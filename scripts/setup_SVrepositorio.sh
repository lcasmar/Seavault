#!/bin/bash
sudo apt update
##############################################
# Instalar MariaDB
##############################################
sudo apt install -y mariadb-server mariadb-client
sudo sed -i 's/^bind-address.*/bind-address=0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mariadb

sudo mysql -u root <<EOF
CREATE DATABASE ccnet_db    CHARACTER SET utf8mb4;
CREATE DATABASE seafile_db  CHARACTER SET utf8mb4;
CREATE DATABASE seahub_db   CHARACTER SET utf8mb4;

CREATE USER 'seavault_adm'@'192.168.56.%' IDENTIFIED BY 'adm';
GRANT ALL PRIVILEGES ON ccnet_db.*   TO 'seavault_adm'@'192.168.56.%';
GRANT ALL PRIVILEGES ON seafile_db.* TO 'seavault_adm'@'192.168.56.%';
GRANT ALL PRIVILEGES ON seahub_db.*  TO 'seavault_adm'@'192.168.56.%';
FLUSH PRIVILEGES;
EOF

##############################################
# Instalar NFS
##############################################
sudo apt install -y nfs-kernel-server

sudo mkdir -p /srv/seavault/seafile-data
sudo mkdir -p /srv/seavault/seahub-data
sudo chown -R nobody:nogroup /srv/seavault/seafile-data
sudo chown -R nobody:nogroup /srv/seavault/seahub-data

echo "/srv/seavault/seafile-data 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports > /dev/null
echo "/srv/seavault/seahub-data 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports > /dev/null
sudo exportfs -ra


##############################################
# Instalar Memcached
##############################################
sudo apt install -y memcached libmemcached-tools

sudo sed -i 's/^-l .*/-l 0.0.0.0/' /etc/memcached.conf
sudo sed -i 's/^-p .*/-p 11211/' /etc/memcached.conf
sudo systemctl restart memcached


##############################################
# 4. Instalar Chrony - NTP
##############################################
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
##############################################
# Instalar Node-exporter
##############################################
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
