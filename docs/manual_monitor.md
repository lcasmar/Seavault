# Manual monitorización con Prometheus + Grafana
## Prometheus
Prometheus es un software especializado como sistema de monitorización y alertas que, consulta endpoints de servicios para exponer métricas en /metrics, guardando esos datos en su base de datos interna como series temporales. Es posible consultar esas métricas desde la interfaz web conectándolo a Grafana, donde también se pueden configurar alertas que se disparen cuando se cumplan ciertas condiciones.

## 1. Entorno
Este manual se ha concebido y elaborado específicamente para un entorno compuesto por máquinas virtuales en VirtualBox que ejecutan distintas ediciones de Ubuntu.

| Host | Rol | Paquetes necesarios |
|------|-----|--------------------|
| SVmonitor | Monitorización | `prometheus` `grafana` `node-exporter` |
| Todos los nodos | Extraer métricas | `node-exporter` |
---
## 2. Instalación (Ubuntu 24.04)
### 2.1. SVmonitor
En el equipo que funcionará como servidor de monitorización, instalaremos Prometheus (para la recolección y almacenamiento de métricas) y Grafana (para visualización y dashboards).

#### 2.1.1 Instalación de Prometheus
Prometheus no siempre viene en la última versión en los repositorios de Ubuntu, por eso se recomienda descargar el binario oficial desde GitHub:
```bash
curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest \
| grep browser_download_url | grep linux-amd64 \
| cut -d '"' -f 4 | wget -qi -
tar -xzf prometheus-*.tar.gz
sudo mv prometheus-*/{prometheus,promtool} /usr/local/bin/
sudo useradd -rs /bin/false prometheus
sudo mkdir /etc/prometheus /var/lib/prometheus
sudo mv prometheus-*/consoles prometheus-*/console_libraries /etc/prometheus
```
#### 2.1.2 Crear el servicio Prometheus
Creamos un servicio systemd para gestionar Prometheus como demonio de sistema:
```bash
cat <<'EOF' | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now prometheus
```
Con esto, Prometheus estará accesible en **http://IP_monitor:9090**.
    
#### 2.1.2 Instalación de Grafana
Grafana tampoco suele estar actualizado en los repositorios de Ubuntu. Usamos el repositorio oficial de Grafana Labs:
```bash
sudo apt-get install -y apt-transport-https software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt-get update && sudo apt-get install -y grafana
sudo systemctl enable --now grafana-server
```
Grafana quedará disponible en **http://IP_monitor:3000**  
Credenciales por defecto: 
- usuario: admin 
- contraseña: admin
  
### 2.2. Instalación en cada nodo
En cada máquina que se desee monitorizar instalaremos Node Exporter, que expone métricas básicas del sistema (CPU, RAM, disco, red).  
Con esto, cada nodo expone métricas en http://<IP_NODE>:9100/metrics.
```bash
useradd -rs /bin/false node_exporter
curl -LO https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
sudo mv node_exporter-*/node_exporter /usr/local/bin/

cat <<'EOF' | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now node_exporter
```

## 3. Paneles Grafana para SeaVault
Una vez que Prometheus y Node Exporter ya están recogiendo métricas, el siguiente paso es visualizarlas en Grafana.  
Grafana permite crear dashboards personalizados donde podemos observar el estado de los nodos SeaVault en tiempo real.  
El primer paso será añadir Prometheus como data source y después crear nuestro primer panel.

### 3.1. Añadir *data source*: Prometheus
1. Acceder a Grafana en `http://SVmonitor:3000`.  
2. En **Configuration → Data sources**, debemos añadir una fuente de datos: **Add datasource**.  
3. Seleccionar **Prometheus**.  
4. En la URL indicar: `http://localhost:9090`.  
5. Clic en **Save & test** (debería mostrar *Data source is working*).  

### 3.2. Crear un Dashboard
1. En Grafana, ir a **Create → Dashboard** y seleccionar **Add a new panel**.  
2. Seleccionar como data source: *Prometheus*.  
3. Introducir la consulta qeu corresponda, por ejemplo:
   ```promql
   rate(node_cpu_seconds_total{mode!="idle"}[5m]) * 100
4. En el panel de la derecha se puede modificar la visualización, añadir títulos a los ejes e incluso dar formato a los gráficos.
5. Una vez tengamos el panel configurado, seleccionar *Apply*.

Los paneles ya configurados apareceran en la sección principal **Dashboard**

### 3.3. Crear alertas en Grafana
Además de mostrar métricas en tiempo real, Grafana permite definir alertas que se disparan cuando una condición se cumple durante un periodo determinado.  
Esto resulta muy útil para detectar problemas sin necesidad de estar mirando constantemente los paneles.  
Las alertas en Grafana se configuran directamente desde los paneles y pueden enviarse a distintos canales como correo electrónico, Slack, Telegram u otros sistemas de notificación.  
1. Editar el panel deseado → pestaña Alert → Create alert rule.
2. Query A.
```promql
changes(up{instance="$instance"}[2m]) > 0
Condition = “is above 0” durante 1 min.
```
1. Elegir notificador (e-mail, Slack, Telegram…).
2. Save. 
3. Aparece en Alerting → Rules.

### 3.4. Paneles básicos recomendados
Es recomendable crear un conjunto mínimo de paneles que permitan tener una visión general del estado de los nodos SeaVault.  
La siguiente tabla resume algunas métricas útiles junto con sus consultas PromQL y el tipo de visualización sugerido en Grafana:
| Métrica                | Consulta PromQL                                                             | Vista       |
| ---------------------- | --------------------------------------------------------------------------- | ----------- |
| CPU %              | `rate(node_cpu_seconds_total{mode!="idle",instance="$instance"}[5m]) * 100` | Gauge       |
| RAM usada (GB)     | `(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1e9`       | Time series |
| Disco usado %      | `100 - (node_filesystem_free_bytes / node_filesystem_size_bytes * 100)`     | Gauge       |
| Latencia login p95 | `histogram_quantile(0.95, rate(seafile_login_duration_seconds_bucket[5m]))` | Bar gauge   |
| Subida MB/s       | `rate(seafile_upload_bytes_total[1m]) / 1e6`                                | Time series |
| Eventos fail-over  | `changes(up{job="seavault_nodes"}[5m])`                                     | Stat        |

También existe la opción de importar paneles ya configurados, se pueden consultar los paneles disponibles en *https://grafana.com/grafana/dashboards/*


