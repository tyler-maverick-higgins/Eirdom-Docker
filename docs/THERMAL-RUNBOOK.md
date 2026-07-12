# Thermal incident runbook

The reviewed host reported 91–98 °C while Sonarr and Paperless each consumed approximately one CPU core. A temperature within one degree of the CPU critical threshold is an incident.

1. Stop runaway services.
2. Recheck `sensors` after two minutes.
3. If temperature remains above 90 °C, shut down and inspect fan operation, heatsink seating, dust, thermal compound, and chassis airflow.
4. Do not deploy NetBox or run image builds until idle and sustained-load temperatures are safe.
5. Add temperature monitoring and alerting to Uptime Kuma or the monitoring platform.
