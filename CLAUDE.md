# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Docker Compose stack for monitoring Claude Code token/cost usage. No application code, no tests, no linter. The repo is config plus one Grafana dashboard JSON. Docs (README) are written in Italian; keep that language for README and user-facing comments.

Pipeline: `Claude Code --OTLP :4317/:4318--> otel-collector --:8889--> Prometheus :9090 --> Grafana :3000`. All ports bound to 127.0.0.1.

## Commands

```bash
docker compose up -d --build        # start / rebuild after ANY config or dashboard change
docker compose logs -f otel-collector
docker compose down                 # keep data; `down -v` wipes prom-data and graf-data volumes
curl -s localhost:9090/api/v1/label/__name__/values | tr ',' '\n' | grep claude_code   # verify metrics arrive
```

Prometheus and Grafana configs are baked into images (`prometheus/Dockerfile`, `grafana/Dockerfile`), not bind-mounted. Only the collector config is mounted. So editing prometheus/grafana files needs `--build`.

## Architecture notes

- `otel-collector/otel-collector.yml`: the `deltatocumulative` processor is mandatory. Claude Code exports delta counters; the Prometheus exporter drops them without it (token/cost metrics vanish, sessions/active time still work). `resource_to_telemetry_conversion` turns resource attributes (e.g. `project.name`) into Prometheus labels (`project_name`).
- `grafana/dashboards/claude-code-metrics.json`: single ~70KB provisioned dashboard, set as home via env in `grafana/Dockerfile`. Datasource is pinned to the local Prometheus (`grafana/provisioning/datasources/prom.yml`). Grafana runs anonymous-Admin, local use only. Upstream dashboard by rockdarko (MIT), extended with quota/project/agent/model panels.
- `scripts/` run on the user's machine, not in containers. Metrics from Claude Code OTel lack quota and project, so:
  - `push-quota.sh`: called from the Claude Code statusline, reads `rate_limits` JSON from stdin, POSTs gauges `claude_quota_used_percent` and `claude_quota_resets_at_timestamp_seconds` (label `window`=`5h`|`7d`) to collector OTLP/HTTP `:4318`. Throttled via a stamp file in `$TMPDIR`.
  - `claude-otel-project.zsh`: shell function wrapping `claude`, sets `OTEL_RESOURCE_ATTRIBUTES=project.name=<git repo or dir name>`.
- Dashboard panels show `(non assegnato)` / `(sessione principale)` for empty `project_name` / `agent_name`; preserve that when editing queries.
- Time-series panels plot rates; legend `Total` is not a real total. Use stat panels for totals.
- Per-project/agent/model "% quota 7d" panels are estimates (7d cost share x weekly quota used), not exact.

## Editing the dashboard

Dashboard is raw exported Grafana JSON. Edit via Grafana UI then export, or edit JSON directly and validate with `python3 -m json.tool`. Rebuild grafana image to apply. When metric labels change, update the "Metriche principali" table in README.
