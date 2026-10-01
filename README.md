# GC Claude Code OTel Dashboard

Stack Docker pronto all'uso per capire **dove vanno i token di Claude Code**: costo e token per modello, sessione, tipo (input / output / cache read / cache write), cache hit ratio, subagent vs sessione principale, attivita' e produttivita'.

```
Claude Code --OTLP gRPC :4317--> OpenTelemetry Collector --:8889--> Prometheus :9090 --> Grafana :3000
```

Tutto gira in locale. Nessun dato lascia la tua macchina.

## Screenshot

### 1. Overview

Colpo d'occhio sul periodo selezionato: sessioni, costo e token totali, commit, righe di codice, tempo attivo. **Tokens by Type** mostra la proporzione tra input, output, cache read e cache creation. **Cache hit ratio** indica quanto contesto viene riletto dalla cache invece di essere rielaborato. In alto i filtri Organization, User e Model valgono per tutta la dashboard.

![Overview](docs/images/01-overview.png)

### 2. Leaderboard

Chi e cosa consuma di piu': utenti e sessioni per costo e token, costo per modello, decisioni sugli edit per linguaggio, sessioni per terminale. Serve a individuare le sessioni "pesanti" e a vedere quanto pesa un modello costoso come Opus rispetto a Sonnet o Haiku.

![Leaderboard](docs/images/02-leaderboards.png)

### 3. Costi e token

L'andamento nel tempo (rate in dollari/ora e token/s) per modello e per tipo di token. In fondo i due pannelli piu' utili per capire gli sprechi: **Cost by query_source** separa `main`, `subagent` e `auxiliary`, **Cost by effort** separa i livelli di effort del modello.

![Costi e token](docs/images/03-cost-tokens.png)

### 4. Attivita' e produttivita'

Tempo attivo, righe di codice aggiunte e rimosse, decisioni accept / reject sui tool. Utile per mettere in relazione il consumo con il lavoro prodotto.

![Attivita'](docs/images/04-activity.png)

## Cosa c'e' dentro

| Servizio | Immagine | Ruolo |
|---|---|---|
| `otel-collector` | `otel/opentelemetry-collector-contrib` | Riceve OTLP da Claude Code, converte i contatori delta in cumulativi, li espone a Prometheus |
| `prometheus` | `prometheus/Dockerfile` (base `prom/prometheus`) | Scrape ogni 15 s, retention 90 giorni |
| `grafana` | `grafana/Dockerfile` (base `grafana/grafana`) | Datasource e dashboard gia' provisioned |

La dashboard e' [Claude Code Metrics (Prometheus)](https://grafana.com/grafana/dashboards/25255) di rockdarko ([repo](https://github.com/rockdarko/claude-code-metrics-prometheus), licenza MIT), con il datasource fissato all'istanza locale.

## Requisiti

- Docker con Docker Compose v2
- Claude Code con accesso a `~/.claude/settings.json`

## Installazione

1. Avvia lo stack:

   ```bash
   git clone https://github.com/giorgiocerruti/gc-claude-code-otel-dashboard.git
   cd gc-claude-code-otel-dashboard
   docker compose up -d --build
   ```

2. Abilita la telemetria in Claude Code. Aggiungi queste variabili al blocco `env` di `~/.claude/settings.json` (vedi `settings.example.json`):

   ```json
   {
     "env": {
       "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
       "OTEL_METRICS_EXPORTER": "otlp",
       "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
       "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
       "OTEL_METRIC_EXPORT_INTERVAL": "15000"
     }
   }
   ```

3. **Riavvia Claude Code.** Le sessioni aperte non rileggono le variabili.

4. Apri http://localhost:3000. La dashboard e' la home.

I primi dati compaiono 1-2 minuti dopo la prima risposta del modello in una sessione avviata dopo il passo 3.

## Porte

Tutte le porte sono legate a `127.0.0.1`.

| Porta | Servizio |
|---|---|
| 3000 | Grafana |
| 9090 | Prometheus |
| 4317 / 4318 | OTLP gRPC / HTTP |

## Verifica

```bash
curl -s localhost:9090/api/v1/label/__name__/values | tr ',' '\n' | grep claude_code
```

Devono comparire, tra le altre, `claude_code_token_usage_tokens_total` e `claude_code_cost_usage_USD_total`.

## Metriche principali

| Metrica | Label utili |
|---|---|
| `claude_code_token_usage_tokens_total` | `type`, `model`, `session_id`, `query_source`, `agent_name`, `mcp_server_name`, `effort` |
| `claude_code_cost_usage_USD_total` | `model`, `session_id`, `query_source`, `agent_name`, `mcp_server_name`, `effort` |
| `claude_code_session_count_total` | |
| `claude_code_active_time_seconds_total` | |
| `claude_code_lines_of_code_count_total`, `claude_code_commit_count_total`, `claude_code_pull_request_count_total`, `claude_code_code_edit_tool_decision_total` | |

Il costo e' una stima calcolata dal client, vicina ma non identica alla fatturazione. Con i piani a limite settimanale conta il consumo, non i dollari: usalo come confronto relativo tra modelli, sessioni e subagent.

Il pannello **Cost by query_source** separa sessione principale (`main`), `subagent` e `auxiliary`: e' il modo piu' rapido per vedere se sono i subagent a consumare il limite.

## Query utili

Token "pesanti" (senza cache read) per modello, ultimi 7 giorni:

```
sum by (model) (increase(claude_code_token_usage_tokens_total{type!="cacheRead"}[7d]))
```

Sessioni piu' costose, ultimi 7 giorni:

```
topk(10, sum by (session_id) (increase(claude_code_cost_usage_USD_total[7d])))
```

Costo per agente (`agent_name`), ultimi 7 giorni:

```
topk(10, sum by (agent_name) (increase(claude_code_cost_usage_USD_total[7d])))
```

Quota di costo dei subagent:

```
sum(increase(claude_code_cost_usage_USD_total{query_source="subagent"}[7d])) / sum(increase(claude_code_cost_usage_USD_total[7d]))
```

## Note e limiti

- **Storico.** I dati partono dal momento dell'attivazione. OTel non recupera il passato.
- **Grafici temporali.** I pannelli "Over Time" e "Usage by ..." mostrano un rate (dollari/ora, token/s). La colonna `Total` nella legenda somma i campioni del rate e non e' un totale reale: per il totale usa gli stat in alto (`Total Cost`, `Total Tokens`).
- **`deltatocumulative`.** Claude Code esporta contatori delta. L'exporter Prometheus non li accetta, quindi senza il processor in `otel-collector/otel-collector.yml` le metriche token e costo non compaiono (sessioni e tempo attivo si').
- **Accesso Grafana.** E' anonimo come Admin, pensato solo per uso locale. Non esporre la porta 3000 su una rete.
- **Privacy.** Le metriche includono `user_email`, `organization_id` e `session_id`. Non pubblicare screenshot senza aver controllato i pannelli dei leaderboard.

## Gestione

```bash
docker compose ps            # stato
docker compose logs -f otel-collector
docker compose down          # stop, i dati restano nei volumi
docker compose down -v       # stop e cancella tutti i dati
```

## Troubleshooting

- Nessuna metrica `claude_code_*`: controlla `docker compose ps` e i log del collector (logga ogni batch ricevuto).
- Pannelli vuoti: controlla l'intervallo di tempo e i filtri Organization / User / Model.
- Porta occupata: cambia la porta host in `docker-compose.yml`.
- Dopo aver modificato la dashboard o la config: `docker compose up -d --build`.

## Licenza

MIT. La dashboard originale e' di rockdarko, anch'essa MIT.
