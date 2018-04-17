# 【MySQL】【ProxySQL】ProxySQL Cluster的搭建

## 背景：

​	早期的ProxySQL若需要做高可用，需要搭建两个实例，进行冗余。但两个ProxySQL实例之间的数据并不能共通,在主实例上配置后，仍需要在备用节点上进行配置，对管理来说非常不方便。

​	从1.4.2版本后，ProxySQL支持原生的集群搭建，实例之间可以互通一些配置数据，大大简化了管理与维护操作。

## 环境：

| 实例名     | 版本  | IP   | 系统    | 备注     |
| ---------- | ----- | ---- | ------- | -------- |
| ProxySQL 1 | 1.4.6 | 208  | CentOS7 | 最初启动 |
| ProxySQL 2 | 1.4.6 | 209  | CentOS7 | 最初启动 |
| ProxySQL 3 | 1.4.6 | 210  | Debian9 | 后面加入 |

​		

## 搭建：

​	集群的搭建有很多种方式，如1+1+1的方式，还可以(1+1)+1的方式。

​	这里采用较简单的(1+1)+1，即先将两个节点作为集群启动，然后其他节点选择性加入的方式

#### 1.更改所有实例的配置文件：

`vim /etc/proxysql.cnf`

```json
# 需要更改的部分
admin_variables=
{
        admin_credentials="admin:admin;cluster_20X:123456"       #配置用于实例间通讯的账号
#       mysql_ifaces="127.0.0.1:6032;/tmp/proxysql_admin.sock"
        mysql_ifaces="0.0.0.0:6032"							   #全网开放登录
#       refresh_interval=2000
#       debug=true
        cluster_username="cluster_20X"						   #集群用户名称，与最上面的相同
        cluster_password="123456"						       #集群用户密码，与最上面的相同
        cluster_check_interval_ms=200						
        cluster_check_status_frequency=100
        cluster_mysql_query_rules_save_to_disk=true
        cluster_mysql_servers_save_to_disk=true
        cluster_mysql_users_save_to_disk=true
        cluster_proxysql_servers_save_to_disk=true
        cluster_mysql_query_rules_diffs_before_sync=3
        cluster_mysql_servers_diffs_before_sync=3
        cluster_mysql_users_diffs_before_sync=3
        cluster_proxysql_servers_diffs_before_sync=3
}
proxysql_servers =											#在这个部分提前定义好集群的成员
(
        {
                hostname="192.168.1.208"
                port=6032
                comment="primary"							#注释
        },
        {
                hostname="192.168.1.209"
                port=6032
                comment="secondary"
        },
        {
                hostname="192.168.1.210"
                host=6032
                comment="secondary"
        }
)

```

#### 2.启动208和209实例：

`systemctl start proxysql`

#### 3.观察集群状况：

```mysql
mysql> select * from proxysql_servers;
+---------------+------+--------+-----------+
| hostname      | port | weight | comment   |
+---------------+------+--------+-----------+
| 192.168.1.208 | 6032 | 0      | primary   |
| 192.168.1.209 | 6032 | 0      | secondary |
+---------------+------+--------+-----------+
2 rows in set (0.00 sec)
mysql> select * from   stats_proxysql_servers_metrics;
+---------------+------+--------+-----------+------------------+----------+---------------+---------+------------------------------+----------------------------+
| hostname      | port | weight | comment   | response_time_ms | Uptime_s | last_check_ms | Queries | Client_Connections_connected | Client_Connections_created |
+---------------+------+--------+-----------+------------------+----------+---------------+---------+------------------------------+----------------------------+
| 192.168.1.209 | 6032 | 0      | secondary | 0                | 670769   | 11027         | 0       | 0                            | 0                          |
| 192.168.1.208 | 6032 | 0      | primary   | 0                | 702316   | 1169          | 5       | 0                            | 1                          |
+---------------+------+--------+-----------+------------------+----------+---------------+---------+------------------------------+----------------------------+

```

#### 4.观察ProxySQL集群中实例之间的数据同步：

