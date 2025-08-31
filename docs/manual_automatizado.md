# Manual de despliegue **automatizado** del clúster SeaVault  
---
## 1. Descripción general
Los siete scripts incluidos permiten instalar todos los servicios de SeaVault sin intervención manual.  
Cada uno prepara su máquina, aplica reglas de cortafuegos, arranca los servicios y deja las métricas expuestas para Prometheus.
Para agilizar la automatización, se incluye un script maestro que se encarga de lanzar cada script en su máquina correspondiente en el orden correcto.
Los scripts de seguridad se deben ejecutar manualmente sobre las correspondientes máquinas para evitar conflictos.
## 2. Entorno
Este manual se ha concebido y elaborado específicamente para un entorno compuesto por cinco máquinas virtuales en VirtualBox que ejecutan distintas ediciones de Ubuntu y cumplen roles bien definidos. Las características de CPU, memoria, almacenamiento y los servicios instalados en cada VM se han dimensionado para emplear los mínimos recursos de la máquina anfitriona. A continuación, la tabla detalla los requisitos de cada VM:

| Máquina        | Modelo de máquina (VM) | Sistema operativo        | CPU      | RAM  | Disco | Servicios alojados                                                                              | Usuario | Contraseña |
|----------------|------------------------|--------------------------|----------|------|-------|--------------------------------------------------------------------------------------------------|-------|-----|
| SVserver-01    | VM VirtualBox          | Ubuntu Server 24.04.2    | 2 vCPU   | 4 GB | 60 GB | Seafile Server, Seahub, cliente Chrony, Node Exporter                                            | seavault_adm | adm |
| SVserver-02    | VM VirtualBox          | Ubuntu Server 24.04.2    | 2 vCPU   | 4 GB | 60 GB | Seafile Server, Seahub, cliente Chrony, Node Exporter                                            | seavault_adm | adm |
| SVrepositorio  | VM VirtualBox          | Ubuntu Server 24.04.2    | 2 vCPU   | 6 GB | 80 GB | MariaDB, NFS, Memcached, cliente Chrony, Node Exporter                                           | seavault_adm | adm |
| SVgateway      | VM VirtualBox          | Ubuntu Server 24.04.2    | 1–2 vCPU | 2–4 GB| 30 GB | NAT, DNS interno, reverse proxy, balanceo, NTP, firewall, cliente Chrony, Node Exporter          | seavault_adm | adm |
| SVmonitor      | VM VirtualBox          | Ubuntu Desktop 24.04.1   | 2 vCPU   | 4 GB | 50 GB | Prometheus, Grafana, cliente Chrony                                                              | lcm | abc123. |

NOTA: Para cada nodo se ha establecido un usuario y una contraseña que se debe indicar durante la instalación, el usuario para cada nodo se define en el propio script, pero por motivos de seguridad las contraseñas se deben añadir manualmente cuando el sistema las requiera. En la tabla de arriba se indican los usuarios y contraseñas configurados por defecto para cada nodo del prototipo.

## 3. Scripts
A continuación se muestra la tabla resumen de scripts utilizados para levantar y proteger cada nodo de forma independiente:

| Nodo | IP | Script principal | Script de cortafuegos | Servicios que instala |
|------|----|------------------|-----------------------|-----------------------|
| SVrepositorio | `192.168.56.30` | `setup_SVrepositorio.sh` | `securizar_SVrepositorio.sh` | MariaDB · NFS · Memcached · Chrony · Node-Exporter |
| SVgateway | `192.168.56.50` | `setup_SVgateway.sh` | `securizar_SVgateway.sh` | dnsmasq · nginx LB · NAT · Chrony (maestro) · Node-Exporter |
| SVserver-01 | `192.168.56.10` | `setup_SVserver01.sh` | — | Seafile + dependencias · NFS mount · Chrony · Node-Exporter |
| SVserver-02 | `192.168.56.20` | `setup_SVserver02.sh` | — | Seafile (replicado) · NFS mount · Chrony · Node-Exporter |
| SVmonitor | `192.168.56.40` | `setup_SVmonitor.sh` | — | Prometheus · Grafana · Chrony · Node-Exporter |

La ejecución del script maestro.sh permite automatizar el proceso de instalación en todos los nodos, evitando así la necesidad de realizar la instalación de forma manual e independiente en cada uno de ellos.

