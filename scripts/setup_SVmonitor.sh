#!/usr/bin/env bash
set -euo pipefail
PROM_VER="2.52.0"          # ajusta versión estable si lo deseas
GRAF_VER="11.0.0"          # grafana OSS
NODE_EXPORTERS=(192.168.56.10 192.168.56.20 192.168.56.30 192.168.56.50)

############################################
# Instalar dependencias
############################################
sudo apt update
sudo apt install -y curl tar adduser libfontconfig1

###############################################################################
# Instalar y configurarPrometheus
###############################################################################

curl -LO https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-amd64.tar.gz
tar -xzf prometheus-${PROM_VER}.linux-amd64.tar.gz
sudo mv prometheus-${PROM_VER}.linux-amd64 /opt/prometheus
sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus || true
sudo chown -R prometheus:prometheus /opt/prometheus


cat <<EOF | sudo tee /opt/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: 'seavault_nodes'
    static_configs:
      - targets: [$(printf "'%s:9100'," "${NODE_EXPORTERS[@]}" | sed 's/,$//')]
EOF
sudo chown prometheus:prometheus /opt/prometheus/prometheus.yml


cat <<'EOF' | sudo tee /etc/systemd/system/prometheus.service > /dev/null
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --web.console.templates=/opt/prometheus/consoles \
  --web.console.libraries=/opt/prometheus/console_libraries
Restart=always

[Install]
WantedBy=multi-user.target
EOF

###############################################################################
# Instalar y configurar Grafana
###############################################################################
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana=${GRAF_VER}*

###############################################################################
# 3. Instalar Chrony
###############################################################################
NTP_SERVER="192.168.56.50"
CONF_FILE="/etc/chrony/chrony.conf"

sudo apt-get update -qq
sudo apt-get install -y chrony

sudo sed -i -E \
    -e "/^(pool|server) /d" \
    -e "/^allow /d" \
    "${CONF_FILE}"

grep -q "^server ${NTP_SERVER}" "${CONF_FILE}" || \
    echo "server ${NTP_SERVER} iburst" | sudo tee -a "${CONF_FILE}" >/dev/null

sudo systemctl enable --now chrony
sudo systemctl restart chrony

sleep 2
chronyc tracking | head -n 6

###############################################################################
# Habilitar y arrancar servicios
###############################################################################
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
sudo systemctl enable --now grafana-server

echo "   - URL Prometheus: http://192.168.56.40:9090"
echo "   - URL Grafana   : http://192.168.56.40:3000  (user: admin / pass: admin)"

