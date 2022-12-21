#!/bin/bash

###
# This should protect important system datasets from a total lack of free space.
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

# get real path to script
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

#-----------------------START-----------------------#

if [ "$#" -ne 2 ]; then
    echo "Illegal number of parameters"
    exit 1
fi

# Add to cron if terminal exist
if [[ -t 1 ]]
then
    TASK="* * * * * ${SCRIPT} $*"
    if crontab -l 2>/dev/null | grep -F -q "${TASK}"
    then
        echo "task already has been added to crontab"
    else
        (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    fi
fi

size=`/usr/sbin/zfs get used $1 -o value -H -p`

if [[ $2 =~ "%" ]]; then
  
  reserv=`echo "scale=0; $size*(100+${2//%})/100" | bc`
else
  reserv=`echo "scale=0; $size+$2" | bc`
fi

#echo "size:   $size"
#echo "reserv: $reserv"

`/usr/sbin/zfs set reservation="$reserv" $1`