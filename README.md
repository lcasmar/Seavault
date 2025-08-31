# SeaVault

SeaVault es un prototipo de almacenamiento seguro basado en Seafile.  
Reproduce un entorno real de producción— clúster activo-activo, balanceo HTTPS, alta disponibilidad y monitorización — usando solo software libre y scripts que despliegan todo en < 20 min.
## Funciones

| Función | Componente |
|------|------------|
| Alta disponibilidad| Dos nodos Seafile + MariaDB Galera (opcional) + NFS compartido. |
| Despliegue automático | 7 scripts bash idempotentes (`scripts/`) sobre VM limpias |
| Seguridad | UFW, iptables, fail2ban. |
| Monitorización | Prometheus + Grafana con alertas, Node Exporter y métricas de salud. |
| Escalabilidad | Diseño modular → añade nodos o separa capas sin refactorizar. |

---

## 🗺️ Estructura del repositorio
```text
Seavault/
├─ docs/
|  ├─ manual_monitor.md              
│  ├─ manual_instalacion.md
│  └─ manual_automatizado.md
├─ scripts/
|  ├─ maestro.sh/          
│  ├─ setup_SVgateway.sh/          
│  ├─ setup_SVserver01.sh       
│  ├─ setup_SVserver02.sh
|  ├─ setup_SVrepositorio.sh
│  ├─ setup_SVmonitor.sh
|  ├─ securizar_SVgateway.sh
|  └─ securizar_SVrepositorio.sh 
└─ README.md
