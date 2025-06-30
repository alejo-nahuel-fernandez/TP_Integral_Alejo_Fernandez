#!/bin/bash
# -------------------------------------------------------------------------------------------------
# SCRIPT: configure_lvm.sh
# DESCRIPCION: Script para configurar Logical Volume Management (LVM) en VMs.
#              Crea Physical Volumes (PVs), Volume Groups (VGs) y Logical Volumes (LVs).
#              Luego formatea los LVs y los monta persistentemente.
#              ¡Versión final: Idempotente, limpia discos, y los identifica por tamaño!
# AUTOR: Alejo
# FECHA: 29 de junio de 2025
# VERSION: 1.4 (Final + Detección por tamaño)
# USAGE: Este script está diseñado para ser ejecutado como parte del aprovisionamiento de Vagrant.
# -------------------------------------------------------------------------------------------------

echo "================================================"
echo " Inciando configuración de LVM"
echo "================================================"

# --- Paso PREVIO: Instalar herramientas necesarias (gdisk para sgdisk) ---
echo "--- Verificando/Instalando herramientas necesarias (gdisk) ---"
if command -v dnf >/dev/null 2>&1; then # Para Fedora
    sudo dnf install -y gdisk lvm2 parted
elif command -v apt-get >/dev/null 2>&1; then # Para Ubuntu
    sudo apt-get update
    sudo apt-get install -y gdisk lvm2 parted
else
    echo "ADVERTENCIA: No se pudo determinar el gestor de paquetes (dnf/apt-get). Herramientas podrían no instalarse."
fi

# --- Funciones de Verificación de Existencia ---
pv_exists() {
    sudo pvs --noheadings -o pv_name | grep -q "$1"
}
vg_exists() {
    sudo vgs --noheadings -o vg_name | grep -q "$1"
}
lv_exists() {
    sudo lvs --noheadings -o lv_name | grep -q "$1"
}

# --- Identificación de Discos por Tamaño (más robusto) ---
# Vamos a encontrar los dispositivos /dev/sdX por su tamaño.
# Usaremos 'lsblk' para obtener una lista de dispositivos.
# Los tamaños están en GB para facilitar la comparación, pero los scripts los usan en bytes (para sfdisk) o MB (para Vagrantfile)
# Disk1: 5GB, Disk2: 3GB, Disk3: 2GB, Disk_extra: 1GB

echo ""
echo "--- Identificando discos por tamaño ---"
# Limpiamos y convertimos lsblk output a una forma fácil de procesar
mapfile -t ALL_DISKS < <(sudo lsblk -ndo NAME,SIZE,TYPE | grep "disk" | awk '{print "/dev/" $1, int($2)}')

declare -A DISK_MAPPING

for entry in "${ALL_DISKS[@]}"; do
    DEVICE=$(echo "$entry" | awk '{print $1}')
    SIZE_GB=$(echo "$entry" | awk '{print $2}')

    case "$SIZE_GB" in
        5)
            if [ -z "${DISK_MAPPING[5G]}" ]; then
                DISK_MAPPING[5G]="$DEVICE"
                echo "Identificado DISK_5G: $DEVICE"
            fi
            ;;
        3)
            if [ -z "${DISK_MAPPING[3G_1]}" ]; then # Primer 3GB
                DISK_MAPPING[3G_1]="$DEVICE"
                echo "Identificado DISK_3G (primero): $DEVICE"
            elif [ -z "${DISK_MAPPING[3G_2]}" ]; then # Segundo 3GB (si aplica para ubuntu, para fedora es 2GB+1GB)
                # NOTA: En Fedora, los discos son 5G, 3G, 2G, 1G.
                # Si esto es Ubuntu y tienes 2x3GB, podrías necesitarlos
                # Para Fedora, vg_datos usa el 5G y 3G, y vg_temp usa 2G y 1G.
                : # No hacemos nada aqui para Fedora
            fi
            ;;
        2)
            if [ -z "${DISK_MAPPING[2G]}" ]; then
                DISK_MAPPING[2G]="$DEVICE"
                echo "Identificado DISK_2G: $DEVICE"
            fi
            ;;
        1)
            if [ -z "${DISK_MAPPING[1G]}" ]; then
                DISK_MAPPING[1G]="$DEVICE"
                echo "Identificado DISK_1G: $DEVICE"
            fi
            ;;
    esac
