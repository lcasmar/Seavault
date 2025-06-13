#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update -qq
sudo apt-get install -y ufw
sudo ufw --force reset
############################################
# Políticas por defecto
############################################
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed  
############################################
# Reglas INPUT para SVgateway
############################################
LAN_NET="192.168.56.0/24"
PROM_IP="192.168.56.40"

# SSH (solo LAN)
sudo ufw allow from $LAN_NET to any port 22 proto tcp

# HTTP/HTTPS  (balanceador público)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# DNS local
sudo ufw allow from $LAN_NET to any port 53 proto tcp
sudo ufw allow from $LAN_NET to any port 53 proto udp

# NTP servidor
sudo ufw allow from $LAN_NET to any port 123 proto udp

# node_exporter
sudo ufw allow from $PROM_IP to any port 9100 proto tcp
############################################
# Habilitar IP forwarding (persistente)
############################################
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/ufw/sysctl.conf
############################################
# Eliminar MASQUERADE en iptables
############################################
WAN_IF=$(ip route | awk '/default/ {print $5; exit}')
sudo iptables -t nat -D POSTROUTING -s 192.168.56.0/24 -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
if [ -f /etc/iptables/rules.v4 ]; then
  sudo sed -i '/\-A POSTROUTING \-s 192\.168\.56\.0\/24 .* MASQUERADE/d' /etc/iptables/rules.v4
fi
############################################
# Insertar MASQUERADE en before.rules si no existe
############################################
RULE_EXISTS=$(grep -c "MASQUERADE -s 192.168.56.0/24" /etc/ufw/before.rules || true)
if [ "$RULE_EXISTS" -eq 0 ]; then
  sudo sed -i "1s|^|*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 192.168.56.0/24 -o ${WAN_IF} -j MASQUERADE\nCOMMIT\n\n|" /etc/ufw/before.rules
fi
############################################
# Habilitar UFW
############################################
echo "y" | sudo ufw enable
sudo ufw reload
sudo ufw status verbose
############################################
# Verificación rápida
############################################
sudo iptables -t nat -S | grep MASQUERADE
echo " Firewall UFW aplicado; NAT gestionado ahora por UFW."
############################################################################
# Instala Fail2ban
############################################################################
sudo apt update -qq
sudo apt install -y fail2ban
############################################################################
# Configura el archivo jail.local
############################################################################
JAIL_LOCAL="/etc/fail2ban/jail.local"
if [ ! -e "$JAIL_LOCAL" ]; then
sudo tee "$JAIL_LOCAL" >/dev/null <<'EOF'
[DEFAULT]
banaction   = ufw
bantime     = 1h
findtime    = 10m
maxretry    = 5
backend     = systemd
ignoreip    = 127.0.0.1/8 192.168.56.0/24

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s

[nginx-http]
enabled  = true
filter   = nginx-http-auth
port     = http,https
maxretry = 20
findtime = 120
bantime  = 30m
logpath  = /var/log/nginx/access.log

[nginx-https]
enabled  = true
filter   = nginx-limit-req
port     = http,https
maxretry = 20
findtime = 120
bantime  = 30m
logpath  = /var/log/nginx/error.log
EOF
fi
############################################################################
#Habilitar el backend ufw
############################################################################
sudo ufw --force enable
############################################################################
# Reiniciar Fail2Ban 
############################################################################
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status

echo "Fail2Ban instalado y protegiendo SSH + Nginx."
