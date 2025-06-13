# Manual de instalación manual para un clúster de dos nodos de seafile.
## Topología de referencia
| Host            | IP            | Rol                               | Puertos |
|-----------------|---------------|-----------------------------------|---------|
| **SVrepositorio**  | 192.168.56.30 | MariaDB · NFS · Memcached         | 3306 · 2049 · 11211 |
| **SVserver-01**   | 192.168.56.10 | Seafile (activo)                  | 8000 |
| **SVserver-02**   | 192.168.56.20 | Seafile (respaldo / activo)       | 8000 |
| **SVgateway**     | 192.168.56.50 | dnsmasq + nginx load-balancer     | 80 (→ 443) |

---
## Servicios preinstalados
Todas las máquinas tienen OpenSSH-server instalado previamente para poder acceder a ellas a través de la consola de comandos.
## 1. `SVrepositorio`
En la máquina SVrepositorio se deben instalar y configurar: MariaDB, NFS, Memcached y Chrony
### 1.1 MariaDB
Qué hace: guarda usuarios, metadatos y configuración.  
Por qué: Seafile separa datos (archivos) y lógica; la BD garantiza consistencia y búsquedas rápidas.  

Instrucciones:
1) Instala mariadb-server mariadb-client. 
2) Cambia bind-address a 0.0.0.0. 
3) Reinicia y abre puerto 3306. 
4) Crea las tres BD y el usuario seavault_adm con privilegios completos.

