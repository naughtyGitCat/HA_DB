#!/bin/bash

CONSUL1=192.168.1.120
CONSUL2=192.168.1.121
CONSUL3=192.168.1.8

IP=$(ip addr|egrep '/24'|tr -s ' '|awk -F ' ' '{print $2}'|awk -F '/' '{print $1}')
NAME=`hostname`

function depend_install()
{
	printf "安装依赖软件...."
	yum -y install unzip lrzsz bind-utils
}

function download_binary()
{
	cd /usr/local/src
	printf "请上传go程序...."
	rz
	printf "\033[32;1m%20s\033[0m\n" "[ OK ]" 
	printf "请上传consul程序...."
	rz
	printf "\033[32;1m%20s\033[0m\n" "[ OK ]" 
}

function unzip_reg()
{
	printf "解压程序并关联bin文件...."
	unzip consul*.zip -d /usr/local/bin
	tar -zxf go*.tar.gz -C /usr/local/
	echo "PATH=$PATH:/usr/local/go/bin" >>/etc/profile
	source /etc/profile
	go version
	consul --version
	printf "\033[32;1m%20s\033[0m\n" "[ OK ]" 
}

function write_conf()
{
 mkdir -p /etc/consul
 mkdir -p /data/consul
 cd /etc/consul
 cat >consul_conf.json<<EOF
 
 {
    "advertise_addr": "$IP",
    "bind_addr": "$IP",
    "domain": "consul",
    "bootstrap_expect": 2,
    "server": true,
    "datacenter": "consul-cluster",
    "data_dir": "/data/consul",
    "enable_syslog": true,
    "performance": {
      "raft_multiplier": 1
    },
    "dns_config": {
        "allow_stale": true,
        "max_stale": "15s"
    },
    "retry_join": [
        "$CONSUL1",
        "$CONSUL2",
		"$CONSUL3"
    ],
    "retry_interval": "10s",
    "skip_leave_on_interrupt": true,
    "leave_on_terminate": false,
    "ports": {
        "dns": 53,
        "http": 8500
    },
    "recursors": [
        "192.168.1.1"
    ],
    "rejoin_after_leave": true,
    "addresses": {
        "http": "0.0.0.0",
        "dns": "0.0.0.0"
    }
}

EOF
}

function hostname_resolve()
{
cat  >/etc/resolv.conf<<EOF
nameserver $CONSUL1
nameserver $CONSUL2
nameserver $CONSUL3
EOF
cat >>/etc/hosts<<EOF
$IP $NAME
EOF
}

function intention()
{
printf "服务集群地址为....$CONSUL1"
printf "服务集群地址为....$CONSUL2"
printf "服务集群地址为....$CONSUL3"
printf "本机地址为$IP"
printf "使用方法：step1:cd /data/consul "
printf "使用方法：step2:nohup consul agent -config-dir /etc/consul/ -server -ui -rejoin &"
}

depend_install
download_binary
unzip_reg
write_conf
hostname_resolve
intention