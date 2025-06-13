#!/bin/bash
set -e
############################################
# Instalación y configuración de Chrony
############################################
sudo apt update
sudo apt install -y chrony
sudo systemctl enable --now chrony
sudo sed -i '/^pool /d' /etc/chrony/chrony.conf
echo "allow 192.168.56.0/24" | sudo tee -a /etc/chrony/chrony.conf
sudo systemctl restart chrony
############################################
# Configurando nginx / balanceador de carga
############################################
sudo apt install -y nginx
cat <<EOF | sudo tee /etc/nginx/sites-available/seavault > /dev/null
upstream seafile_cluster {
    server 192.168.56.10:8000 max_fails=3 fail_timeout=30s;
    server 192.168.56.20:8000 max_fails=3 fail_timeout=30s;
}

upstream seafile_fileserver {
    server 192.168.56.10:8082 max_fails=3 fail_timeout=30s;
    server 192.168.56.20:8082 max_fails=3 fail_timeout=30s;
}

server {
    listen 443 ssl;
    server_name seavault.lan;

    ssl_certificate     /etc/ssl/certs/seavault.crt;
    ssl_certificate_key /etc/ssl/private/seavault.key;

    location / {
        proxy_pass http://seafile_cluster;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /seafhttp {
        rewrite ^/seafhttp(.*)\$ \$1 break;
        proxy_pass http://seafile_fileserver;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 36000s;
        proxy_read_timeout 36000s;
        proxy_request_buffering off;
    }
}

server {
    listen 80;
    server_name seavault.lan;
    return 301 https://\$host\$request_uri;
}
EOF
############################################
# Configurando HTTPS
############################################
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/seavault.key \
  -out /etc/ssl/certs/seavault.crt \
  -subj "/C=ES/ST=Seafile/L=LAN/O=seavault/CN=seavault.lan"

############################################
# Activando sitio
############################################
sudo ln -s /etc/nginx/sites-available/seavault /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

############################################
# Configurando DNS local con dnsmasq
############################################
sudo apt install -y dnsmasq

sudo mkdir -p /etc/dnsmasq.hosts
cat <<EOF | sudo tee /etc/dnsmasq.hosts/lan_hosts > /dev/null
192.168.56.10 SVserver01 SVserv01.lan
192.168.56.20 SVserver02 SVserv01.lan
192.168.56.50 SVgateway seavault.lan
192.168.56.50 SVrepositorio SVrep.lan
192.168.56.50 SVmonitor SVmonitor.lan
EOF


cat <<EOF | sudo tee /etc/dnsmasq.conf > /dev/null
domain-needed
bogus-priv
no-resolv
addn-hosts=/etc/dnsmasq.hosts/lan_hosts
server=8.8.8.8
EOF

sudo systemctl restart dnsmasq

############################################
# Activando NAT
############################################
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE

sudo apt install -y iptables-persistent

############################################
# Instalación node-exporter
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
echo "Gateway listo: DNS, router, NTP, balanceo Seafile y node-exporter funcionando."
