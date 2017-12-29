#!/bin/bash
PORT=$1
ROLE=$2
a=$(redis-cli -p $PORT info Replication|grep role:|awk -F ':' '{print $2}'|awk -F '\r' '{print $1}' )
if [ $a = $ROLE ]; then
		exit 0
	else
	   exit 2
fi
