#!/bin/bash
PORT=$1
ROLE=$2 
a=$(mongo -uroot -psa123456  --port $PORT --host 192.168.1.151 --authenticationDatabase admin --eval "rs.isMaster()"|grep -i "isMaster"|awk -F ':' '{print $2}'|awk -F ',' '{print $1}')
#a=$(redis-cli -p $PORT info Replication|grep role:|awk -F ':' '{print $2}'|awk -F '\r' '{print $1}' )
if [ $a = $ROLE ]; then
	exit 0
else
        exit 2
fi

