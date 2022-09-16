#!/bin/bash
# На сервере должны быть настроены глобальные переменные окружения $TG_TOKEN и $TG_CHAT (/etc/environment)

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

# read envivoments
source  /etc/environment
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

available=`/usr/sbin/zfs list -Hp -o available rpool | /usr/bin/awk '{printf "scale=0;(%s)/1024/1024/1024\n", ($1) }' | /usr/bin/bc`
if [ $available -lt 10 ]; then
        MESSAGE="⚠️  PVE.DARUSH: only $available GB available"
        JSON="{\"chat_id\": \"$TG_CHAT\",\"parse_mode\": \"html\", \"text\": \"$MESSAGE\",\"disable_notification\": true}"

        /usr/bin/curl -X POST \
             -H 'Content-Type: application/json' \
             -d "$JSON" \
#             --socks5 {url}:1080 --proxy-user {login}:{pass} \
             https://api.telegram.org/$TG_TOKEN/sendMessage
fi
