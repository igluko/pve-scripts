#!/bin/bash
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

function help(){
    echo "Usages:" 
    echo "  sync.sh --add_labels"
    echo "  sync.sh --add_cron"
    echo "  sync.sh 1.2.3.4 LABEL"
    exit 1
}

# print help
if [ $# -eq 0 ]; then
    help
fi

if [ $# -eq 1 ]; then
    if [ $1 == "--add_labels" ]
    then
        ZFS_WO_LABEL=$(/usr/sbin/zfs list -r -o name,sync:label -H | awk '$2=="-" {print $1}')
        if [ "$ZFS_WO_LABEL" != "" ]; then
            echo "Add default label to:"
            echo "=>"
            echo "$ZFS_WO_LABEL"
            eval "/usr/sbin/zfs list -r -o name,sync:label -H | awk '\$2==\"-\" {print \$1}' | xargs -n1 /usr/sbin/zfs set sync:label=`hostname`"
        fi
    elif [ $1 == "--show_labels" ]
    then
         eval "zfs list -r -o name,sync:label -H"
    fi
    elif [ $1 == "--add_cron" ]
    then
        TASK="* * * * * $SCRIPT --add_labels 2>&1 | logger -t add_labels"
        if crontab -l 2>/dev/null | grep -q "$TASK"
        then 	
            echo "task already has been added to crontab"
        else
            (crontab -l 2>/dev/null; echo "$TASK") | crontab -
        fi
    else
        help
    fi
elif [ $# -ne 2 ]; then
    help
fi

DST_NODE=$1
LABEL=$2
SSH_OPT="BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q"
SSH="ssh -o $SSH_OPT root@$DST_NODE"
SCP="scp -o $SSH_OPT"
SYNCOID="/usr/sbin/syncoid --sshoption=\"$SSH_OPT\" --sendoptions=-wR --force-delete --exclude=\".*-[8-9][0-9][0-9]-disk-[0-9]+\""

# check syncoid is available
if [ ! -f /usr/sbin/syncoid ]; then
    echo "[WARN] file /usr/sbin/syncoid not exists, installing syncoid"
    apt update
    apt install debhelper libcapture-tiny-perl libconfig-inifiles-perl pv lzop mbuffer build-essential -y
    # it doesn't work in root directory
    cd /tmp
    # Download the repo as root to avoid changing permissions later
    git clone https://github.com/jimsalterjrs/sanoid.git
    cd sanoid
    # checkout latest stable release or stay on master for bleeding edge stuff (but expect bugs!)
    git checkout $(git tag | grep "^v" | tail -n 1)
    ln -s packages/debian .
    dpkg-buildpackage -uc -us
    apt install ../sanoid_*_all.deb
    
    # enable and start the sanoid timer
    systemctl enable sanoid.timer
    systemctl start sanoid.timer

    patch --batch /usr/sbin/syncoid $SCRIPTPATH/syncoid.patch
fi

# check jq is available
if [ ! -f /usr/bin/jq ]; then
    echo "[WARN] file /usr/bin/jq not exists install jq"
    apt update 
    apt install jq -y
fi

for STOR in $($SSH pvesh get /nodes/\`hostname\`/storage --output=json-pretty | jq -r '.[] | select(.type=="zfspool" and .active==1) | .storage')
do
    ZFS_LOCAL=""
    ZFS_REMOTE=""
    ZFS_LOCAL=$(pvesh get /storage --output=json-pretty | jq -r ".[] | select(.storage==\"$STOR\") | .pool")
    ZFS_REMOTE=$($SSH pvesh get /storage --output=json-pretty | jq -r ".[] | select(.storage==\"$STOR\") | .pool")
    if [ "$ZFS_LOCAL" != "" ] && [ "$ZFS_REMOTE" != "" ]; then
        echo "FROM $ZFS_REMOTE"
        echo "TO   $ZFS_LOCAL"
        echo "---"
        for ZFS in $($SSH "zfs list -r -o name,sync:label -H $ZFS_REMOTE | awk '\$2==\"$LABEL\" {print \$1}' | grep -v \"^$ZFS_REMOTE\$\" | awk -F  / '{print \$NF}'")
        do
            echo $ZFS
            eval "$SYNCOID root@$DST_NODE:$ZFS_REMOTE/$ZFS $ZFS_LOCAL/$ZFS"
        done
    else
        echo "ERROR: ZFS_LOCAL=$ZFS_LOCAL, ZFS_REMOTE=$ZFS_REMOTE"
    fi
done 

# sync configs
eval  "$SCP -r root@$DST_NODE:/etc/pve/local/qemu-server/[1-7]* /etc/pve/local/qemu-server/ 2>/dev/null"
eval  "$SCP -r root@$DST_NODE:/etc/pve/local/lxc/[1-7]* /etc/pve/local/lxc/ 2>/dev/null"

# load keys
for ZFS in $(zfs list -H -o name,keystatus,keylocation | awk '$2=="unavailable" && $3!="prompt" {print $1}')
do
    echo "load-key for $ZFS"
    zfs set keylocation=file:///tmp/passphrase $ZFS
    zfs load-key $ZFS
done

exit 0
#-----------------------------------------------#
# get labels
eval "zfs list -r -o name,sync:label -H"
# clear labels
zfs list -r -o name -H | xargs -n1 zfs set sync:label=-
# set default labels
eval "zfs list -r -o name,sync:label -H | awk '\$2==\"-\" {print \$1}' | xargs -n1 zfs set sync:label=`hostname`"
# set custom label
zfs set sync:label=`hostname`-slow rpool/data/vm-100-disk-0