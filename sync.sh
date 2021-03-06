#!/bin/bash
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

# check number of parameters
if [ $# -ne 1 ]; then
    echo "usage: sync.sh 1.2.3.4"
    exit 1
fi

DST_NODE=$1
SSH_OPT="BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q"
SSH="ssh -o $SSH_OPT root@$DST_NODE"
SCP="scp -o $SSH_OPT"
SYNCOID="/usr/sbin/syncoid --sshoption=\"$SSH_OPT\" --skip-parent -r --sendoptions=-wR --force-delete --exclude=\".*-[6-9][0-9][0-9]-disk-[0-9]+\""

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
        eval "$SYNCOID root@$DST_NODE:$ZFS_REMOTE $ZFS_LOCAL"
    else
        echo "ERROR: ZFS_LOCAL=$ZFS_LOCAL, ZFS_REMOTE=$ZFS_REMOTE"
    fi
done 

# sync configs
eval  "$SCP -r root@$DST_NODE:/etc/pve/local/qemu-server/[1-5]* /etc/pve/local/qemu-server/ 2>/dev/null"
eval  "$SCP -r root@$DST_NODE:/etc/pve/local/lxc/[1-5]* /etc/pve/local/lxc/ 2>/dev/null"

# load keys
for ZFS in $(zfs list -H -o name,keystatus,keylocation | awk '$2=="unavailable" && $3!="prompt" {print $1}')
do
    echo "load-key for $ZFS"
    zfs set keylocation=file:///tmp/passphrase $ZFS
    zfs load-key $ZFS
done

# load keys
#if eval "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | grep -q ."
#then
#    echo "Warning: found unavailable keys"
#    eval "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | xargs -n1 zfs set keylocation=file:///tmp/passphrase"
#    eval "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | xargs -n1 zfs load-key"
#fi
