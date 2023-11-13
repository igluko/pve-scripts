#!/bin/bash
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

function help(){
    echo "Usages:" 
    echo "  sync2.sh 1.2.3.4 LABEL"
    exit 1
}

if [ $# -ne 2 ]; then
    help
fi

DST_NODE=$1
LABEL=$2
SSH_OPT="BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
SSH="ssh -o $SSH_OPT root@$DST_NODE"
SCP="scp -o $SSH_OPT"
# Use this fork https://github.com/mr-vinn/sanoid for --include-snaps filter
SYNCOID="/usr/sbin/syncoid --sshoption=\"$SSH_OPT\" --sendoptions=-wR --force-delete --no-sync-snap --include-snaps=autosnap"

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
        # add default label
        ZFS_WO_LABEL=$($SSH "zfs list -r -o name,sync:label -H $ZFS_REMOTE  | awk '\$2==\"-\" {print \$1}' | grep -v \"^$ZFS_REMOTE\$\"")
        if [ "$ZFS_WO_LABEL" != "" ]; then
            echo "Add default label to:"
            echo "=>"
            echo "$ZFS_WO_LABEL"
            for ZFS in $ZFS_WO_LABEL
            do
                eval "$SSH 'zfs set sync:label=\$(hostname) $ZFS'"
            done
        fi
        # replicate
        echo "FROM $ZFS_REMOTE"
        echo "TO   $ZFS_LOCAL"
        echo "---"
        for ZFS in $($SSH "zfs list -r -o name,sync:label -H $ZFS_REMOTE | awk '\$2==\"$LABEL\" {print \$1}' | grep -v \"^$ZFS_REMOTE\$\" | awk -F  / '{print \$NF}'")
        do
            VMID=$(echo $ZFS | awk -F - '{print $2}')
            echo "$VMID - $ZFS"

            # If the dataset name contains -state-suspend-, then skip it
            if [[ $ZFS == *"state-suspend-"* ]]; then
                echo "skip"
                continue
            fi

            if (echo "$VMID" | grep -q [1-7][0-9][0-9])
            then
                # zfs
                eval "$SYNCOID root@$DST_NODE:$ZFS_REMOTE/$ZFS $ZFS_LOCAL/$ZFS"
                # config
                eval "rsync --checksum --ignore-missing-args root@$DST_NODE:/etc/pve/local/qemu-server/$VMID.conf /etc/pve/local/qemu-server/"
                eval "rsync --checksum --ignore-missing-args root@$DST_NODE:/etc/pve/local/lxc/$VMID.conf /etc/pve/local/lxc/"
            else
                echo "skip"
            fi
        done
    else
        echo "ERROR: ZFS_LOCAL=$ZFS_LOCAL, ZFS_REMOTE=$ZFS_REMOTE"
    fi
done 

# load keys
for ZFS in $(zfs list -H -o name,keystatus,keylocation | awk '$2=="unavailable" && $3=="prompt" {print $1}')
do
    echo "load-key for $ZFS"
    # Get parent dataset
    PARENT_DATASET=${ZFS%/*}
    # If parent dataset exists and has a keylocation set
    if [ -n "$PARENT_DATASET" ] && [ "$(zfs get -H -o value keylocation "$PARENT_DATASET")" != "none" ]; then
        PARENT_KEYLOCATION=$(zfs get -H -o value keylocation "$PARENT_DATASET")
        echo "load-key for $ZFS"
        zfs set keylocation="$PARENT_KEYLOCATION" $ZFS
        zfs load-key $ZFS
    fi
done


exit 0
#-----------------------------------------------#
# get labels
eval "zfs list -r -o name,sync:label -H"
# clear labels  
zfs inherit -r sync:label rpool
# set default label
zfs set sync:label=`hostname` rpool/data/vm-100-disk-0
# set custom label
zfs set sync:label=`hostname`-slow rpool/data/vm-100-disk-0
