#!/bin/bash

###
# This script prepares a new PVE node
# Tested on Hetzner AX-101 servers
###

# Helpful to read output when debugging
# set -x

#https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Strict mode
# set -eEuo pipefail
set -eEu
trap 'printf "${RED}Failed on line: $LINENO at command:${NC}\n$BASH_COMMAND\nexit $?\n"' ERR
# IFS=$'\n\t'

# read envivoments
source  /etc/environment
# get real path to script
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

export PBS_PASSWORD=$PBS_PASSWORD
export PBS_REPOSITORY=$PBS_REPOSITORY

#-----------------------START-----------------------#

function backup {
    mkdir -p /home/backup
    cp -r /etc /home/backup/etc
    cp -r /root/Sync/floppy /home/backup/floppy
    proxmox-backup-client backup home.pxar:/home/backup/
}

# Если интерактивный режим
if [[ -t 1 ]]
then
    printf "\n"

    # Проверка соединение
    proxmox-backup-client login

    # Добавление в крон
    TASK="0 23 * * * $SCRIPT"
    if crontab -l 2>/dev/null | grep -F -q "$TASK"
    then 
        echo "task already has been added to crontab"
    elif crontab -l 2>/dev/null | grep -F -q "$SCRIPT"
    then
        echo "update crontab task"
        ESCAPED_REPLACE=$(printf '%s\n' "$TASK" | sed -e 's/[\/&]/\\&/g')
        ESCAPED_MATCH=$(printf '%s\n' "$SCRIPT" | sed -e 's/[\/&]/\\&/g')
        eval "crontab -l 2>/dev/null | sed '/$ESCAPED_MATCH/ s/.*/${ESCAPED_REPLACE}/' | crontab -"
    else
        echo "add task to crontab"
        (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    fi
    # Запуск бэкапа
    printf "\n"
    backup
else
    # Выводим только ошибки
    export PBS_LOG=error
    # Подавление std_out нужно для поддержки старого клиента.
    # Начиная с версии примерно 2.2.7 все сообщение пишутся в канал std_err
    backup >/dev/null
fi

