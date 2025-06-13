#!/bin/bash
set -euo pipefail
############################################
# Variables
############################################
NODE1="192.168.56.10"
NODE1_USER="seavault_adm"
NFS_SERVER="192.168.56.30"
BASE="/opt/seavault"
SEAF_VER="10.0.1"
TAR_URL="https://s3.eu-central-1.amazonaws.com/download.seadrive.org/seafile-server_${SEAF_VER}_x86-64.tar.gz"
PY_VER="3.11"

## Comprobar que no se ejecuta el script como root
if [ "$EUID" -eq 0 ]; then
  echo "Ejecútame como usuario seavault_adm, no como root."
  exit 1
fi
############################################
# Instalación dependencias
############################################
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y \
  nfs-common chrony mariadb-client \
  python${PY_VER} python${PY_VER}-venv python${PY_VER}-dev \
  build-essential default-libmysqlclient-dev curl tar
############################################
# Montando NFS
############################################
sudo mkdir -p $BASE/seafile-data $BASE/seahub-data
grep -qxF "$NFS_SERVER:/srv/seavault/seafile-data $BASE/seafile-data nfs defaults 0 0" /etc/fstab \
  || echo "$NFS_SERVER:/srv/seavault/seafile-data $BASE/seafile-data nfs defaults 0 0" | sudo tee -a /etc/fstab >/dev/null
grep -qxF "$NFS_SERVER:/srv/seavault/seahub-data  $BASE/seahub-data  nfs defaults 0 0" /etc/fstab \
  || echo "$NFS_SERVER:/srv/seavault/seahub-data  $BASE/seahub-data  nfs defaults 0 0" | sudo tee -a /etc/fstab >/dev/null
sudo mount -a
############################################
# Descargar Seafile
############################################
sudo mkdir -p $BASE
sudo chown -R $USER:$USER $BASE
curl -L $TAR_URL -o /tmp/seafile.tar.gz
tar -xzf /tmp/seafile.tar.gz -C $BASE
rm /tmp/seafile.tar.gz
############################################
# Ajustar permisos remotos
############################################
scp -r ${NODE1_USER}@${NODE1}:/opt/seavault/{ccnet,conf} $BASE/
chown -R $USER:$USER $BASE/ccnet $BASE/conf
############################################
# Arreglar Python
############################################
cd $BASE/seafile-server-${SEAF_VER}/seahub
if [ ! -x env/bin/python ]; then
  python${PY_VER} -m venv env
  source env/bin/activate
  pip install -r requirements.txt
  pip install PyMemcache
fi

sed -i "s|^ *PYTHON=.*|PYTHON=$(pwd)/env/bin/python|" ../seahub.sh
############################################
# Instalación y configuración de Chrony
############################################
NTP_SERVER="192.168.56.50"
CONF_FILE="/etc/chrony/chrony.conf"

sudo apt-get update -qq
sudo apt-get install -y chrony

echo "Configurando ${NTP_SERVER} como servidor NTP único…"
# 1. Elimina líneas pool / server anteriores que no sean la IP deseada
sudo sed -i -E \
    -e "/^(pool|server) /d" \
    -e "/^allow /d" \
    "${CONF_FILE}"

# 2. Añade la línea de servidor si no existe
grep -q "^server ${NTP_SERVER}" "${CONF_FILE}" || \
    echo "server ${NTP_SERVER} iburst" | sudo tee -a "${CONF_FILE}" >/dev/null
sudo systemctl enable --now chrony
sudo systemctl restart chrony

sleep 2
echo "Sincronización rápida (tracking)…"
chronyc tracking | head -n 6
############################################
# Instalación y configuración de node-exporter
############################################
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
############################################
# Arrancando
############################################
cd $BASE/seafile-server-${SEAF_VER}
./seafile.sh start
./seahub.sh  start

sleep 3
curl -I http://192.168.56.20:8000 || {
  echo "ERROR; revisa logs en logs/*.log"
  exit 1
}

echo "Nodo2 listo."
