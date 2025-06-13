# Manual monitorización con Prometheus + Grafana
## Prometheus
Prometheus es un software especializado como sistema de monitorización y alertas. Prometheus consulta endpoints de servicios que exponen métricas en /metrics, guarda esos datos en su base de datos interna como series temporales. Es posible consultar esas métricas desde la interfaz web conectandolo a Grafana, donde también se pueden configurar alertas que se disparen cuando ciertas condiciones se cumplan.

## 1. Entorno
Este manual se ha concebido y elaborado específicamente para un entorno compuesto por máquinas virtuales en VirtualBox que ejecutan distintas ediciones de Ubuntu.

| Host | Rol | Paquetes necesarios |
|------|-----|--------------------|
| SVmonitor | Prometheus + Grafana | `prometheus` `grafana` `node-exporter` |
| Todos los nodos | Exportar métricas | `node-exporter` |
---
## 2. Instalación (Ubuntu 22.04)
### 2.1. SVmonitor
```bash
# ---------- Prometheus ----------
curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest \
| grep browser_download_url | grep linux-amd64 \
| cut -d '"' -f 4 | wget -qi -
tar -xzf prometheus-*.tar.gz
sudo mv prometheus-*/{prometheus,promtool} /usr/local/bin/
sudo useradd -rs /bin/false prometheus
sudo mkdir /etc/prometheus /var/lib/prometheus
sudo mv prometheus-*/consoles prometheus-*/console_libraries /etc/prometheus

# ---------- Prometheus service ----------
cat <<'EOF' | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now prometheus

# ---------- Grafana ----------
sudo apt-get install -y apt-transport-https software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt-get update && sudo apt-get install -y grafana
sudo systemctl enable --now grafana-server
```
### 2.2. En cada nodo
```bash
# ---------- Node exporter ----------
useradd -rs /bin/false node_exporter
curl -LO https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
sudo mv node_exporter-*/node_exporter /usr/local/bin/

cat <<'EOF' | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now node_exporter
```

## 3. Paneles Grafana para SeaVault 
### 3.1. Añadir _data-source_: Prometheus
1. Iniciar sesión en Grafana (`http://SVmonitor:3000`, admin/admin).  
2. Gear → Data sources → Add data source.  
3. Seleccionar Prometheus y poner la URL `http://localhost:9090`.  
4. Save & test

---
### 3.2. Crear un _Dashboard_
1. Create → Dashboard →Add a new panel.  
2. Elegir como data-source Prometheus.  
3. Escribir la primera consulta:
   ```promql
   rate(node_cpu_seconds_total{mode!="idle"}[5m]) * 100
   ```
4. Cambiar la visualización a Gauge → Title = “CPU %”.
5. Apply.

### 3.3. Paneles básicos recomendados
| Métrica                | Consulta PromQL                                                             | Vista       |
| ---------------------- | --------------------------------------------------------------------------- | ----------- |
| CPU %              | `rate(node_cpu_seconds_total{mode!="idle",instance="$instance"}[5m]) * 100` | Gauge       |
| RAM usada (GB)     | `(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1e9`       | Time series |
| Disco usado %      | `100 - (node_filesystem_free_bytes / node_filesystem_size_bytes * 100)`     | Gauge       |
| Latencia login p95 | `histogram_quantile(0.95, rate(seafile_login_duration_seconds_bucket[5m]))` | Bar gauge   |
| Subida MB/s       | `rate(seafile_upload_bytes_total[1m]) / 1e6`                                | Time series |
| Eventos fail-over  | `changes(up{job="seavault_nodes"}[5m])`                                     | Stat        |

### 3.4. Crear alertas en Grafana
1. Editar el panel deseado → pestaña Alert → Create alert rule.
2. Query A.
```promql
changes(up{instance="$instance"}[2m]) > 0
Condition = “is above 0” durante 1 min.
```
3. Elegir notificador (e-mail, Slack, Telegram…).
4. Save. 
5. Aparece en Alerting → Rules.
