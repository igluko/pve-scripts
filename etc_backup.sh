#!/bin/bash

# read envivoments
source  /etc/environment

export PBS_LOG=error
export PBS_PASSWORD=$PBS_PASSWORD
export PBS_REPOSITORY=$PBS_REPOSITORY

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`
# add binary folders to local path
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

if [[ $1 == "--add_cron" ]]; then
    TASK="0 23 * * * $SCRIPT"
    if crontab -l 2>/dev/null | grep -F -q "$TASK"
    then 
        echo "task already has been added to crontab"
    else
        (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    fi
    exit 0
fi
mkdir -p /home/backup
cp -r /etc /home/backup/etc
proxmox-backup-client backup home.pxar:/home/backup/ > /dev/null