```mysql
#原有数据
mysql> select * from mysql_servers;
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname      | port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 7            | 192.168.1.181 | 3306 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
| 10           | 192.168.1.182 | 3306 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
| 8            | 192.168.1.180 | 3306 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
3 rows in set (0.00 sec)
#在209上插入一条数据：
mysql> insert into mysql_servers(hostgroup_id,hostname,port,comment) values (20,'192.168.1.120',3306,'zabbix');
# 持久化，并加载到运行环境中
mysql> save mysql servers to disk; 
mysql> load mysql servers to runtime;  
# 观察208实例的数据：
mysql> select * from mysql_servers;
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname      | port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 7            | 192.168.1.181 | 3306 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
| 20           | 192.168.1.120 | 3306 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              | zabbix  |
| 10           | 192.168.1.182 | 3306 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
| 8            | 192.168.1.180 | 3306 | ONLINE | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
4 rows in set (0.00 sec)
mysql> select * from runtime_mysql_servers;
+--------------+---------------+------+---------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname      | port | status  | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+---------------+------+---------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 7            | 192.168.1.181 | 3306 | ONLINE  | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
| 8            | 192.168.1.180 | 3306 | ONLINE  | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
| 10           | 192.168.1.182 | 3306 | ONLINE  | 1      | 0           | 1000            | 0                   | 0       | 0              |         |
| 20           | 192.168.1.120 | 3306 | SHUNNED | 1      | 0           | 1000            | 0                   | 0       | 0              | zabbix  |
+--------------+---------------+------+---------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
4 rows in set (0.00 sec)

# 可以看到新插入的数据，已经被更新到208实例中的memory和runtime环境中。
# 注意：数据差异检查是根据runtime进行检查的，只对memory和disk进行更改，并不触发同步操作。

```

#### 5.查看208实例的ProxySQL日志

