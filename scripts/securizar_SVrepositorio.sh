#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update -qq
sudo apt-get install -y ufw
sudo ufw --force reset 

############################################
# Variables de red
############################################
LAN_NET="192.168.56.0/24"
NODE1="192.168.56.10"      
NODE2="192.168.56.20"           
GW="192.168.56.50"               
PROM="192.168.56.40"              

############################################
# Políticas por defecto
############################################
sudo ufw default deny incoming
sudo ufw default allow outgoing   

############################################
# Reglas INPUT
############################################
## SSH desde la LAN
sudo ufw allow from $LAN_NET to any port 22 proto tcp comment 'SSH LAN'

## MariaDB / nodos Seafile
sudo ufw allow from $NODE1 to any port 3306 proto tcp comment 'MariaDB node1'
sudo ufw allow from $NODE2 to any port 3306 proto tcp comment 'MariaDB node2'

## NFS (2049) + portmap (111) / LAN
sudo ufw allow from $LAN_NET to any port 2049 proto tcp comment 'NFS TCP'
sudo ufw allow from $LAN_NET to any port 2049 proto udp comment 'NFS UDP'
sudo ufw allow from $LAN_NET to any port 111  proto tcp comment 'Portmap TCP'
sudo ufw allow from $LAN_NET to any port 111  proto udp comment 'Portmap UDP'

## Memcached / nodos Seafile
sudo ufw allow from $NODE1 to any port 11211 proto tcp comment 'Memcached node1'
sudo ufw allow from $NODE2 to any port 11211 proto tcp comment 'Memcached node2'

## node_exporter / Prometheus
sudo ufw allow from $PROM to any port 9100 proto tcp comment 'node_exporter'

## NTP (Chrony cliente)
sudo ufw allow from $GW to any port 123 proto udp comment 'NTP from gateway'

############################################
# Habilitar
############################################
echo "y" | sudo ufw enable
sudo ufw reload
sudo ufw status verbose

echo "UFW configurado: BD/NFS segura"