done

# Asigna las variables finales
DISK_5G="${DISK_MAPPING[5G]}"
DISK_3G="${DISK_MAPPING[3G_1]}" # Este es el disco de 3GB para vg_datos
DISK_2G="${DISK_MAPPING[2G]}" # Este es el disco de 2GB para vg_temp
DISK_1G="${DISK_MAPPING[1G]}" # Este es el disco de 1GB para vg_temp

# Verificamos que todos los discos necesarios fueron encontrados
if [ -z "$DISK_5G" ] || [ -z "$DISK_3G" ] || [ -z "$DISK_2G" ] || [ -z "$DISK_1G" ]; then
    echo "ERROR: No se pudieron identificar todos los discos. Abortando LVM."
    echo "Discos identificados: 5G=${DISK_5G}, 3G=${DISK_3G}, 2G=${DISK_2G}, 1G=${DISK_1G}"
    exit 1
fi
echo "Discos identificados con éxito."


# --- Paso 0: Desmontar y limpiar cualquier partición existente ---
echo ""
echo "--- Desmontando particiones y limpiando discos antes de usarlos para LVM ---"
for DISK in ${DISK_5G} ${DISK_3G} ${DISK_2G} ${DISK_1G}; do
    if [ -b "${DISK}" ]; then # Verifica si el dispositivo existe
        echo "Procesando ${DISK}..."

        # Primero, intenta desmontar todas las particiones de este disco
        mapfile -t PARTITIONS < <(sudo lsblk -nr -o NAME "${DISK}" | grep -E "${DISK##*/}[0-9]+")
        for PART in "${PARTITIONS[@]}"; do
            if mountpoint -q "/dev/$PART"; then
                echo "Desmontando /dev/$PART..."
                sudo umount "/dev/$PART" || echo "ADVERTENCIA: Falló el desmontaje de /dev/$PART."
            fi
        done

        # Limpiar firmas de sistemas de archivos y encabezados LVM/Swap
        echo "Limpiando firmas de sistemas de archivos en ${DISK}..."
        sudo wipefs -a "${DISK}" || echo "ADVERTENCIA: Falló wipefs en ${DISK}."

        # Limpiar tablas de particiones (GPT/MBR)
        echo "Limpiando tablas de particiones en ${DISK}..."
        sudo sgdisk --zap-all "${DISK}" || echo "ADVERTENCIA: Falló sgdisk en ${DISK}."

        # Informar al kernel sobre los cambios en la tabla de particiones
        echo "Informando al kernel sobre los cambios en ${DISK}..."
        sudo partprobe "${DISK}" || echo "ADVERTENCIA: Falló partprobe en ${DISK}."
        sleep 2 # Dar tiempo al kernel para procesar
    else
        echo "ADVERTENCIA: Dispositivo ${DISK} no encontrado durante la limpieza. Saltando."
    fi
done
echo "Limpieza profunda de discos completada."


# 1. Crear Physical Volumes (PVs)
echo ""
echo "--- Creando Physical Volumes (PVs) ---"
for DISK in ${DISK_5G} ${DISK_3G} ${DISK_2G} ${DISK_1G}; do
    if [ -b "${DISK}" ]; then # Verificar que el disco exista antes de intentar crear PV
        if ! pv_exists "${DISK}"; then
            echo "Creando PV en ${DISK}..."
            sudo pvcreate "${DISK}" -ff
            if [ $? -ne 0 ]; then
                echo "ERROR: Falló la creación del PV en ${DISK}. Abortando."
                exit 1
            fi
        else
            echo "PV en ${DISK} ya existe. Saltando."
        fi
    else
        echo "ADVERTENCIA: Disco ${DISK} no existe, no se puede crear PV."
    fi
done
echo "PVs creados/verificados exitosamente."
sudo pvs # Muestra los PVs actuales