```shell
2018-04-16 19:10:21 [INFO] Cluster: detected a new checksum for mysql_servers from peer 192.168.1.209:6032, version 99434, epoch 1523986027, checksum 0x9AFEA97C6D622D69 . Not syncing yet ... #检测到209实例传来的新配置文件校验值
2018-04-16 19:10:22 [INFO] Cluster: detected a peer 192.168.1.209:6032 with mysql_servers version 99434, epoch 1523986027, diff_check 3. Own version: 3, epoch: 1523876751. Proceeding with remote sync #根据传来的配置校验值，版本号，时间戳，与自己的版本进行比较，决定进行同步操作
2018-04-16 19:10:22 [INFO] Cluster: detected a peer 192.168.1.209:6032 with mysql_servers version 99434, epoch 1523986027, diff_check 4. Own version: 3, epoch: 1523876751. Proceeding with remote sync #根据传来的配置校验值，版本号，时间戳，与自己的版本进行比较，决定进行同步操作
2018-04-16 19:10:22 [INFO] Cluster: detected peer 192.168.1.209:6032 with mysql_servers version 99434, epoch 1523986027
2018-04-16 19:10:22 [INFO] Cluster: Fetching MySQL Servers from peer 192.168.1.209:6032 started. Expected checksum 0x9AFEA97C6D622D69
2018-04-16 19:10:22 [INFO] Cluster: Fetching MySQL Servers from peer 192.168.1.209:6032 completed      #从远端获取新的差异配置信息
2018-04-16 19:10:22 [INFO] Cluster: Fetching checksum for MySQL Servers from peer 192.168.1.209:6032 before proceessing 
2018-04-16 19:10:22 [INFO] Cluster: Fetching checksum for MySQL Servers from peer 192.168.1.209:6032 successful. Checksum: 0x9AFEA97C6D622D69 #获取完信息后，本地进行校验，并请求远端校验值进行比较
2018-04-16 19:10:22 [INFO] Cluster: Writing mysql_servers table #开始写mysql_servers表
2018-04-16 19:10:22 [INFO] Cluster: Writing mysql_replication_hostgroups table
2018-04-16 19:10:22 [INFO] Cluster: Loading to runtime MySQL Servers from peer 192.168.1.209:6032	#将刚刚接收并保存到memory的配置加载到runtime环境中
2018-04-16 19:10:22 [INFO] Dumping current MySQL Servers structures for hostgroup ALL
HID: 7 , address: 192.168.1.181 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
HID: 10 , address: 192.168.1.182 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
HID: 8 , address: 192.168.1.180 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
2018-04-16 19:10:22 [INFO] Dumping mysql_servers #先输出之前自己的配置信息
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
| hostgroup_id | hostname      | port | weight | status | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment | mem_pointer     |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
| 7            | 192.168.1.181 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140116687433856 |
| 8            | 192.168.1.180 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140116687434240 |
| 10           | 192.168.1.182 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140116687434112 |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
2018-04-16 19:10:22 [INFO] Dumping mysql_servers_incoming #再输出一遍更新传来的的配置信息
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname      | port | weight | status | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 7            | 192.168.1.181 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         |
| 20           | 192.168.1.120 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              | zabbix  |
| 10           | 192.168.1.182 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         |
| 8            | 192.168.1.180 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
2018-04-16 19:10:22 [INFO] New mysql_replication_hostgroups table
2018-04-16 19:10:22 [INFO] New mysql_group_replication_hostgroups table
2018-04-16 19:10:22 [INFO] Dumping current MySQL Servers structures for hostgroup ALL
HID: 7 , address: 192.168.1.181 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
HID: 20 , address: 192.168.1.120 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: zabbix
HID: 10 , address: 192.168.1.182 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
HID: 8 , address: 192.168.1.180 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
2018-04-16 19:10:22 [INFO] Dumping mysql_servers #最后输出一遍自己更新后的信息
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
| hostgroup_id | hostname      | port | weight | status | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment | mem_pointer     |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
| 7            | 192.168.1.181 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140116687433856 |
| 8            | 192.168.1.180 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140116687434240 |
| 10           | 192.168.1.182 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140116687434112 |
| 20           | 192.168.1.120 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              | zabbix  | 140116687433984 |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
2018-04-16 19:10:22 [INFO] Cluster: Saving to disk MySQL Servers from peer 192.168.1.209:6032 #经过设置的时间后，自动保存到disk环境中
2018-04-16 19:10:22 [INFO] Cluster: detected a new checksum for mysql_servers from peer 192.168.1.208:6032, version 4, epoch 1523877022, checksum 0x9AFEA97C6D622D69 . Not syncing yet ...
2018-04-16 19:10:22 [INFO] Cluster: checksum for mysql_servers from peer 192.168.1.208:6032 matches with local checksum 0x9AFEA97C6D622D69 , we won't sync.
2018-04-16 19:10:24 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-16 19:10:34 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections

```

#### 6.加入210节点：

​	210为全新的节点，我们尝试不使用conf文件启动，而使用更改global_variable的方式加入集群。

```mysql
# 更改管理端口的验证信息
mysql> update global_variables set variable_value="admin:admin;cluster_20X:123456" where variable_name ='admin-admin_credentials'; 
mysql> update global_variables set variable_value="cluster_20X" where variable_name ='admin-cluster_username';
mysql> update global_variables set variable_value="123456" where variable_name ='admin-cluster_password';
# 插入ProxySQL实例信息
mysql> insert into proxysql_servers(hostname,port) values('192.168.1.208',6032)，('192.168.1.209',6032)，('192.168.1.210',6032);
# 将更改的信息载入runtime环境
mysql >load admin variables to runtime;
mysql >load proxysql servers to runtime;
```

​	观察日志：

