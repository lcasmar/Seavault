#!/bin/bash
set -euo pipefail # salir si hay error
# no se puede ejecutar como root
if [ "$EUID" -eq 0 ]; then
  echo "No ejecutes este script como root o con sudo. Usa seavault_adm."
  exit 1
fi
############################################
# Instalar node-exporter
############################################
set -euo pipefail
EXP_VER="1.8.1"

curl -LO https://github.com/prometheus/node_exporter/releases/download/v${EXP_VER}/node_exporter-${EXP_VER}.linux-amd64.tar.gz
tar -xzf node_exporter-${EXP_VER}.linux-amd64.tar.gz
sudo mv node_exporter-${EXP_VER}.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --system --no-create-home --shell /usr/sbin/nologin nodeexp || true

cat <<'EOF' | sudo tee /etc/systemd/system/node_exporter.service > /dev/null
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=nodeexp
Group=nodeexp
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
echo "node_exporter escuchando en :9100"

############################################
# Instalación y configuración de Chrony
############################################

NTP_SERVER="192.168.56.50"
CONF_FILE="/etc/chrony/chrony.conf"

sudo apt-get update -qq
sudo apt-get install -y chrony

#  Elimina líneas pool / server anteriores que no sean la IP deseada
sudo sed -i -E \
    -e "/^(pool|server) /d" \
    -e "/^allow /d" \
    "${CONF_FILE}"

# Añade la línea de servidor si no existe
grep -q "^server ${NTP_SERVER}" "${CONF_FILE}" || \
    echo "server ${NTP_SERVER} iburst" | sudo tee -a "${CONF_FILE}" >/dev/null

sudo systemctl enable --now chrony
sudo systemctl restart chrony

sleep 2
chronyc tracking | head -n 6

############################################
# Instalar NFS y montar recursos compartidos
############################################
sudo apt update
sudo apt install -y nfs-common

 sudo mkdir -p /opt/seavault/seafile-data
 sudo mkdir -p /opt/seavault/seahub-data

sudo mount 192.168.56.30:/srv/seavault/seafile-data /opt/seavault/seafile-data
sudo mount 192.168.56.30:/srv/seavault/seahub-data  /opt/seavault/seahub-data

sudo chown -R seavault_adm:seavault_adm /opt/seavault
sudo chmod 755 /opt/seavault
sudo chmod 755 /opt/seavault/seafile-data
sudo chmod 755 /opt/seavault/seahub-data

# Lineas para agregar
LINE1="192.168.56.30:/srv/seavault/seafile-data /opt/seavault/seafile-data nfs defaults 0 0"
LINE2="192.168.56.30:/srv/seavault/seahub-data  /opt/seavault/seahub-data  nfs defaults 0 0"

grep -qxF "$LINE1" /etc/fstab || echo "$LINE1" | sudo tee -a /etc/fstab > /dev/null
grep -qxF "$LINE2" /etc/fstab || echo "$LINE2" | sudo tee -a /etc/fstab > /dev/null

############################################
# Descarga e instalación Seafile
############################################
# Variables
URL="https://s3.eu-central-1.amazonaws.com/download.seadrive.org/seafile-server_10.0.1_x86-64.tar.gz"
ARCHIVO_TAR="/tmp/$(basename "$URL")"
DEST_DIR="/opt/seavault"
EXTRACTED_DIR="seafile-server-10.0.1"

curl -Lo "$ARCHIVO_TAR" "$URL"
sudo cp "$ARCHIVO_TAR" "$DEST_DIR"
cd "$DEST_DIR" || exit 1
tar -xzf "$(basename "$ARCHIVO_TAR")"
cd "$EXTRACTED_DIR" || exit 1
sudo ./setup-seafile-mysql.sh

############################################
# Arreglando Python
############################################
# Variables
PYTHON_VERSION="3.11"
BASE_DIR="/opt/seavault/seafile-server-10.0.1"
SEAHUB_DIR="$BASE_DIR/seahub"
SEAHUB_SH="$BASE_DIR/seahub.sh"
VENV_DIR="$SEAHUB_DIR/env"
PYTHON_PATH="$VENV_DIR/bin/python"


sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update


sudo apt install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev
sudo apt install -y build-essential default-libmysqlclient-dev pkg-config


cd "$SEAHUB_DIR" || { echo " No se pudo acceder a $SEAHUB_DIR"; exit 1; }
python${PYTHON_VERSION} -m venv env

source "$VENV_DIR/bin/activate"
pip install -r requirements.txt
pip install --no-cache-dir PyMemcache==4.0.0
deactivate

sudo sed -i "s|^ *PYTHON=python3\$|PYTHON=${PYTHON_PATH}|" "$SEAHUB_SH"

############################################
# Configurando seafile
############################################
SEAFILE_DIR="/opt/seavault/seafile-server-10.0.1"
CONF_DIR="/opt/seavault/conf"
SEAHUB_SETTINGS="$CONF_DIR/seahub_settings.py"
GUNICORN_CONF="$CONF_DIR/gunicorn.conf.py"
FILE_SERVER_ROOT="https://seavault.lan/seafhttp"
MEMCACHED_HOST="192.168.56.30:11211"

sudo chown -R seavault_adm:seavault_adm /opt/seavault/conf
if ! grep -q "^FILE_SERVER_ROOT" "$SEAHUB_SETTINGS"; then
    echo "FILE_SERVER_ROOT = '${FILE_SERVER_ROOT}'" | sudo tee -a "$SEAHUB_SETTINGS" > /dev/null
    echo "FILE_SERVER_ROOT añadido."
else
    echo "FILE_SERVER_ROOT ya existe, no se modifica."
fi

if ! grep -q "^CACHES\s*=" "$SEAHUB_SETTINGS"; then
    cat <<EOF | sudo tee -a "$SEAHUB_SETTINGS" > /dev/null

CACHES = {
    'default': {
        'BACKEND':'django.core.cache.backends.memcached.PyMemcacheCache',
        'LOCATION': '${MEMCACHED_HOST}',
    }
}
EOF
    echo "CACHES añadido."
else
    echo "CACHES ya existe, no se modifica."
fi

sudo sed -i 's|^bind *= *".*"|bind = "0.0.0.0:8000"|' "$GUNICORN_CONF"

############################################
# Iniciando Seafile y Seahub
############################################
cd "$SEAFILE_DIR"
./seafile.sh start
./seahub.sh start

sleep 3

curl -I http://192.168.56.10:8000

#EXTRA: Establece permisos por si se conectasen múltiples servidores
sudo chown -R seavault_adm:seavault_adm /opt/seavault/{ccnet,conf}
sudo chmod -R o+rX /opt/seavault/{ccnet,conf}
