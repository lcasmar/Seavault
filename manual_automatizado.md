# Manual de despliegue **automatizado** del clúster SeaVault  
---
## 1 · Descripción general
Los siete scripts incluidos permiten instalar **todos** los servicios de SeaVault sin intervención manual.  
Cada uno prepara su máquina, aplica reglas de cortafuegos, arranca los servicios y deja las métricas expuestas para Prometheus.

| Nodo | IP | Script principal | Script de cortafuegos | Servicios que instala |
|------|----|------------------|-----------------------|-----------------------|
| SVrepositorio | `192.168.56.30` | `setup_repositorio.sh` | `fw_repositorio.sh` | MariaDB · NFS · Memcached · Chrony · Node-Exporter |
| SVgateway | `192.168.56.50` | `setup_gateway.sh` | `fw_gateway.sh` | dnsmasq · nginx LB · NAT · Chrony (maestro) · Node-Exporter |
| SVserver-01 | `192.168.56.10` | `completo_server01.sh` | — | Seafile + dependencias · NFS mount · Chrony · Node-Exporter |
| SVserver-02 | `192.168.56.20` | `setup_server02F.sh` | — | Seafile (replicado) · NFS mount · Chrony · Node-Exporter |
| SVmonitor | `192.168.56.40` | `setup_prometheus.sh` | — | Prometheus · Grafana · Chrony · Node-Exporter |

> **Cómo ejecutar**  
> 1. Copia el script al nodo:  
>   ```bash
>   scp script.sh usuario@IP:/tmp
>   ```  
> 2. Dale permisos y lánzalo con sudo:  
>   ```bash
>   sudo chmod +x /tmp/script.sh && sudo /tmp/script.sh
>   ```

---

## 2 · Pasos por nodo

### 2.1 SVrepositorio (`setup_repositorio.sh` → `fw_repositorio.sh`)

1. Instala **MariaDB**, crea las tres bases de datos y el usuario `seavault_adm`.  
2. Habilita **NFS** exportando `/srv/seavault/*` para la red `192.168.56.0/24`.  
3. Activa **Memcached** escuchando en `0.0.0.0:11211`.  
4. Configura **Chrony** como cliente del gateway y añade **Node-Exporter** (`:9100`).  
5. Aplica el cortafuegos: solo quedan abiertos 22, 3306, 2049, 11211, 123 y 9100.

### 2.2 SVgateway (`setup_gateway.sh` → `fw_gateway.sh`)

1. Instala **dnsmasq** para resolver `*.lan`.  
2. Despliega **nginx** con balanceo round-robin a `192.168.56.10:8000` y `192.168.56.20:8000`.  
3. Genera un certificado autofirmado y habilita HTTPS (443) con redirección 80→443.  
4. Activa **NAT** y abre DNS (53) y NTP (123); Chrony se convierte en servidor maestro.  
5. Añade **Node-Exporter** y un `allow 192.168.56.0/24` en chrony.conf.  
6. El script de firewall bloquea todo salvo 22, 53, 80, 443, 123 y 9100.

### 2.3 SVserver-01 (`completo_server01.sh`)

1. Monta los exports NFS en `/opt/seavault`.  
2. Descarga **Seafile 10.0.1**, lanza el instalador apuntando a MariaDB remota y rutas NFS.  
3. Instala **Python 3.11**, crea virtualenv, resuelve dependencias y ajusta `seahub.sh`.  
4. Configura `seahub_settings.py` (URL, `SECRET_KEY`, Memcached, etc.).  
5. Arranca `./seafile.sh` y `./seahub.sh -d`; verifica con `curl -I …:8000`.  
6. Habilita Chrony y Node-Exporter.

### 2.4 SVserver-02 (`setup_server02F.sh`)

1. Monta NFS igual que el nodo 01.  
2. Descarga Seafile y **sincroniza** solo `ccnet/` y `conf/` vía rsync desde `192.168.56.10`.  
3. Repite la creación de virtualenv y dependencias Python.  
4. Crea enlaces simbólicos a los datos NFS, copia los mismos ajustes y arranca los servicios.  
5. Activa Chrony cliente y Node-Exporter.

### 2.5 SVmonitor (`setup_prometheus.sh`)

1. Instala **Prometheus 2.x** con un `prometheus.yml` que apunta a todos los `:9100`.  
2. Despliega **Grafana OSS**, agrega Prometheus como DataSource y pre-carga un dashboard de Seafile.  
3. Activa Chrony y su propio Node-Exporter.  
4. Muestra las URLs finales: `http://192.168.56.40:9090` y `http://192.168.56.40:3000` (admin/admin).

---

## 3 · Orden recomendado de ejecución

```text
1) SVrepositorio → setup_repositorio.sh  ▸  fw_repositorio.sh
2) SVgateway     → setup_gateway.sh      ▸  fw_gateway.sh
3) SVserver-01   → completo_server01.sh
4) SVserver-02   → setup_server02F.sh
5) SVmonitor     → setup_prometheus.sh
