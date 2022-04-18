#!/bin/bash

if [ $# -ne 2 ]; then
  echo "2 arguments expected. Usage: switch.sh -f(rom)=100 -t(o)=101"
  exit 1
fi

for i in "$@"
do
case $i in
    -f=*|--from=*)
    FROM="${i#*=}"
    shift # past argument=value
    ;;
    -t=*|--to=*)
    TO="${i#*=}"
    shift # past argument=value
    ;;
    *)
        # unknown option
    ;;
esac
done

TIMEOUT=100
counter=0

qm agent $FROM suspend-disk

expr="\$1==$FROM {print \$3}"
state=`qm list | awk "$expr"`
echo "$state wait..."

while [ "$state" != "stopped" ]
do
  sleep 1
  state=`qm list | awk "$expr"`
  echo "$state wait..."
  ((counter=counter+1))

  if [ $counter -gt $TIMEOUT ]; then
    echo "Timeout $counter sec"
    exit 1
  fi
done

qm start $TO