```bash
sudo apt update
sudo apt install -y mariadb-server mariadb-client
sudo sed -i 's/^bind-address.*/bind-address=0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mariadb
sudo ufw allow 3306/tcp
```
```bash
CREATE DATABASE ccnet_db    CHARACTER SET utf8mb4;
CREATE DATABASE seafile_db  CHARACTER SET utf8mb4;
CREATE DATABASE seahub_db   CHARACTER SET utf8mb4;

CREATE USER 'seavault_adm'@'192.168.56.%' IDENTIFIED BY 'adm';
GRANT ALL PRIVILEGES ON ccnet_db.*   TO 'seavault_adm'@'192.168.56.%';
GRANT ALL PRIVILEGES ON seafile_db.* TO 'seavault_adm'@'192.168.56.%';
GRANT ALL PRIVILEGES ON seahub_db.*  TO 'seavault_adm'@'192.168.56.%';
FLUSH PRIVILEGES;
```
### 1.2 NFS
Qué hace: exporta un directorio compartido por red.  
Por qué: ambos nodos Seafile necesitan ver la misma carpeta de datos para evitar divergencias.
1) Instala nfs-kernel-server. 
2) Crea carpetas /srv/seavault/*. 
3) Añade las líneas a /etc/exports con rw,sync,no_root_squash. 
4) Ejecuta exportfs -ra y permite 2049/TCP.
```bash
sudo apt install -y nfs-kernel-server
sudo mkdir -p /srv/seavault/seafile-data
sudo mkdir -p /srv/seavault/seahub-data
sudo chown -R nobody:nogroup /srv/seavault/seafile-data
sudo chown -R nobody:nogroup /srv/seavault/seahub-data
echo "/srv/seavault/seafile-data 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
echo "/srv/seavault/seahub-data  192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo ufw allow 2049/tcp
```
### 1.3 Memcached
Qué hace: cachea consultas frecuentes en RAM.  
Por qué: acelera la respuesta y libera carga a MariaDB.  
1) Instala memcached. 
2) Configura para escuchar en 0.0.0.0:11211. 
3) Reinicia servicio y abre el puerto.

```bash
sudo apt install -y memcached libmemcached-tools
sudo sed -i 's/^-l .*/-l 0.0.0.0/' /etc/memcached.conf
sudo sed -i 's/^-p .*/-p 11211/'    /etc/memcached.conf
sudo systemctl restart memcached
sudo ufw allow 11211/tcp
```
### 1.4  Sincronía horaria con Chrony
Qué hace: sincroniza el reloj con la pasarela NTP.  
Por qué: los mismos timestamps en todos los hosts evitan errores en tokens, certificados y auditoría.  
1) Instala chrony.
2) Apunta a server 192.168.56.50 iburst. 
3) Arranca y habilita al inicio.
```bash
sudo apt install -y chrony
sudo systemctl enable --now chrony
En las maquinas : /etc/chrony/chrony.conf "server 192.168.56.50 iburst"
```
## 1. server-01 – Primer nodo
### 2.1  Montar NFS
Por qué: enlaza el almacenamiento compartido /srv/seavault del repositorio en /opt/seavault.
1) Instala nfs-common. 
2) Crea /opt/seavault/*. 
3) Monta exports de 192.168.56.30 y confirma con df -h.
```bash
sudo apt install -y nfs-common
sudo mkdir -p /opt/seavault/seafile-data
sudo mkdir -p /opt/seavault/seahub-data
sudo mount 192.168.56.30:/srv/seavault/seafile-data /opt/seavault/seafile-data
sudo mount 192.168.56.30:/srv/seavault/seahub-data  /opt/seavault/seahub-data
sudo chown -R seavault_adm:seavault_adm /opt/seavault
```
### 2.2  Instalar Seafile
Por qué: crea los servicios seaf-server, seahub y fileserver que atienden a los clientes.
1) Descarga el tar de Seafile. 
2) Descomprime y lanza setup-seafile-mysql.sh apuntando a la BD externa y a las rutas NFS.
```bash
curl -LO https://s3.eu-central-1.amazonaws.com/download.seadrive.org/seafile-server_10.0.1_x86-64.tar.gz
tar -xzf seafile-server_10.0.1_x86-64.tar.gz
cd seafile-server-10.0.1
./setup-seafile-mysql.sh            # usa BD 192.168.56.30 y /srv/nfs/seavault-data
```
### 2.3 Solucionar errores dependencias
Por qué: la versión incluida en el instalador puede ser antigua; se usa Python 3.11 para compatibilidad y seguridad.
1) Agrega PPA de Deadsnakes. 
2) Instala Python 3.11 + dev libs. 
3) Crea venv en seahub/env y ejecuta pip install -r requirements.txt.
```bash
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update 
sudo apt install python3.11 python3.11-venv python3.11-dev
sudo apt install build-essential default-libmysqlclient-dev pkg-config
cd ~/seafile-server-10.0.1/seahub
python3.11 -m venv env
source env/bin/activate
pip install -r requirements.txt
pip install -r PyMemcache
nano ~/seafile-server-10.0.1/seahub.sh
# Modificamos esta linea PYTHON=/opt/seavault/seafile-server-10.0.1/seahub/env/bin/python  
```
### 2.4  Configurar Seafile-Server
Por qué: se definen URL pública, clave secreta común, uso de Memcached y binding en 0.0.0.0 para aceptar tráfico del LB.  
1) Ajusta seahub_settings.py (URL, SECRET_KEY, Memcached).   
```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(50))'
nano /opt/seavault/conf/seahub_settings.py   
# Modificamos los campos SERVICE_URL, SECRET_KEY, CACHES
SERVICE_URL = 'http://seavault.lan'
SECRET_KEY = 'tu-clave-secreta-compartida'
FILE_SERVER_ROOT = 'https://seavault.lan/seafhttp'

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.PyMemcache',
        'LOCATION': '192.168.56.30:11211',
    }
}
nano /opt/seavault/conf/gunicorn.conf.py     
# Modificamos la linea bind = "0.0.0.0:8000"
```
### 2.5 Arrancar servicios
1) Abre Seafile y Seahub con ./*.sh start. 
2) Comprueba con curl -I.
```bash
./seafile.sh start
./seahub.sh  start
curl -I http://192.168.56.10:8000  
```
Para que guarde los archivos subidos hay que toquetear en la interfaz gráfica y decirle a que IP debe mandar los archivos.
### 2.5 Sincronía horaria
Por qué: mantiene el reloj alineado con el resto del clúster para evitar errores en sesiones y registros.
1) Instala chrony.
2) Apunta a server 192.168.56.50 iburst. 
3) Arranca y habilita al inicio.

```bash
sudo apt install -y chrony
sudo systemctl enable --now chrony
sudo nano /etc/chrony/chrony.conf 
# Añadimos la linea "server 192.168.56.50 iburst"
```

### 2.6 Ajuste permisos
Ajustamos los permisos para evitar errores de load balancing
```bash
sudo chown -R seavault_adm:seavault_adm /opt/seavault/{ccnet,conf}
sudo chmod -R o+rX /opt/seavault/{ccnet,conf}
```
## 3. SVserver-02 – Segundo nodo
### 3.1  Montar NFS
Por qué: enlaza el almacenamiento compartido /srv/seavault del repositorio en /opt/seavault.
1) Repite los tres pasos del nodo 01.
```bash
sudo apt install -y nfs-common
sudo mkdir -p /opt/seavault/seafile-data
sudo mkdir -p /opt/seavault/seahub-data
sudo mount 192.168.56.30:/srv/seavault/seafile-data /opt/seavault/seafile-data
sudo mount 192.168.56.30:/srv/seavault/seahub-data  /opt/seavault/seahub-data
sudo chown -R seavault_adm:seavault_adm /opt/seavault
```
### 3.2  Copiar datos desde server-01
Por qué: copiar configuración desde el nodo 01 asegura coherencia.
1) 	Sincroniza /opt/seavault desde server-01
```bash
scp -r seavault_adm@192.168.56.10: /opt/seavault/*  /opt/seavault/*
```
### 3.3 Arreglar python
Por qué: entorno idéntico a SVserver-01, debemos ajustar Python y dependencias.
1) Repite instalación de Python 3.11 y venv.
OJO! No es necesario indicarle a seahub la ruta para acceder a Python, esto ya estaba indicado en el archivo de configuración de SVserver-01 y SVserver-02 tiene una copia exacta de ese archivo.
```bash
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update 
sudo apt install python3.11 python3.11-venv python3.11-dev
sudo apt install build-essential default-libmysqlclient-dev pkg-config
cd ~/seafile-server-10.0.1/seahub
python3.11 -m venv env
source env/bin/activate
pip install -r requirements.txt
pip install -r PyMemcache
```

### 3.5  Arrancar
1) Abre Seafile y Seahub con ./*.sh start. 
2) Comprueba con curl -I.
```bash
cd ~/seafile-server-10.0.1
./seafile.sh start
./seahub.sh  start 
curl -I http://192.168.56.20:8000
```
### 3.6  Sincronía horaria
1) Instala chrony.
2) Apunta a server 192.168.56.50 iburst. 
3) Arranca y habilita al inicio.
```bash
sudo apt install -y chrony
sudo systemctl enable --now chrony
sudo nano /etc/chrony/chrony.conf 
# Añadimos la linea "server 192.168.56.50 iburst"

```
## 4. SVgateway
### 4.1  Sincronía horaria con Chrony
Por qué: al actuar como servidor NTP interno, marca el “reloj maestro” para el resto de nodos.
1) Instala chrony.
2) Apunta a red 192.168.56.0/24 
3) Arranca y habilita al inicio.
```bash
sudo apt install -y chrony
sudo systemctl enable --now chrony
sudo nano /etc/chrony/chrony.conf 
#Añade la linea allow 192.168.56.0/24
```
### 4.2 Configurar Nginx como balanceador
Qué hace: recibe peticiones HTTP/S en seavault.lan y las distribuye (round-robin) a SVserver-01 y SVserver-02.  
Por qué: reparte carga y ofrece tolerancia a fallos.
1) Instala nginx. 
2) Crea archivo sites-available/seavault con los bloques upstream. 
3) Habilita, nginx -t, recarga y abre puerto 80.
```bash
sudo nano /etc/nginx/sites-available/seavault
## Añadimos
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
```
```bash
sudo ln -s /etc/nginx/sites-available/seavault /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo ufw allow 80/tcp
```
### 4.3 Securizar con https
Qué hace: cifra el tráfico entre clientes y el LB.  
Por qué: evita credenciales en texto claro.
1) Genera par clave/cert autofirmado. 
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/seavault.key \
  -out /etc/ssl/certs/seavault.crt \
  -subj "/C=ES/ST=Seafile/L=LAN/O=seavault/CN=seavault.lan"

##clave privada: /etc/ssl/private/seavault.key
##certificado: /etc/ssl/certs/seavault.crt
```
## 5. Orden de arranque
#	Host	Comando
```bash
1	SVrepositorio	systemctl restart mariadb nfs-kernel-server memcached
2	SVserver-01 & SVserver-02	mount -a
3	SVserver-01	./seafile.sh start && ./seahub.sh start
4	SVserver-02	Igual que server-01
5	SVgateway	systemctl reload nginx
```
