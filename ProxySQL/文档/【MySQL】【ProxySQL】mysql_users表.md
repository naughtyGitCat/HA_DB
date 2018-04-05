# 【MySQL】【ProxySQL】浅析mysql_users表

[TOC]



## 1.表定义与字段说明

### 表的DDL定义:

```mysql
CREATE TABLE mysql_users (
    username VARCHAR NOT NULL,   #用户名
    password VARCHAR,			#密码
    active INT CHECK (active IN (0,1)) NOT NULL DEFAULT 1,    #是否启用
    use_ssl INT CHECK (use_ssl IN (0,1)) NOT NULL DEFAULT 0,  #是否使用SSL连接
    default_hostgroup INT NOT NULL DEFAULT 0,				 #默认查询路由组
    default_schema VARCHAR,								   #默认数据库
    schema_locked INT CHECK (schema_locked IN (0,1)) NOT NULL DEFAULT 0,  #限定用户在默认数据库中
    transaction_persistent INT CHECK (transaction_persistent IN (0,1)) NOT NULL DEFAULT 1,           #事务路由分配持久性，同一个事务的语句不会被分配到不同的组
    fast_forward INT CHECK (fast_forward IN (0,1)) NOT NULL DEFAULT 0,    #快速回收空闲线程
    backend INT CHECK (backend IN (0,1)) NOT NULL DEFAULT 1,			 #是否为后端数据库的账户
    frontend INT CHECK (frontend IN (0,1)) NOT NULL DEFAULT 1,			                           #是否为ProxySQL本身的账户（通过6033端口接入ProxySQL）
    max_connections INT CHECK (max_connections >=0) NOT NULL DEFAULT 10000,                         #该用户对ProxysSQL最大连接数
    PRIMARY KEY (username, backend),  #主键，后端账户用户名唯一
    UNIQUE (username, frontend))	  #唯一性约束，前端中用户名唯一
```

### 参数的特别说明：

#### 	transaction_persistent：

​		对于读写分离特别重要，保证了同一个事务中所有的语句都会路由到同一组示例，防止出现同一个事务中，上下文数据不一致的情况。例如，在不开启这个属性的情况下，

```mysql
begin;
insert into t1 values(xxxyyyzzz);
select * from t1;   
commit;
```

​	很有可能	插入语句被路由到写组，而查询语句被路由到读组（假设写组的示例没有重复出现在读组中)。由于在传统复制情况下（没有开启after sync），事务只有被提交后才会被传输到从库上，就造成一个事务中前后不一致，自己读不到自己的修改的数据的问题。

#### fast_forward：

看下源码（lib\MySQL_Thread.cpp）：

```c++
				if (myds->myds_type==MYDS_BACKEND && myds->sess->status!=FAST_FORWARD) {
					if (mypolls.fds[n].revents) {
					// this part of the code fixes an important bug
					// if a connection in use but idle (ex: running a transaction)
					// get data, immediately destroy the session
					//
					// this can happen, for example, with a low wait_timeout and running transaction
						if (myds->sess->status==WAITING_CLIENT_DATA) {
							if (myds->myconn->async_state_machine==ASYNC_IDLE) {
								proxy_warning("Detected broken idle connection on %s:%d\n", myds->myconn->parent->address, myds->myconn->parent->port);
								myds->destroy_MySQL_Connection_From_Pool(false);
								myds->sess->set_unhealthy();
								return false;
					return true;
				}

				..............................
					} else {
						// if this is a backend with fast_forward, set unhealthy
						// if this is a backend without fast_forward, do not set unhealthy: it will be handled by client library
						if (myds->sess->session_fast_forward) { // if fast forward
							if (myds->myds_type==MYDS_BACKEND) { // and backend
								myds->sess->set_unhealthy(); // set unhealthy
							}
						}
					}
				}
	return true;
}
```

​	例如在开启fast_forward后，一些处于连接状态，但空闲的线程，会被ProxySQL标记为不健康的线程，会被立即结束掉(可能处于节省线程资源的考虑)。这个参数默认是不开启的。

#### 	backend 与 frontend：

​		以后的版本中可能有前后端账号分离的操作。