> **Cómo ejecutar**  
> 1. Acceder al nodo SVgateway mediante ssh:  
>   ```bash
>   ssh seavault_adm@192.168.0.19
>   ```  
> 2. Copiar todos los script en el nodo SVgateway en el mismo directorio:
>   ```bash
>   nano setup.sh
>   ```
> 3. Dar permisos de ejecución sobre el script maestro.sh y sobre el script setup_SVgateway.sh:
>   ```bash
>   sudo chmod +x maestro.sh 
>   sudo chmod +x setup_SVgateway.sh 
>   ```
> 4. Ejecutar script maestro.sh:
>   ```bash
>   sudo ./maestro.sh
---

## 4. Pasos por nodo
Una vez ejecutado el script maestro.sh, el sistema inicia la instalación nodo por nodo. En algunos casos, además de introducir manualmente las contraseñas, será necesario configurar ciertos parámetros adicionales.
### 4.1. SVgateway (`setup_SVgateway.sh`)
1. Instala **dnsmasq** para resolver `*.lan`.  
2. Despliega **nginx** con balanceo round-robin a `192.168.56.10:8000` y `192.168.56.20:8000`.  
3. Genera un certificado autofirmado y habilita HTTPS (443) con redirección 80→443.  
4. Activa **NAT** y abre DNS (53) y NTP (123); Chrony se convierte en servidor maestro.  
5. Añade **Node-Exporter** y un `allow 192.168.56.0/24` en chrony.conf.  
6. El script de firewall bloquea todo salvo 22, 53, 80, 443, 123 y 9100.

### 4.2. SVrepositorio (`setup_SVrepositorio.sh`)
1. Instala **MariaDB**, crea las tres bases de datos y el usuario `seavault_adm`.  
2. Habilita **NFS** exportando `/srv/seavault/*` para la red `192.168.56.0/24`.  
3. Activa **Memcached** escuchando en `0.0.0.0:11211`.  
4. Configura **Chrony** como cliente del gateway y añade **Node-Exporter** (`:9100`).  

### 4.3. SVserver-01 (`setup_SVserver01.sh`
1. Monta los exports NFS en `/opt/seavault`.  
2. Descarga **Seafile 10.0.1**, lanza el instalador apuntando a MariaDB remota y rutas NFS.  
3. Instala **Python 3.11**, crea virtualenv, resuelve dependencias y ajusta `seahub.sh`.  
4. Configura `seahub_settings.py` (URL, `SECRET_KEY`, Memcached, etc.).  
5. Arranca `./seafile.sh` y `./seahub.sh -d`; verifica con `curl -I …:8000`.  
6. Habilita Chrony y Node-Exporter.

Durante la instalación del nodo SVserver-01 el sistema solicitará varios parámetros de configuración, a continuación se detallan las respuestas por defecto para la configuración del prototipo:

```bash
What is the name of the server? svserver-01

What is the ip or domain of the server? 192.168.56.10

Which port do you want to use for the seafile server? 8082 (default)

[1 or 2]: [2] ([2] Use existing ccnet/seafile/seahub databases)

What is the host of mysql server? : 192.168.56.30

From which hosts could the mysql account be used?: % (default)

What is the port of mysql server? 3306 (default)

Which mysql user to use for seafile? seavault_adm

What is the password for mysql user "seavault_adm"? adm

Enter the database name for ccnet: ccnet_db

Enter the database name for seafile-server: seafile_db

Enter the database name for seahub: seahub_db
```

### 4.4. SVserver-02 (`setup_SVserver02.sh`)
1. Monta NFS igual que el nodo 01.  
2. Descarga Seafile y **sincroniza** solo `ccnet/` y `conf/` vía rsync desde `192.168.56.10`.  
3. Repite la creación de virtualenv y dependencias Python.  
4. Crea enlaces simbólicos a los datos NFS, copia los mismos ajustes y arranca los servicios.  
5. Activa Chrony cliente y Node-Exporter.

### 4.5. SVmonitor (`setup_SVmonitor.sh`)
1. Instala **Prometheus 2.x** con un `prometheus.yml` que apunta a todos los `:9100`.  
2. Despliega **Grafana OSS**, agrega Prometheus como DataSource y pre-carga un dashboard de Seafile.  
3. Activa Chrony y su propio Node-Exporter.  
4. Muestra las URLs finales: `http://192.168.56.40:9090` y `http://192.168.56.40:3000` (admin/admin).

### 4.6. SVgateway  (`securizar_SVgateway.sh`)
1. El script de firewall bloquea todo salvo 22, 53, 80, 443, 123 y 9100.

### 4.7. SVrepositorio  (`securizar_SVrepositorio.sh`)
1. Aplica el cortafuegos: solo quedan abiertos 22, 3306, 2049, 11211, 123 y 9100.
---

## 3. Orden de ejecución
En caso de realizar una instalación nodo a nodo es fundamental respetar el orden de ejecución de cada script:
```text
1) SVgateway     → setup_SVgateway.sh     
2) SVrepositorio → setup_SVrepositorio.sh  
3) SVserver-01   → seup_SVserver01.sh
4) SVserver-02   → setup_SVserver02.sh
5) SVmonitor     → setup_SVmonitor.sh
6) SVrepositorio → securizar_SVrepositorio.sh
7) SVgateway     → securizar_SVgateway.sh
