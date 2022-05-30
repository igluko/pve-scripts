#!/bin/bash

# check number of parameters
if [ $# -ne 0 ]; then
    echo "usage: sync.sh"
    exit 1
fi

# check syncoid is available
if [ ! -f /usr/sbin/syncoid ]; then
    echo "file /usr/sbin/syncoid not exists, please install syncoid"
    exit 1
fi

DST_NODE="10.25.254.246"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q root@$DST_NODE"
SCP="scp -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q"
SYNCOID='/usr/sbin/syncoid --sshoption="ConnectTimeout=5" --skip-parent -r --sendoptions=-wR --force-delete --recvoptions="-F -o keylocation=file:///tmp/passphrase" --exclude=".*-[6-9][0-9][0-9]-disk-[0-9]+"'

# STORS=$(pvesh get /nodes/`hostname`/storage --output=json-pretty | jq '.[] | select(.type=="zfspool")') 

#STORS=$(pvesh get /nodes/`hostname`/storage --output=json-pretty | jq '[ .[] | select(.type=="zfspool") ]')
for STOR in $(pvesh get /nodes/`hostname`/storage --output=json-pretty | jq -r '.[] | select(.type=="zfspool") | .storage')
do
    ZFS_LOCAL=""
    ZFS_REMOTE=""
    ZFS_LOCAL=$(pvesh get /storage --output=json-pretty | jq -r ".[] | select(.storage==\"$STOR\") | .pool")
    ZFS_REMOTE=$($SSH pvesh get /storage --output=json-pretty | jq -r ".[] | select(.storage==\"$STOR\") | .pool")
    if [ "$ZFS_LOCAL" != "" ] && [ "$ZFS_REMOTE" != "" ]; then
        eval "$SYNCOID root@$DST_NODE:$ZFS _REMOTE $ZFS_LOCAL"
    else
        echo "ERROR: ZFS_LOCAL=$ZFS_LOCAL, ZFS_REMOTE=$ZFS_REMOTE"
    fi
done 

# sync configs
eval  "$SCP -r root@$DST_NODE:/etc/pve/local/qemu-server/[1-5]* /etc/pve/local/qemu-server/ 2>/dev/null"
eval  "$SCP -r root@$DST_NODE:/etc/pve/local/lxc/[1-5]* /etc/pve/local/lxc/ 2>/dev/null"

# load keys
if eval "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | grep -q ."
then
    echo "Warning: found unavailable keys"
    eval "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | xargs -n1 zfs load-key"
fi
