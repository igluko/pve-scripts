#!/bin/bash

# check number of parameters
if [ $# -ne 1 ]; then
    echo "usage: sync.sh 1.2.3.4"
    exit 1
fi

# check syncoid is available
if [ ! -f /usr/sbin/syncoid ]; then
    echo "file /usr/sbin/syncoid not exists, please install syncoid"
    exit 1
fi

DST_NODE=$1
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q root@$DST_NODE"
SCP="scp -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q"
SYNCOID='/usr/sbin/syncoid --sshoption="ConnectTimeout=5" --skip-parent -r --sendoptions=-wR --force-delete --recvoptions="-F -o keylocation=file:///tmp/passphrase" --exclude=".*-[6-9][0-9][0-9]-disk-[0-9]+"'

# sync configs
eval  "$SCP -r /etc/pve/local/qemu-server/[1-5]* root@$DST_NODE:/etc/pve/local/qemu-server/ 2>/dev/null"
eval  "$SCP -r /etc/pve/local/lxc/[1-5]* root@$DST_NODE:/etc/pve/local/lxc/ 2>/dev/null"

# sync rpool/data
eval "$SYNCOID rpool/data root@$DST_NODE:rpool/data"

# sync hdd
#eval "$SYNCOID hdd root@$DST_NODE:hdd"

# load keys
if $SSH "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | grep -q ."
then
    echo "Warning: found unavailable keys"
    $SSH "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | xargs -n1 zfs load-key"
fi
