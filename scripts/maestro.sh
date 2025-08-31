#!/bin/bash
USUARIO="seavault_adm"
#### Ejecuta primer script en SVgateway ####
bash "setup_SVgateway.sh"
if [ $? -ne 0 ]; then
    echo "Error: setup_SVgateway.sh falló en la primera máquina. Deteniendo ejecución."
    exit 1
fi

### Máquinas y scripts correspondientes ###
declare -A maquinas_scripts
maquinas_scripts=(
    ["192.168.56.30"]="setup_SVrepositorio.sh"
    ["192.168.56.10"]="setup_SVserver01.sh"
    ["192.168.56.20"]="setup_SVserver02.sh"
    ["192.168.56.40"]="setup_SVmonitor.sh"
)

### Orden de ejecución ###
orden_ips=("192.168.56.30" "192.168.56.10" "192.168.56.20" "192.168.56.40")

### Ejecución scripts en orden ###
# Nota: para ip 192.168.56.40 el usuario y contraseña son diferentes
for ip in "${orden_ips[@]}"; do
    script="${maquinas_scripts[$ip]}"
    echo "Ejecutando $script en $ip..."

    if [ "$ip" == "192.168.56.40" ]; then
        ssh -t lcm@"$ip" "bash -s" < "$script"
    else
        ssh -t "$USUARIO@$ip" "bash -s" < "$script"
    fi

    if [ $? -ne 0 ]; then
        echo "Error: $script falló en $ip. Deteniendo ejecución."
        exit 1
    fi
done

echo "Todos los scripts se ejecutaron correctamente."


