#!/bin/bash

# get real path to script
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
# load functions
source $SCRIPT_PATH/../FUNCTIONS
IFS=$' \n\t'

H1 "hostnamectl"
hostnamectl
H1 "ip addr"
ip addr | grep -E 'altname|global '
H1 "ip route"
ip route | grep default

DISKS=$(lsblk -o NAME,SIZE,TYPE | grep disk | awk '{print $1}')
KVM_DISKS=""
DISK_INDEX=0

# Получаем текущий IP адрес хоста
HOST_IP=$(hostname -I | awk '{print $1}')
# Получаем текущий шлюз
HOST_GATEWAY=$(ip route | grep default | awk '{print $3}')

for disk in ${DISKS}
do
    KVM_DISKS+="-drive file=/dev/${disk},format=raw,cache=none,index=${DISK_INDEX},if=virtio,media=disk "
    ((DISK_INDEX+=1))
done

# Check for EFI or MBR boot mode
if [ -d /sys/firmware/efi ]; then
    H1 "Текущий режим загрузки: EFI"
    BOOT_MODE="efi"
    QEMU_MACHINE_TYPE="q35"
else
    H1 "Текущий режим загрузки: MBR"
    BOOT_MODE="mbr"
    QEMU_MACHINE_TYPE="pc"
fi

function START_KVM {
    # generate random password
    VNC_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 || true ; echo '')
    printf "${ORANGE} VNC Password is ${GREEN}${VNC_PASSWORD}${NC}\n"

    # Start KVM
    pkill qemu-system-x86 || true
    H1 "Please open VNC console to ${HOST_IP}, install PVE and press Next"
    printf "change vnc password\n%s\n" ${VNC_PASSWORD} | qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -boot once=d -cdrom ./$ISO ${KVM_DISKS} -M ${QEMU_MACHINE_TYPE} -vnc 0.0.0.0:0,password -monitor stdio &>/dev/null &

    read -e -p "> " -i "Next"
}

function DOWNLOAD_ISO {
    URL=$1
    WGET="wget --show-progress -N --progress=bar:force --content-disposition"
    ${WGET} "$URL"
    ISO=$(basename $URL)
}

if Q "Install PVE?"
then
    URL=$(curl -s https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso | grep -o 'href="[^"]*">Download</a>' | sed -E 's/href="([^"]*)">Download<\/a>/\1/' | head -n1)
    echo "$URL"
    if [ -z "$URL" ]; then
        echo "Could not find ISO on the website. Please enter URL to download PVE ISO:"
        read -e -p "> " CUSTOM_URL
        DOWNLOAD_ISO "$CUSTOM_URL"
    else
        DOWNLOAD_ISO "$URL"
    fi
    START_KVM