```shell
Standard Query Processor rev. 0.2.0902 -- Query_Processor.cpp -- Thu Feb  1 02:57:56 2018
In memory Standard Query Cache (SQC) rev. 1.2.0905 -- Query_Cache.cpp -- Thu Feb  1 02:57:56 2018
Standard MySQL Monitor (StdMyMon) rev. 1.2.0723 -- MySQL_Monitor.cpp -- Thu Feb  1 02:57:56 2018
2018-04-17 22:40:55 [INFO] Received load admin variables to runtime command
2018-04-17 22:44:19 [INFO] Received load proxysql servers to runtime command
2018-04-17 22:44:19 [INFO] Created new Cluster Node Entry for host 192.168.1.208:6032 #
2018-04-17 22:44:19 [INFO] Created new Cluster Node Entry for host 192.168.1.209:6032 #
2018-04-17 22:44:19 [INFO] Created new Cluster Node Entry for host 192.168.1.210:6032 #为其他实例开启自身入口
2018-04-17 22:44:19 [INFO] Cluster: starting thread for peer 192.168.1.210:6032 #
2018-04-17 22:44:19 [INFO] Cluster: starting thread for peer 192.168.1.209:6032 #
2018-04-17 22:44:19 [INFO] Cluster: starting thread for peer 192.168.1.208:6032 # 为其他实例连入创建线程
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_query_rules from peer 192.168.1.210:6032, version 1, epoch 1523975806, checksum 0x0000000000000000 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: checksum for mysql_query_rules from peer 192.168.1.210:6032 matches with local checksum 0x0000000000000000 , we won't sync.
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_servers from peer 192.168.1.210:6032, version 1, epoch 1523975806, checksum 0x0000000000000000 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: checksum for mysql_servers from peer 192.168.1.210:6032 matches with local checksum 0x0000000000000000 , we won't sync.
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_users from peer 192.168.1.210:6032, version 1, epoch 1523975806, checksum 0x0000000000000000 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: checksum for mysql_users from peer 192.168.1.210:6032 matches with local checksum 0x0000000000000000 , we won't sync.
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for proxysql_servers from peer 192.168.1.210:6032, version 2, epoch 1523976259, checksum 0x42904D5D92E2A8FE . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: checksum for proxysql_servers from peer 192.168.1.210:6032 matches with local checksum 0x42904D5D92E2A8FE , we won't sync.
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_query_rules from peer 192.168.1.209:6032, version 1, epoch 1523173084, checksum 0x0000000000000000 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: checksum for mysql_query_rules from peer 192.168.1.209:6032 matches with local checksum 0x0000000000000000 , we won't sync.
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_servers from peer 192.168.1.209:6032, version 99434, epoch 1523986027, checksum 0x9AFEA97C6D622D69 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_users from peer 192.168.1.209:6032, version 2, epoch 1523174009, checksum 0x8EEF803C41343944 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for proxysql_servers from peer 192.168.1.209:6032, version 1, epoch 1523173084, checksum 0xDF7CA570731DA09D . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_query_rules from peer 192.168.1.208:6032, version 1, epoch 1523876494, checksum 0x0000000000000000 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: checksum for mysql_query_rules from peer 192.168.1.208:6032 matches with local checksum 0x0000000000000000 , we won't sync.
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_servers from peer 192.168.1.208:6032, version 4, epoch 1523877022, checksum 0x9AFEA97C6D622D69 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for mysql_users from peer 192.168.1.208:6032, version 2, epoch 1523876495, checksum 0x8EEF803C41343944 . Not syncing yet ...
2018-04-17 22:44:19 [INFO] Cluster: detected a new checksum for proxysql_servers from peer 192.168.1.208:6032, version 1, epoch 1523876494, checksum 0xDF7CA570731DA09D . Not syncing yet ...
2018-04-17 22:44:21 [INFO] Cluster: detected a peer 192.168.1.209:6032 with mysql_servers version 99434, epoch 1523986027, diff_check 3. Own version: 1, epoch: 1523975806. Proceeding with remote sync
2018-04-17 22:44:21 [INFO] Cluster: detected a peer 192.168.1.209:6032 with mysql_users version 2, epoch 1523174009, diff_check 3. Own version: 1, epoch: 1523975806. Proceeding with remote sync
2018-04-17 22:44:21 [INFO] Cluster: detected a peer 192.168.1.208:6032 with mysql_servers version 4, epoch 1523877022, diff_check 3. Own version: 1, epoch: 1523975806. Proceeding with remote sync
2018-04-17 22:44:21 [INFO] Cluster: detected a peer 192.168.1.208:6032 with mysql_users version 2, epoch 1523876495, diff_check 3. Own version: 1, epoch: 1523975806. Proceeding with remote sync
2018-04-17 22:44:22 [INFO] Cluster: detected a peer 192.168.1.209:6032 with mysql_servers version 99434, epoch 1523986027, diff_check 4. Own version: 1, epoch: 1523975806. Proceeding with remote sync
2018-04-17 22:44:22 [INFO] Cluster: detected peer 192.168.1.209:6032 with mysql_servers version 99434, epoch 1523986027
2018-04-17 22:44:22 [INFO] Cluster: Fetching MySQL Servers from peer 192.168.1.209:6032 started. Expected checksum 0x9AFEA97C6D622D69
2018-04-17 22:44:22 [INFO] Cluster: Fetching MySQL Servers from peer 192.168.1.209:6032 completed
2018-04-17 22:44:22 [INFO] Cluster: Fetching checksum for MySQL Servers from peer 192.168.1.209:6032 before proceessing
2018-04-17 22:44:22 [INFO] Cluster: Fetching checksum for MySQL Servers from peer 192.168.1.209:6032 successful. Checksum: 0x9AFEA97C6D622D69
2018-04-17 22:44:22 [INFO] Cluster: Writing mysql_servers table
2018-04-17 22:44:22 [INFO] Cluster: Writing mysql_replication_hostgroups table
2018-04-17 22:44:22 [INFO] Cluster: Loading to runtime MySQL Servers from peer 192.168.1.209:6032
2018-04-17 22:44:22 [INFO] Dumping current MySQL Servers structures for hostgroup ALL
2018-04-17 22:44:22 [INFO] Dumping mysql_servers
+--------------+----------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-------------+
| hostgroup_id | hostname | port | weight | status | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment | mem_pointer |
+--------------+----------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-------------+
+--------------+----------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-------------+
2018-04-17 22:44:22 [INFO] Dumping mysql_servers_incoming
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname      | port | weight | status | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 7            | 192.168.1.181 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         |
| 20           | 192.168.1.120 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              | zabbix  |
| 10           | 192.168.1.182 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         |
| 8            | 192.168.1.180 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
2018-04-17 22:44:22 [INFO] New mysql_replication_hostgroups table
2018-04-17 22:44:22 [INFO] New mysql_group_replication_hostgroups table
2018-04-17 22:44:22 [INFO] Dumping current MySQL Servers structures for hostgroup ALL
HID: 7 , address: 192.168.1.181 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
HID: 20 , address: 192.168.1.120 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: zabbix
HID: 10 , address: 192.168.1.182 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
HID: 8 , address: 192.168.1.180 , port: 3306 , weight: 1 , status: ONLINE , max_connections: 1000 , max_replication_lag: 0 , use_ssl: 0 , max_latency_ms: 0 , comment: 
2018-04-17 22:44:22 [INFO] Dumping mysql_servers
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
| hostgroup_id | hostname      | port | weight | status | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment | mem_pointer     |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
| 7            | 192.168.1.181 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140641893576576 |
| 8            | 192.168.1.180 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140641893867776 |
| 10           | 192.168.1.182 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              |         | 140641893867648 |
| 20           | 192.168.1.120 | 3306 | 1      | 0      | 0           | 1000            | 0                   | 0       | 0              | zabbix  | 140641893867520 |
+--------------+---------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+-----------------+
2018-04-17 22:44:22 [INFO] Cluster: Saving to disk MySQL Servers from peer 192.168.1.209:6032
2018-04-17 22:44:22 [INFO] Cluster: detected a peer 192.168.1.209:6032 with mysql_users version 2, epoch 1523174009, diff_check 4. Own version: 1, epoch: 1523975806. Proceeding with remote sync
2018-04-17 22:44:22 ProxySQL_Cluster.cpp:1268:get_peer_to_sync_mysql_users(): [WARNING] Cluster: detected a peer with mysql_users epoch 1523876495 , but not enough diff_check. We won't sync from epoch 1523174009: temporarily skipping sync
2018-04-17 22:44:22 [INFO] Cluster: detected a peer 192.168.1.208:6032 with mysql_users version 2, epoch 1523876495, diff_check 4. Own version: 1, epoch: 1523975806. Proceeding with remote sync
2018-04-17 22:44:22 [INFO] Cluster: detected peer 192.168.1.208:6032 with mysql_users version 2, epoch 1523876495
2018-04-17 22:44:22 [INFO] Cluster: Fetching MySQL Users from peer 192.168.1.208:6032 started
2018-04-17 22:44:22 [INFO] Cluster: Fetching MySQL Users from peer 192.168.1.208:6032 completed
2018-04-17 22:44:22 [INFO] Cluster: Loading to runtime MySQL Users from peer 192.168.1.208:6032
2018-04-17 22:44:22 [INFO] Cluster: Saving to disk MySQL Query Rules from peer 192.168.1.208:6032
2018-04-17 22:44:23 [INFO] Cluster: detected a new checksum for mysql_servers from peer 192.168.1.210:6032, version 2, epoch 1523976262, checksum 0x9AFEA97C6D622D69 . Not syncing yet ...
2018-04-17 22:44:23 [INFO] Cluster: checksum for mysql_servers from peer 192.168.1.210:6032 matches with local checksum 0x9AFEA97C6D622D69 , we won't sync.
2018-04-17 22:44:23 [INFO] Cluster: detected a new checksum for mysql_users from peer 192.168.1.210:6032, version 2, epoch 1523976262, checksum 0x8EEF803C41343944 . Not syncing yet ...
2018-04-17 22:44:23 [INFO] Cluster: checksum for mysql_users from peer 192.168.1.210:6032 matches with local checksum 0x8EEF803C41343944 , we won't sync.
2018-04-17 22:44:48 ProxySQL_Cluster.cpp:551:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.208:6032 with proxysql_servers version 1, epoch 1523876494, diff_check 30. Own version: 2, epoch: 1523976259. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD PROXYSQL SERVERS TO RUNTIME is executed on candidate master.
2018-04-17 22:44:48 ProxySQL_Cluster.cpp:551:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.209:6032 with proxysql_servers version 1, epoch 1523173084, diff_check 30. Own version: 2, epoch: 1523976259. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD PROXYSQL SERVERS TO RUNTIME is executed on candidate master.
2018-04-17 22:44:56 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-17 22:45:06 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-17 22:45:16 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-17 22:45:18 ProxySQL_Cluster.cpp:551:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.208:6032 with proxysql_servers version 1, epoch 1523876494, diff_check 60. Own version: 2, epoch: 1523976259. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD PROXYSQL SERVERS TO RUNTIME is executed on candidate master.
2018-04-17 22:45:18 ProxySQL_Cluster.cpp:551:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.209:6032 with proxysql_servers version 1, epoch 1523173084, diff_check 60. Own version: 2, epoch: 1523976259. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD PROXYSQL SERVERS TO RUNTIME is executed on candidate master.
2018-04-17 22:45:26 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-17 22:45:36 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-17 22:45:46 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-17 22:45:48 ProxySQL_Cluster.cpp:551:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.208:6032 with proxysql_servers version 1, epoch 1523876494, diff_check 90. Own version: 2, epoch: 1523976259. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD PROXYSQL SERVERS TO RUNTIME is executed on candidate master.
2018-04-17 22:45:48 ProxySQL_Cluster.cpp:551:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.209:6032 with proxysql_servers version 1, epoch 1523173084, diff_check 90. Own version: 2, epoch: 1523976259. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD PROXYSQL SERVERS TO RUNTIME is executed on candidate master.
2018-04-17 22:45:56 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections
2018-04-17 22:46:06 MySQL_Monitor.cpp:1370:monitor_ping(): [ERROR] Server 192.168.1.120:3306 missed 3 heartbeats, shunning it and killing all the connections

```

 	大致信息即为接收并更新自己的配置文件，但有一点出现了问题，我在210上插入了三条信息（208.209，210），但在之前208和209在达成共识后，将210的proxysql_server信息踢出了表中（只有208，209，没有210）。导致从现有集群中获取的proxysql_server信息与自身的不符，且自身的信息版本（时间戳）高于集群中的信息。需要手动LOAD PROXYSQL SERVERS TO RUNTIME，然后在208或者209上重新加上210的信息上，同步到整个集群中，210实例方能排除数据冲突，真正的与208，209组成的集群保持同步。

