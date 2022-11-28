#!/bin/bash

# get real path to script
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

if [[ $1 == "--add_cron" ]]; then
    TASK="* 8,23 * * * $SCRIPT"
    if crontab -l 2>/dev/null | grep -F -q "$TASK"
    then 	
        echo "task already has been added to crontab"
    else
        (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    fi
fi


if zpool status -v | grep 'progress' 1>/dev/null
then
 zpool scrub -p rpool
 exit 0
fi
if zpool status -v | grep 'paused' 1>/dev/null
then
 zpool scrub rpool
 exit 0
fi