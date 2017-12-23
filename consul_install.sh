#!/bin/bash

IP=$(ip addr|egrep '/24'|tr -s ' '|awk -F ' ' '{print $2}'|awk -F '/' '{print $1}')
NAME=`hostname`

function depend_install()
{
	printf "安装依赖软件...."
	yum -y install unzip lrzsz
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
        "192.168.100.195",
        "192.168.100.196",
		"192.168.100.197"
    ],
    "retry_interval": "10s",
    "skip_leave_on_interrupt": true,
    "leave_on_terminate": false,
    "ports": {
        "dns": 53,
        "http": 8500
    },
    "recursors": [
        "114.114.114.114"
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
nameserver 192.168.100.195
nameserver 192.168.100.196
nameserver 192.168.100.197
EOF
cat >>/etc/hosts<<EOF
$IP $NAME
EOF
}

function intention()
{
printf "服务集群地址为....192.168.100.195"
printf "服务集群地址为....192.168.100.196"
printf "服务集群地址为....192.168.100.197"
printf "本机地址为$IP"
}

depend_install
download_binary
unzip_reg
write_conf
intention