# 2. Crear Volume Groups (VGs)
echo ""
echo "--- Creando Volume Groups (VGs) ---"

# VG para datos (vg_datos) utilizando discos de 5G y 3G
if ! vg_exists "vg_datos"; then
    echo "Creando VG 'vg_datos'..."
    sudo vgcreate vg_datos "${DISK_5G}" "${DISK_3G}"
    if [ $? -eq 0 ]; then
        echo "VG 'vg_datos' creado exitosamente."
    else
        echo "ERROR: Falló la creación del VG 'vg_datos'. Abortando."
        exit 1
    fi
else
    echo "VG 'vg_datos' ya existe. Saltando."
fi

# VG para temporales (vg_temp) utilizando discos de 2G y 1G
if ! vg_exists "vg_temp"; then
    echo "Creando VG 'vg_temp'..."
    sudo vgcreate vg_temp "${DISK_2G}" "${DISK_1G}"
    if [ $? -eq 0 ]; then
        echo "VG 'vg_temp' creado exitosamente."
    else
        echo "ERROR: Falló la creación del VG 'vg_temp'. Abortando."
        exit 1
    fi
else
    echo "VG 'vg_temp' ya existe. Saltando."
fi
sudo vgs # Muestra los VGs actuales

# 3. Crear Logical Volumes (LVs)
echo ""
echo "--- Creando Logical Volumes (LVs) ---"

# LV para Docker: 12M en vg_datos
if ! lv_exists "lv_docker"; then
    echo "Creando LV 'lv_docker'..."
    sudo lvcreate -L 12M -n lv_docker vg_datos
    if [ $? -eq 0 ]; then
        echo "LV 'lv_docker' creado exitosamente."
    else
        echo "ERROR: Falló la creación del LV 'lv_docker'. Abortando."
        exit 1
    fi
else
    echo "LV 'lv_docker' ya existe. Saltando."
fi

# LV para Workareas: 2.5GB en vg_datos
if ! lv_exists "lv_workareas"; then
    echo "Creando LV 'lv_workareas'..."
    sudo lvcreate -L 2.5G -n lv_workareas vg_datos
    if [ $? -eq 0 ]; then
        echo "LV 'lv_workareas' creado exitosamente."
    else
        echo "ERROR: Falló la creación del LV 'lv_workareas'. Abortando."
        exit 1
    fi
else
    echo "LV 'lv_workareas' ya existe. Saltando."
fi

# LV para Swap: 2.5G en vg_temp
if ! lv_exists "lv_swap"; then
    echo "Creando LV 'lv_swap'..."
    sudo lvcreate -L 2.5G -n lv_swap vg_temp
    if [ $? -eq 0 ]; then
        echo "LV 'lv_swap' creado exitosamente."
    else
        echo "ERROR: Falló la creación del LV 'lv_swap'. Abortando."
        exit 1
    fi
else
    echo "LV 'lv_swap' ya existe. Saltando."
fi
sudo lvs # Muestra los LVs actuales

# 4. Formatear Logical Volumes
echo ""
echo "--- Formateando Logical Volumes ---"

# Formatear lv_docker como ext4
if ! sudo blkid "/dev/mapper/vg_datos-lv_docker" | grep -q "TYPE=\"ext4\""; then
    echo "Formateando LV 'lv_docker' como ext4..."
    sudo mkfs.ext4 /dev/vg_datos/lv_docker -F
    if [ $? -eq 0 ]; then
        echo "LV 'lv_docker' formateado como ext4."
    else
        echo "ERROR: Falló el formateo de 'lv_docker'. Abortando."
        exit 1
    fi
else
    echo "LV 'lv_docker' ya formateado como ext4. Saltando."
fi

# Formatear lv_workareas como ext4
if ! sudo blkid "/dev/mapper/vg_datos-lv_workareas" | grep -q "TYPE=\"ext4\""; then
    echo "Formateando LV 'lv_workareas' como ext4..."
    sudo mkfs.ext4 /dev/vg_datos/lv_workareas -F
    if [ $? -eq 0 ]; then
        echo "LV 'lv_workareas' formateado como ext4."
    else
        echo "ERROR: Falló el formateo de 'lv_workareas'. Abortando."
        exit 1
    fi
