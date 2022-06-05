#!/bin/bash
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

if [[ $1 == "--add_cron" ]]; then
    TASK="* * * * * $SCRIPT"
    if crontab -l 2>/dev/null | grep -F -q "$TASK"
    then 	
        echo "task already has been added to crontab"
    else
        (crontab -l 2>/dev/null; echo "$TASK") | crontab -
    fi
fi

function getMemFree(){
    running_vm=`/usr/sbin/qm list | grep running`
    running_mem=0
    if [[ -n "$running_vm" ]]; then
    running_mem=`echo "$running_vm" | awk '{print $4}' | paste -sd+ | awk '{printf "scale=0;(%s)/1024\n", ($1) }' | bc`
    fi

    total_mem=`cat /proc/meminfo | awk '$1=="MemTotal:" {printf "%.f", $2/1024/1024 }'`
    arc_mem=`cat /proc/spl/kstat/zfs/arcstats | awk '$1=="size" {printf "%.f", $3/1024/1024/1024 }'`

    echo "#Total Mem: **$total_mem GB**  "
    echo "#"
    echo "#Running VM Reserved: **$running_mem GB**  "
    echo "#"
    awk '$1=="size" {printf "#ARC SIZE = **%.f GB** \n", $3/1024/1024/1024 }' /proc/spl/kstat/zfs/arcstats
    echo "#"
}

function getSyncoidSnaps(){
    echo "#**Syncoid snapshots:**"
    echo "#"
    /usr/sbin/zfs list -t snapshot -o sync:label,name  2>/dev/null | grep syncoid | awk '{printf "#%s \\\n" , $0}'
    echo "#**end**"
}

getMemFree>"/etc/pve/local/config"
getSyncoidSnaps>>"/etc/pve/local/config"