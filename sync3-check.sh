#!/bin/bash

###
# Скрипт для проверки свежести sancoid снимков.
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

# Проверка актуальности снимков
TIME=$(date +%s -d "$1 hour ago")
DATASETS=$(zfs list -o name | grep 'vm-\|subvol-')
for DATASET in $DATASETS
do
    OLD_SNAPS+=$(zfs list -H -p -t snapshot -o sync:label,name,creation $DATASET | grep 'autosnap' | tail -1 | grep -v 'stopped' | awk -v time=$TIME '$3<time {printf "<b>#%s</b> %s %%0A" , $1, $2}')
done

if [[ "$OLD_SNAPS" != "" ]]
then
    HEADER="Найдены старые снимки Syncoid на $(hostname)"
    curl -X POST https://api.telegram.org/bot$TG_TOKEN/sendMessage -d parse_mode=html -d chat_id=$TG_CHAT -d text="<b>$HEADER</b>%0A $OLD_SNAPS" &>/dev/null
    sleep 1
fi

# Проверка соотвествия статуса VM и наличия снимка stopped
RUNVMS=$(qm list | grep -v 'VMID' | awk -v status='running' '$3==status && $1<700 {printf $1}')
if [[ "$RUNVMS" != "" ]]
then
    VMS=$(qm list | awk '{print $1" "$3}' | grep -v 'VMID')
    if [[ $(pct list) != "" ]]
    then
        VMS+=" "
        VMS+=$(pct list | awk '{print $1" "$2}' | grep -v 'VMID')
    fi
    SNAPSHOTS=$(zfs list -H -p -t snapshot -o name)
    STOPSNAPSHOT=""
    I=0
    for WORD in $VMS
    do
        I=$(($I+1))
        if [ $I == 1 ]
        then
            VM=$WORD
            continue
        fi
        if [ $I == 2 ]
        then
            I=0
            STATUS=$WORD
            if [[ -t 1 ]]
            then
                echo $VM $STATUS
            fi
            # Находим снапшоты stopped для VM
            for SNAPSHOT in $SNAPSHOTS
            do
                if [[ $SNAPSHOT =~ "stopped"  && ( $SNAPSHOT =~ "vm-${VM}" || $SNAPSHOT =~ "subvol-${VM}" ) ]]
                then
                    STOPSNAPSHOT+="${SNAPSHOT}\n"
                fi
            done
            if [[ -t 1 ]]
            then
                echo -e $STOPSNAPSHOT
            fi
            # Проверям статус VM
            if [[ "$STATUS" == "stopped" ]]
            then
                if [[ "$STOPSNAPSHOT" == "" ]]
                then
                    HEADER="Нет сников stopped для VM $VM со статусом $STATUS на $(hostname)"
                    curl -X POST https://api.telegram.org/bot$TG_TOKEN/sendMessage -d parse_mode=html -d chat_id=$TG_CHAT -d text="<b>$HEADER</b>%0A" &>/dev/null
                    sleep 1
                fi
            else
                if [[ "$STOPSNAPSHOT" != "" ]]
                then
                    HEADER="Найдены снимки stopped для VM $VM со статусом $STATUS на $(hostname)"
                    STOPSNAPSHOT=$(echo -e $STOPSNAPSHOT)
                    curl -X POST https://api.telegram.org/bot$TG_TOKEN/sendMessage -d parse_mode=html -d chat_id=$TG_CHAT -d text="<b>$HEADER</b>%0A  $STOPSNAPSHOT" &>/dev/null
                    sleep 1
                fi
            fi       
            STOPSNAPSHOT=""
        fi
    done
fi