else
    echo "LV 'lv_workareas' ya formateado como ext4. Saltando."
fi

# Configurar lv_swap como espacio de intercambio
if ! sudo blkid "/dev/mapper/vg_temp-lv_swap" | grep -q "TYPE=\"swap\""; then
    echo "Configurando LV 'lv_swap' como espacio de intercambio..."
    sudo mkswap /dev/vg_temp/lv_swap
    if [ $? -eq 0 ]; then
        echo "LV 'lv_swap' configurado como espacio de intercambio."
    else
        echo "ERROR: Falló la configuración de 'lv_swap' como swap. Abortando."
        exit 1
    fi
else
    echo "LV 'lv_swap' ya configurado como swap. Saltando."
fi

# 5. Crear puntos de montaje y montar LVs
echo ""
echo "--- Creando puntos de montaje y montando LVs ---"

# Montar lv_docker en /var/lib/docker
sudo mkdir -p /var/lib/docker
if ! mountpoint -q /var/lib/docker; then
    echo "Montando LV 'lv_docker' en /var/lib/docker..."
    sudo mount /dev/vg_datos/lv_docker /var/lib/docker
    if [ $? -eq 0 ]; then
        echo "LV 'lv_docker' montado en /var/lib/docker."
    else
        echo "ERROR: Falló el montaje de 'lv_docker'. Abortando."
        exit 1
    fi
else
    echo "/var/lib/docker ya está montado. Saltando."
fi

# Montar lv_workareas en /work
sudo mkdir -p /work
if ! mountpoint -q /work; then
    echo "Montando LV 'lv_workareas' en /work..."
    sudo mount /dev/vg_datos/lv_workareas /work
    if [ $? -eq 0 ]; then
        echo "LV 'lv_workareas' montado en /work."
    else
        echo "ERROR: Falló el montaje de 'lv_workareas'. Abortando."
        exit 1
    fi
else
    echo "/work ya está montado. Saltando."
fi

# Activar lv_swap
if ! sudo swapon --show | grep -q "/dev/mapper/vg_temp-lv_swap"; then
    echo "Activando LV 'lv_swap'..."
    sudo swapon /dev/vg_temp/lv_swap
    if [ $? -eq 0 ]; then
        echo "LV 'lv_swap' activado."
    else
        echo "ERROR: Falló la activación de 'lv_swap'. (Puede que ya esté activo, se omitirá si no es crítico)."
    fi
else
    echo "LV 'lv_swap' ya activado. Saltando."
fi

# 6. Configurar /etc/fstab para montajes persistentes
echo ""
echo "--- Configurando /etc/fstab para montajes persistentes ---"

FSTAB_BACKUP_NAME="/etc/fstab.bak.$(date +%Y%m%d)"
if [ ! -f "${FSTAB_BACKUP_NAME}" ]; then
    sudo cp /etc/fstab "${FSTAB_BACKUP_NAME}"
    echo "Copia de seguridad de /etc/fstab creada en ${FSTAB_BACKUP_NAME}"
else
    echo "Copia de seguridad de /etc/fstab del día ya existe. Saltando respaldo."
fi

grep -q "/var/lib/docker" /etc/fstab || echo "/dev/mapper/vg_datos-lv_docker /var/lib/docker ext4 defaults 0 2" | sudo tee -a /etc/fstab
grep -q "/work" /etc/fstab || echo "/dev/mapper/vg_datos-lv_workareas /work ext4 defaults 0 2" | sudo tee -a /etc/fstab
grep -q "vg_temp-lv_swap" /etc/fstab || echo "/dev/mapper/vg_temp-lv_swap none swap sw 0 0" | sudo tee -a /etc/fstab
echo "Entradas de fstab añadidas/verificadas."

echo ""
echo "================================================"
echo " Configuración de LVM completada."
echo " Verificar con: sudo pvs, sudo vgs, sudo lvs, df -h /var/lib/docker /work, swapon --show"
echo "================================================"