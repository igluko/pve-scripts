#!/bin/bash
# Скрипт для проверки свежести syncoid снимков.
# Скрипт найдет иснимки старше чем переданное количество часов.
# Если снимки будут найдены, скрипт отправит сообщение в телеграм
# На сервере должны быть настроены глобальные переменные окружения $TG_TOKEN и $TG_CHAT (/etc/environment)
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

function help(){
    echo "Example: search syncoid snaps older then 12 hours ago" 
    echo "  sync-check.sh 12"
    exit 1
}

if [ $# -ne 1 ]; then
    help
fi

TIME=$(/usr/bin/date +%s -d "$1 hour ago")
OLD_SNAPS=$(/usr/sbin/zfs list -H -p -t snapshot -o sync:label,name,creation | grep syncoid | awk -v time=$TIME '$3<time {printf "<b>#%s</b> %s %%0A" , $1, $2}')
if [[ "$OLD_SNAPS" != "" ]]
then
    /usr/bin/curl -X POST https://api.telegram.org/bot$TG_TOKEN/sendMessage -d parse_mode=html -d chat_id=$TG_CHAT -d text="<b>Найдены старые снимки Syncoid</b>%0A $OLD_SNAPS" &>/dev/null
fi