## 2.用户表维护

让我们先看下和配置有关的库和表

```mysql
mysql> show databases;
+-----+---------------+-------------------------------------+
| seq | name          | file                                |
+-----+---------------+-------------------------------------+
| 0   | main          |                                     |  #常用库
| 2   | disk          | /var/lib/proxysql/proxysql.db       |  #配置存档库
| 3   | stats         |                                     |  #统计信息库
| 4   | monitor       |                                     |  #监控信息库
| 5   | stats_history | /var/lib/proxysql/proxysql_stats.db |  #统计信息历史库
+-----+---------------+-------------------------------------+
```

ProxySQL自身共有5个 库，分别为3个保存在内存中的库，和三个保存在磁盘的SQLite库。

我们平时通过6032管理端口登入后，默认就是main库，所有的配置更改都必须在这个库中进行，disk存档库不会直接受到影响。接下来看下

#### main库中的表：

```mysql
mysql> show tables from main;
+--------------------------------------------+
| tables                                     |
+--------------------------------------------+
| global_variables                           |	#ProxySQL的基本配置参数，类似与MySQL
| mysql_collations                           |	#配置对MySQL字符集的支持
| mysql_group_replication_hostgroups         |	#MGR相关的表，用于实例的读写组自动分配
| mysql_query_rules                          |	#路由表
| mysql_replication_hostgroups               |	#主从复制相关的表，用于实例的读写组自动分配
| mysql_servers                              |	#存储MySQL实例的信息
| mysql_users                                |	#现阶段存储MySQL用户，当然以后有前后端账号分离的设想
| proxysql_servers                           |	#存储ProxySQL的信息，用于ProxySQL Cluster同步
| runtime_checksums_values                   |	#运行环境的存储校验值
| runtime_global_variables                   |	#
| runtime_mysql_group_replication_hostgroups |	#
| runtime_mysql_query_rules                  |	#
| runtime_mysql_replication_hostgroups       |	#与上面对应，但是运行环境正在使用的配置
| runtime_mysql_servers                      |	#
| runtime_mysql_users                        |	#
| runtime_proxysql_servers                   |	#
| runtime_scheduler                          |	#
| scheduler                                  |	#定时任务表
+--------------------------------------------+
```

#### disk库中的表：

```mysql
mysql> show tables from disk;
+------------------------------------+
| tables                             |
+------------------------------------+
| global_variables                   |#
| mysql_collations                   |#
| mysql_group_replication_hostgroups |#
| mysql_query_rules                  |#
| mysql_replication_hostgroups       |#基本与上面的表相对应
| mysql_replication_hostgroups_v122  |#但是多了两个老版本的表
| mysql_servers                      |#
| mysql_servers_v122                 |#
| mysql_users                        |#
| proxysql_servers                   |#
| scheduler                          |#
+------------------------------------+
```

不难观察出，9张配置表在不同的情况下出现了三次，分别代表：当前内存中的配置信息，当前正在使用的配置信息，当前磁盘文件中的配置信息。

这就要求我们在配置时按需对三个地方的配置进行分别配置。

#### 如：插入一个新的用户

```mysql
insert into mysql_users(username,password,active,default_hostgroup) values ('predecessor_beast','114514',1,69)
```

这条记录只会出现在`main`库的`mysql_users` 表中，而运行环境和磁盘上均未发生变化。

#### 从内存加载到运行环境中

```mysql
LOAD MYSQL USERS TO RUNTIME;
```

#### 从内存保存到磁盘文件中

```
SAVE MYSQL USERS TO DISK;
```

#### 从运行环境下载到内存中

```mysql
SAVE MYSQL USERS TO MEMORY;
```

#### 从磁盘文件加载到内存中

```mysql
LOAD MYSQL USERS TO MEMORY;
```

#### 配置管理简图

