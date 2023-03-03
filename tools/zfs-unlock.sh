#!/bin/bash
# set -x # Helpful to read output when debugging

# Этот скрипт загружает ключи шифрованных ZFS датасетов и томов
# 1) из аргумента во время вызова скрипта
# 2) из DNS TXT
# 3) из HTTPS URL

# /etc/environment: 
#   TXT_ZFS_KEY=ZFS_KEY # Загрузить ключ из DNS записи ZFS_KEY
#        or
#   URL_ZFS_KEY=https://domain.com/secret-link

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

# read envivoments
source  /etc/environment
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

load-key() {
  local KEY=$1
  if [[ -n "$KEY" ]]
  then
    echo $KEY
    yes $KEY | zfs load-key -a -L prompt
  fi
}

if [[ -n "$1" ]]
then
  KEY=$1
  load-key $KEY
  exit 0
fi

if [[ -n "$TXT_ZFS_KEY" ]]
then
  echo "Load key from DNS TXT:$TXT_ZFS_KEY"
  KEY=$(dig +short txt $TXT_ZFS_KEY | xargs) # use xargs for trim
  load-key $KEY
fi

if [[ -n "$URL_ZFS_KEY" ]]
then
  echo "Load key from URL $URL_ZFS_KEY"
  KEY=$(curl -s $URL_ZFS_KEY)
  load-key $KEY
fi