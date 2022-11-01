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
    echo "#<table align='center'> 
      #<caption><b>RAM Usage:</b></caption>
      #  <tr>
      #    <th>Total Mem:</th>
      #    <th>Running VM Reserved:</th>
      #    <th>ARC Size:</th>
      #  </tr>"
    echo "#  <tr>
        #    <td align='center'>$total_mem GB</td>"
    echo "#    <td align='center'>$running_mem GB</td>"
    awk '$1=="size" {printf "#    <td align=\"center\">%.f GB</td>\n", $3/1024/1024/1024 }' /proc/spl/kstat/zfs/arcstats
    echo "#  </tr>
    #</table>"
    echo "#<br>"
    echo "#<br>"
}

function getSyncoidSnaps(){
    echo ""
    echo "#<table align='center'> 
      #<caption><b>Syncoid snapshots:</b></caption>
      #  <tr>
      #    <th>Label</th>
      #    <th>Name</th>
      #  </tr>"
    /usr/sbin/zfs list -t snapshot -o sync:label,name  2>/dev/null | grep syncoid | awk '{printf "#  <tr>\n#    <td><b>%s</b></td>\n#    <td>%s</td>\n#  </tr>\n" , $1, $2}'
    echo "#</table>"
    echo "#<br>"
    echo "#<br>"
    echo ""
}

function getZFSList(){
    echo ""
    echo "#<table align='center'> 
      #<caption><b>ZFS List:</b></caption>
      #  <tr>
      #    <th>Name</th>
      #    <th>Used</th>
      #    <th>Avail</th>
      #  </tr>"
    /usr/sbin/zfs list -o name,used,avail | grep -v ROOT | grep -v NAME | awk '{printf "#  <tr>\n#    <td>%s</td>\n#    <td>%s</td>\n#    <td>%s</td>\n#  </tr>\n" , $1, $2, $3}'
    echo "#</table>"
    echo "#<br>"
    echo "#<br>"
}

TEXT="$(getMemFree)$(getZFSList)$(getSyncoidSnaps)"
echo "$TEXT">"/etc/pve/local/config"