elif Q "Install PBS?"
then
    URL=$(curl -s https://www.proxmox.com/en/downloads/category/iso-images-pbs | grep -o "/en/downloads?.*" || true | head -n1 | sed 's/".*//')
    if [ -z "$URL" ]; then
        echo "Could not find ISO on the website. Please enter URL to download PBS ISO:"
        read -e -p "> " CUSTOM_URL
        DOWNLOAD_ISO "$CUSTOM_URL"
    else
        DOWNLOAD_ISO "$URL"
    fi
    START_KVM
fi

if Q "Change INTERFACE name or IP?"
then
    pkill qemu-system-x86 || true
    zpool version
    if ! zpool list | grep -v "no pools available"
    then
        zpool import -f -N rpool
    fi

    ZFS_ROOT=$(zfs list -o name -H | grep rpool/ROOT/...-1)

    zfs set mountpoint=/mnt ${ZFS_ROOT}
    zfs mount ${ZFS_ROOT} || true

    printf "${GREEN}"
    for i in $(ls /sys/class/net/ | grep -v lo)
    do
        udevadm test /sys/class/net/$i 2>/dev/null | grep ID_NET_NAME_
    done
    printf "${NC}"

    CONFIG_FILE="/mnt/etc/network/interfaces"
    CURRENT_INTERFACE=$(awk '/bridge-ports/ {print $2}' $CONFIG_FILE)

    if [ -z "$CURRENT_INTERFACE" ] || [ "$CURRENT_INTERFACE" = "none" ]; then
        echo "Текущий интерфейс не найден в файле конфигурации."
        exit 1
    fi

    ALL_INTERFACES=$(ls /sys/class/net | grep -v 'lo\|docker\|veth')

    ACTIVE_INTERFACES=()
    for IFACE in $ALL_INTERFACES; do
        if [[ "$(cat /sys/class/net/$IFACE/operstate)" == "up" ]] && [[ -z $(udevadm info --path=/sys/class/net/$IFACE | grep ID_BUS | grep usb) ]]; then
            ID_NET_NAME_ONBOARD=$(udevadm info --path=/sys/class/net/$IFACE | grep ID_NET_NAME_ONBOARD | awk -F '=' '{print $2}')
            if [ ! -z "$ID_NET_NAME_ONBOARD" ]; then
                ACTIVE_INTERFACES+=("$ID_NET_NAME_ONBOARD")
            fi
        fi
    done

    if [ ${#ACTIVE_INTERFACES[@]} -eq 1 ]; then
        ACTIVE_INTERFACE=${ACTIVE_INTERFACES[0]}
    elif [ ${#ACTIVE_INTERFACES[@]} -gt 1 ]; then
        echo "Найдено несколько активных проводных интерфейсов. Пожалуйста, выберите один:"
        for i in "${!ACTIVE_INTERFACES[@]}"; do
            echo "$((i+1))) ${ACTIVE_INTERFACES[$i]}"
        done
        read -p "Введите номер интерфейса: " INTERFACE_CHOICE
        ACTIVE_INTERFACE=${ACTIVE_INTERFACES[$((INTERFACE_CHOICE-1))]}
    else
        echo "Активные проводные интерфейсы не найдены."
        exit 1
    fi

    echo "Выбранный интерфейс: $ACTIVE_INTERFACE"

    MOUNTED_FS_IP=$(grep 'address' $CONFIG_FILE | grep -v 'lo' | awk '{print $2}')
    MOUNTED_FS_GATEWAY=$(grep 'gateway' $CONFIG_FILE | awk '{print $2}')

    echo "Текущий IP в смонтированной файловой системе: $MOUNTED_FS_IP"
    echo "Текущий шлюз в смонтированной файловой системе: $MOUNTED_FS_GATEWAY"
    echo "Текущий IP хоста: $HOST_IP"
    echo "Текущий шлюз хоста: $HOST_GATEWAY"
    read -p "Вы хотите изменить IP адрес на $HOST_IP? [y/N]: " CHANGE_IP

    if [[ $CHANGE_IP =~ ^[Yy]$ ]]
    then
        NEW_IP=$HOST_IP
        # Перед обновлением шлюза спрашиваем у пользователя
        read -e -p "Вы хотите изменить шлюз на $HOST_GATEWAY? [y/N]: " CHANGE_GATEWAY
        NEW_GATEWAY=${CHANGE_GATEWAY:-$MOUNTED_FS_GATEWAY}

        # Проверяем, существует ли файл /etc/hostname
        HOSTNAME_FILE="/mnt/etc/hostname"
        if [ -f "$HOSTNAME_FILE" ]; then
            SHORT_NAME=$(cat $HOSTNAME_FILE)
        else
            echo "Файл hostname не найден."
            exit 1
        fi

        # Получаем FQDN из файла hosts
        HOSTS_FILE="/mnt/etc/hosts"
        FQDN=$(grep "$SHORT_NAME" $HOSTS_FILE | awk '{print $2}')
        FQDN=${FQDN:-$SHORT_NAME}

        # Обновляем файлы конфигурации
        sed -i "/iface vmbr0 inet static/,/iface|auto|source/ s|address .*|address $NEW_IP|" $CONFIG_FILE
        sed -i "s|.* ${SHORT_NAME}$|${NEW_IP} ${FQDN} ${SHORT_NAME}|" $HOSTS_FILE
        sed -i "/gateway /c\gateway $NEW_GATEWAY" $CONFIG_FILE

        # Обновляем DNS сервер в /etc/resolv.conf
        RESOLV_CONF="/mnt/etc/resolv.conf"
        sed -i "s|nameserver .*|nameserver 1.1.1.1|" $RESOLV_CONF
    fi

    echo "Новый IP-адрес: $NEW_IP"
    echo "Новый шлюз: $NEW_GATEWAY"

    sed -i "s|iface $CURRENT_INTERFACE inet manual|iface $ACTIVE_INTERFACE inet manual|" $CONFIG_FILE
    sed -i "s|bridge-ports $CURRENT_INTERFACE|bridge-ports $ACTIVE_INTERFACE|" $CONFIG_FILE

    echo "Обновленная конфигурация:"
    cat $CONFIG_FILE

    echo "Обновленный файл /etc/hosts:"
    cat $HOSTS_FILE

    echo "Обновленный файл /etc/resolv.conf:"
    cat $RESOLV_CONF

    read -p "Вы хотите размонтировать файловую систему? [y/N]: " UMOUNT_FS

    if [[ $UMOUNT_FS =~ ^[Yy]$ ]]
    then
        eval "zfs set mountpoint=/ ${ZFS_ROOT}"
        eval "zpool export rpool"
    fi

    H1 "Proxmox will be enabled at this link in 2 minutes after reboot"

    H1 "PVE -   https://${NEW_IP}:8006"
    H1 "PBS -   https://${NEW_IP}:8007"

    Q "reboot?" && reboot
fi
