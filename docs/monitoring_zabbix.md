# Monitoring Zabbix with Prometheus & Grafana

This guide describes how to monitor a Zabbix instance using the Zabbix Prometheus exporter, Prometheus, and Grafana.

What this adds
- A Docker Compose file (infra/monitoring/docker-compose.monitoring.yml) that runs Prometheus, Grafana, Loki, and the Zabbix Prometheus exporter.
- Prometheus config with a scrape job for the zabbix_exporter (infra/monitoring/prometheus/prometheus.yml).
- An alert rule to notify when the zabbix_exporter is down (infra/monitoring/prometheus/alerts.yml).
- A Grafana dashboard (infra/monitoring/grafana/dashboards/zabbix_overview.json) and provisioning files to load the dashboard automatically.

How it works
1. zabbix_exporter connects to your Zabbix API using credentials (ZABBIX_URL, ZABBIX_USER, ZABBIX_PASSWORD) and exposes metrics at http://zabbix_exporter:9116/metrics.
2. Prometheus scrapes the exporter and stores metrics.
3. Grafana displays dashboards and panels based on Prometheus metrics.
4. Alerts are defined in alerts.yml — configure Alertmanager or webhook integrations as needed.

Quick start (local)
1. Create a .env file in the repository root containing:

   ZABBIX_URL="https://your-zabbix.example.com/api_jsonrpc.php"
   ZABBIX_USER="your_zabbix_user"
   ZABBIX_PASSWORD="your_password"

2. Start the monitoring stack:

   docker compose -f infra/monitoring/docker-compose.monitoring.yml up -d

3. Visit Grafana at http://localhost:3000 (admin/admin). The Zabbix Overview dashboard will be provisioned automatically.

4. Visit Prometheus at http://localhost:9090 to query metrics. Example query to check exporter status:

   up{job="zabbix_exporter"}

Alerting
- The provided alert rule ZabbixExporterDown fires when up{job="zabbix_exporter"} == 0 for 2 minutes.
- To receive notifications, configure Alertmanager and add the alertmanager URL to Prometheus (not included in the compose file by default).

Notes & next steps
- The zabbix_exporter requires a user with read access to the Zabbix API.
- If you run Zabbix locally in Docker, you can point ZABBIX_URL to the container address.
- You can extend the Grafana dashboard with panels that visualize specific Zabbix metrics exported (items, triggers, etc.). Refer to the exporter docs for metric names.