## 疑难解答：

#### 1.新加入的节点在已经有和主节点配置不同时，主节点日志输出如下：

```shell
Sun Apr  8 10:06:37 CST 2018 ###### TRYING TO FIX MISSING WRITERS ######
Sun Apr  8 10:06:37 CST 2018 ###### TRYING TO FIX MISSING READERS ######
2018-04-08 10:06:38 ProxySQL_Cluster.cpp:488:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.209:6032 with mysql_query_rules version 1, epoch 1523107592, diff_check 60. Own version: 9, epoch: 1523005649. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD MYSQL QUERY RULES TO RUNTIME is executed on candidate master.
2018-04-08 10:06:38 ProxySQL_Cluster.cpp:509:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.209:6032 with mysql_servers version 1, epoch 1523107592, diff_check 60. Own version: 85814, epoch: 1523153195. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD MYSQL SERVERS TO RUNTIME is executed on candidate master.
2018-04-08 10:06:38 ProxySQL_Cluster.cpp:530:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.209:6032 with mysql_users version 1, epoch 1523107592, diff_check 60. Own version: 9, epoch: 1523110710. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD MYSQL USERS TO RUNTIME is executed on candidate master.
2018-04-08 10:06:38 ProxySQL_Cluster.cpp:551:set_checksums(): [WARNING] Cluster: detected a peer 192.168.1.209:6032 with proxysql_servers version 1, epoch 1523107592, diff_check 60. Own version: 3, epoch: 1523077120. diff_check is increasing, but version 1 doesn't allow sync. This message will be repeated every 30 checks until LOAD PROXYSQL SERVERS TO RUNTIME is executed on candidate master.
Sun Apr  8 10:06:40 CST 2018 ###### TRYING TO FIX MISSING WRITERS ######
Sun Apr  8 10:06:40 CST 2018 ###### TRYING TO FIX MISSING READERS ######

```

