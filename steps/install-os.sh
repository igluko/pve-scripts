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

IP=$(hostname -I | awk '{print $1}')

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
    H1 "Please open VNC console to ${IP}, install PVE and press Next"
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

    # -o options An optional, comma-separated list of mount options to use temporarily for the duration of the mount
    # Not worked
    # https://github.com/openzfs/zfs/issues/4553
    # eval "zfs mount -o mountpoint=/mnt ${ZFS_ROOT} || true"
    zfs set mountpoint=/mnt ${ZFS_ROOT}
    zfs mount ${ZFS_ROOT} || true

    printf "${GREEN}"
    for i in $(ls /sys/class/net/ | grep -v lo)
    do
        udevadm test /sys/class/net/$i 2>/dev/null | grep ID_NET_NAME_
    done
    printf "${NC}"

    # Путь к файлу конфигурации
    CONFIG_FILE="/mnt/etc/network/interfaces"

    # Извлекаем текущий интерфейс, используемый в конфигурации vmbr0
    CURRENT_INTERFACE=$(awk '/bridge-ports/ {print $2}' $CONFIG_FILE)

    # Убедитесь, что CURRENT_INTERFACE был определен
    if [ -z "$CURRENT_INTERFACE" ] || [ "$CURRENT_INTERFACE" = "none" ]; then
        echo "Текущий интерфейс не найден в файле конфигурации."
        exit 1
    fi

    # Получаем список всех физических сетевых интерфейсов, исключая loopback, docker и veth
    ALL_INTERFACES=$(ls /sys/class/net | grep -v 'lo\|docker\|veth')

    # Определяем активные проводные интерфейсы
    ACTIVE_INTERFACES=()
    for IFACE in $ALL_INTERFACES; do
        # Проверяем, является ли интерфейс активным и не является USB
        if [[ "$(cat /sys/class/net/$IFACE/operstate)" == "up" ]] && [[ -z $(udevadm info --path=/sys/class/net/$IFACE | grep ID_BUS | grep usb) ]]; then
            ID_NET_NAME_ONBOARD=$(udevadm info --path=/sys/class/net/$IFACE | grep ID_NET_NAME_ONBOARD | awk -F '=' '{print $2}')
            if [ ! -z "$ID_NET_NAME_ONBOARD" ]; then
                ACTIVE_INTERFACES+=("$ID_NET_NAME_ONBOARD")
            fi
        fi
    done


    # Выбор активного интерфейса
    if [ ${#ACTIVE_INTERFACES[@]} -eq 1 ]; then
        # Если найден только один активный интерфейс, используем его
        ACTIVE_INTERFACE=${ACTIVE_INTERFACES[0]}
    elif [ ${#ACTIVE_INTERFACES[@]} -gt 1 ]; then
        # Если есть несколько активных интерфейсов, предлагаем пользователю выбрать
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

    # Извлекаем текущие настройки IP и шлюза
    CURRENT_IP=$(grep 'address' $CONFIG_FILE | grep -v 'lo' | awk '{print $2}')
    CURRENT_GATEWAY=$(grep 'gateway' $CONFIG_FILE | awk '{print $2}')

    # Запрашиваем у пользователя новые значения, предлагая текущие в качестве значений по умолчанию
    read -e -p "Введите новый IP-адрес: " -i "$CURRENT_IP" NEW_IP
    NEW_IP=${NEW_IP:-$CURRENT_IP}

    read -e -p "Введите новый шлюз: " -i "$CURRENT_GATEWAY" NEW_GATEWAY
    NEW_GATEWAY=${NEW_GATEWAY:-$CURRENT_GATEWAY}

    # Выводим обновленные значения
    echo "Новый IP-адрес: $NEW_IP"
    echo "Новый шлюз: $NEW_GATEWAY"

    # Теперь используем переменную ACTIVE_INTERFACE для обновления файла конфигурации
    sed -i "s|iface $CURRENT_INTERFACE inet manual|iface $ACTIVE_INTERFACE inet manual|" $CONFIG_FILE
    sed -i "/iface vmbr0 inet static/,/iface|auto|source/ s|address .*|address $NEW_IP|" $CONFIG_FILE
    sed -i "/iface vmbr0 inet static/,/iface|auto|source/ s|gateway .*|gateway $NEW_GATEWAY|" $CONFIG_FILE
    sed -i "s|bridge-ports $CURRENT_INTERFACE|bridge-ports $ACTIVE_INTERFACE|" $CONFIG_FILE

    # Выводим обновленную конфигурацию
    echo "Обновленная конфигурация:"
    cat $CONFIG_FILE

    # Путь к файлам
    HOSTS_FILE="/mnt/etc/hosts"
    HOSTNAME_FILE="/mnt/etc/hostname"

    # Чтение имени хоста из файла hostname
    if [ -f "$HOSTNAME_FILE" ]; then
        HOST_NAME=$(cat $HOSTNAME_FILE)
    else
        echo "Файл hostname не найден."
        exit 1
    fi

    # Замена IP-адреса в файле /etc/hosts
    # Ищем строку, содержащую имя хоста, и заменяем в ней IP-адрес
    # Используем '|' вместо '/' в качестве разделителя для sed
    sed -i "|$HOST_NAME| s|.*|${NEW_IP} ${HOST_NAME}|" $HOSTS_FILE

    # Показываем обновленный файл hosts
    echo "Обновленный файл /etc/hosts:"
    cat $HOSTS_FILE

    eval "zfs set mountpoint=/ ${ZFS_ROOT}"
    eval "zpool export rpool"

    H1 "Proxmox will be enabled at this link in 2 minutes after reboot"

    H1 "PVE -   https://${IP}:8006"
    H1 "PBS -   https://${IP}:8007"

    Q "reboot?" && reboot
fi