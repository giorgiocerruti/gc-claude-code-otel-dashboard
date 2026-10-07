FROM grafana/grafana:11.4.0
# Accesso anonimo come Admin: pensato SOLO per uso locale (porta legata a 127.0.0.1 nel compose)
ENV GF_AUTH_ANONYMOUS_ENABLED=true \
    GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
    GF_AUTH_DISABLE_LOGIN_FORM=true \
    GF_ANALYTICS_REPORTING_ENABLED=false \
    GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/dashboards/claude-code-metrics.json
COPY provisioning /etc/grafana/provisioning
COPY dashboards /etc/grafana/dashboards
