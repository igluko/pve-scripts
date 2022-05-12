#!/bin/bash

if [ $# -ne 1 ]; then
	echo "usage: sync.sh 1.2.3.4"
	exit 1
fi

DST_NODE=$1
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q root@$DST_NODE"


eval  '/usr/sbin/syncoid --sshoption="ConnectTimeout=5" --skip-parent -r --sendoptions=-wR --force-delete \
--recvoptions="-F -o keylocation=file:///tmp/passphrase" rpool/data root@$DST_NODE:rpool/data'

# load keys
if $SSH "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | grep -q ."
then
	echo "Warning: found unavailable keys"
	$SSH "zfs list -H -o name,keystatus,keylocation | awk '\$2==\"unavailable\" && \$3!=\"prompt\" {print \$1}' | xargs -n1 zfs load-key"
fi
