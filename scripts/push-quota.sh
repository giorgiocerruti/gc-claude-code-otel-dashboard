#!/bin/bash
# Legge il JSON della statusline di Claude Code da stdin e invia al collector OTLP/HTTP
# la quota usata (finestra 5h e 7d) come gauge. Pensato per essere lanciato in background
# dallo script statusline: non scrive nulla su stdout.
#
#   claude_quota_used_percent{window="5h|7d"}              percentuale usata (0-100)
#   claude_quota_resets_at_timestamp_seconds{window=...}   epoch del prossimo reset
#
# Variabili: OTEL_QUOTA_ENDPOINT (default http://localhost:4318/v1/metrics),
#            OTEL_QUOTA_MIN_INTERVAL secondi tra due invii (default 20)

endpoint="${OTEL_QUOTA_ENDPOINT:-http://localhost:4318/v1/metrics}"
min_interval="${OTEL_QUOTA_MIN_INTERVAL:-20}"
stamp="${TMPDIR:-/tmp}/claude-otel-quota.stamp"

input=$(cat)

# throttle: la statusline si aggiorna spesso
now=$(date +%s)
if [ -f "$stamp" ]; then
  last=$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$min_interval" ] && exit 0
fi

five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
[ -z "$five" ] && [ -z "$week" ] && exit 0
touch "$stamp"

ts=$(( now * 1000000000 ))
point() { # nome finestra valore
  [ -z "$3" ] && return
  printf '{"name":"%s","gauge":{"dataPoints":[{"asDouble":%s,"timeUnixNano":"%s","attributes":[{"key":"window","value":{"stringValue":"%s"}}]}]}}' "$1" "$3" "$ts" "$2"
}
metrics=$(
  { point claude_quota_used_percent 5h "$five"
    point claude_quota_used_percent 7d "$week"
    point claude_quota_resets_at_timestamp_seconds 5h "$five_reset"
    point claude_quota_resets_at_timestamp_seconds 7d "$week_reset"
  } | sed 's/}{"name"/},{"name"/g'
)

curl -s -m 3 -X POST "$endpoint" -H 'Content-Type: application/json' -d \
 "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"claude-statusline\"}}]},\"scopeMetrics\":[{\"metrics\":[${metrics}]}]}]}" >/dev/null 2>&1
exit 0