这种情况要求我们强制覆盖一端的数据。不建议手动在控制台进行load或者save等操作进行覆盖，最好将一个实例的配置手动更新至最全的版本，然后删除另一个ProxySQL的proxysql.db配置文件，并在conf文件中写定集群信息。启动后，缺失proxysql.db的实例，会自动下载集群中的配置信息，并生成新的proxysql.db。

#### 2.因为密码间隔用的‘，’导致日志中输出无法登录的情况

```shell
2018-04-08 09:40:10 ProxySQL_Cluster.cpp:180:ProxySQL_Cluster_Monitor_thread(): [WARNING] Cluster: unable to connect to peer 192.168.1.208:6032 . Error: ProxySQL Error: Access denied for user 'cluster'@'' (using password: YES)
2018-04-08 09:40:11 ProxySQL_Cluster.cpp:180:ProxySQL_Cluster_Monitor_thread(): [WARNING] Cluster: unable to connect to peer 192.168.1.209:6032 . Error: ProxySQL Error: Access denied for user 'cluster'@'' (using password: YES)
2018-04-08 09:40:11 ProxySQL_Cluster.cpp:180:ProxySQL_Cluster_Monitor_thread(): [WARNING] Cluster: unable to connect to peer 192.168.1.208:6032 . Error: ProxySQL Error: Access denied for user 'cluster'@'' (using password: YES)
ERROR 1045 (28000): ProxySQL Error: Access denied for user 'admin'@'' (using password: YES)
ERROR 1045 (28000): ProxySQL Error: Access denied for user 'admin'@'' (using password: YES)
ERROR 1045 (28000): ProxySQL Error: Access denied for user 'admin'@'' (using password: YES)
ERROR 1045 (28000): ProxySQL Error: Access denied for user 'admin'@'' (using password: YES)

```

将`admin_credentials="admin:admin，cluster_20X:123456"`中间隔两个账户和密码对的‘，’改成’；‘