![](https://raw.githubusercontent.com/naughtyGitCat/HA_DB/master/ProxySQL/pic/ProxySQL_conf_manage.png)

从上到下是`SAVE XXX TO XXX;`

从下到上是`LOAD XXX FROM XXX;`

## 3.明文密码的加密存储

ProxySQL支持明文和哈希加密两种密码保存方式，默认的方式一般都是明文。如下图：

```mysql
mysql> SELECT username,password FROM mysql_users;
+------------------+-------------------------------------------+
| username         | password                                  |
+------------------+-------------------------------------------+
| proxysql_web     | 123456                                    |
| mgr33061         | 123456                                    |
| mgr33061_backend | 123456                                    |
+------------------+-------------------------------------------+
```

可以通过两种办法将明文密码加密，

#### 1.在输入时加密

由于ProxySQL提供的服务端没有加密函数，需要在MySQL中进行加密后，然后替换掉插入语句中的明文密码。

```mysql
# 原明文插入语句如下：
# ProxySQL
ProxySQL> insert into mysql_users(username,password,active,default_hostgroup) values ('predecessor_beast','114514',1,69);
# 先到MySQL实例中进行加密
# MySQL
root@localhost 16:53:  [(none)]> select PASSWORD('114514');
+-------------------------------------------+
| PASSWORD('114514')                        |
+-------------------------------------------+
| *D9050F2D99C3DDD8138912B7BDF8F4BACBE3A8E7 |
+-------------------------------------------+
1 row in set, 1 warning (0.00 sec)
# 替换插入语句中的明文密码
ProxySQL> insert into mysql_users(username,password,active,default_hostgroup) values ('predecessor_beast','114514',1,69);
```

#### 2.使用`admin-hash_passwords`特性

在`global_variable`中开启admin-hash_passwords后，通过将含有明文密码的mysql_users表加载到运行环境中，这时表中的所有明文密码都会被哈希加密后的密码替换，然后再save到memory最后save到disk即可永久加密保存。

```mysql
ProxySQL> select * from global_variables where variable_name like "%passwords%";
+----------------------+----------------+
| variable_name        | variable_value |
+----------------------+----------------+
| admin-hash_passwords | true           |   #确认开启admin-hash_passwords特性
+----------------------+----------------+
1 row in set (0.00 sec)

# 插入新的用户（明文密码）
ProxySQL> insert into mysql_users(username,password,active,default_hostgroup) values ('predecessor_beast','114514',1,69);
Query OK, 1 row affected (0.00 sec)

# 查看明文密码的用户表
ProxySQL> SELECT username,password FROM mysql_users;
+------------------+-------------------------------------------+
| username         | password                                  |
+------------------+-------------------------------------------+
| proxysql         | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 |  #之前已经加密过了
| proxysql_web     | 123456                                    |  #未加密
| mgr33061         | 123456                                    |  #未加密
| mgr33061_backend | 123456                                    |  #未加密
| predecessor_beast| 114514									|  #新插入的未加密用户
+------------------+-------------------------------------------+

# 查看运行环境中的用户表
ProxySQL> select username,password from  runtime_mysql_users;
+------------------+-------------------------------------------+
| username         | password                                  |
+------------------+-------------------------------------------+
| proxysql         | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 | #由于前后端账户的原因
| proxysql_web     | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 | #原先单个账户成对出现
| mgr33061         | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 |
| proxysql         | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 | #运行环境中的都是已经加密的
| proxysql_web     | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 |
| mgr33061_backend | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 | #不存在新用户
+------------------+-------------------------------------------+

# 加载到运行环境中
mysql> load mysql users to runtime;
Query OK, 0 rows affected (0.00 sec)

# 从运行环境中下载出来
mysql> save mysql users to memory;
Query OK, 0 rows affected (0.00 sec)
mysql> save mysql users to disk;
Query OK, 0 rows affected (0.00 sec)

# 检查下载出来的用户表
mysql> SELECT username,password FROM mysql_users;
+-------------------+-------------------------------------------+
| username          | password                                  |
+-------------------+-------------------------------------------+
| mgr33061          | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 |
| proxysql          | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 |
| proxysql_web      | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 |
| mgr33061_backend  | *6BB4837EB74329105EE4568DDA7DC67ED2CA2AD9 |
| predecessor_beast | *D9050F2D99C3DDD8138912B7BDF8F4BACBE3A8E7 |
+-------------------+-------------------------------------------+
# 所有明文密码已经被加密，已经加密过的，不会再次加密
```