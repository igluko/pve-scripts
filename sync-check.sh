#!/bin/bash

###
# Скрипт для проверки свежести syncoid снимков.
# Скрипт найдет иснимки старше чем переданное количество часов.
# Если снимки будут найдены, скрипт отправит сообщение в телеграм
# На сервере должны быть настроены глобальные переменные окружения $TG_TOKEN и $TG_CHAT (/etc/environment)
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

#-----------------------START-----------------------#

# Проверка количества переданных аргументов
if [ $# -ne 1 ]
then
    printf "${RED}Wrong number of arguments${NC}\n"
    echo "Example: search syncoid snaps older then 12 hours ago"
    echo "  sync-check.sh 12"
    exit 1
fi

# Если интерактивный режим
if [[ -t 1 ]]
then
    printf "\n"
    # Добавление в крон
    TASK="0 9 * * * $SCRIPT $1"
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
fi

# Основной код
TIME=$(date +%s -d "$1 hour ago")
OLD_SNAPS=$(zfs list -H -p -t snapshot -o sync:label,name,creation | grep 'syncoid\|replicate' | awk -v time=$TIME '$3<time {printf "<b>#%s</b> %s %%0A" , $1, $2}')
if [[ "$OLD_SNAPS" != "" ]]
then
    HEADER="Найдены старые снимки Syncoid на $(hostname)"
    curl -X POST https://api.telegram.org/bot$TG_TOKEN/sendMessage -d parse_mode=html -d chat_id=$TG_CHAT -d text="<b>$HEADER</b>%0A $OLD_SNAPS" &>/dev/null
fi