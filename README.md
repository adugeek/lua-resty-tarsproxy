
描述
===========

lua-resty-tarsproxy - 基于 openrestry stream 的 tars 网关代理.

预期是作为一个 tars 集群的网关统一接收 tars 请求,然后转发到后端.

lua-resty-tarsproxy 需要两个端口进行工作 proxy 和 admin 

proxy 用于代理请求

admin 用于管理 upstream ,以及后期的其他控制功能. 为便于使用其他第三方组件, admin接口使用 http 协议

开发状态
========

此项目还处于早期开发阶段


使用步骤
========

1. 安装 openrestry ,建议使用当前最新版 (1.17.8)
 
2. 编译 libparser.so,并安装到 openrestry lib 路径

3. 将 tars 文件夹到 openresty/lualib/resty 文件夹

4. 编辑 openrestry/nginx/nginx.conf 文件,示例配置如下:

    ```
    worker_processes  1;

    events {
        worker_connections  1024;
    }

    stream {
        
        lua_shared_dict tarsProxyCache 10m;
        
        lua_code_cache on;
        
        server {
            listen 9090;
            content_by_lua_block {
                local proxy = require("tars.proxy")
                local p = proxy:new()
                p:run()
            }
        }
        
        server {
            listen 9091;
            content_by_lua_block {
                local admin = require("tars.admin")
                local p = admin:new()
                p:run()
            }
        }
    }

    ```
5. 启动 openrestry 

正常情况下, lua-resty-tarsproxy 已经能够正常工作, 但是没有配置 upstream ,只能接受请求,无法响应结果.需要提交 upstream 信息


控制 upstream
========

+ 设置 Obj 与后端

    POST /admin
    ```json
    {
        "jsonrpc": "2.0",
        "method": "setUpstream",
        "id": "1594974115190",
        "params": {
            "tars.tarsregistry.QueryObj":[
                "10.217.3.178:17890",
                "10.217.1.212:17890"
            ]
        }
    }    
    ```
+ 删除 upstream

    POST /admin
    ```json
    {
        "jsonrpc": "2.0",
        "method": "deleteUpstream",
        "id": "1594974115190",
        "params": [
            "tars.tarsregistry.QueryObj"
        ]
    }    
    ```

+ 查看 upstream
    
    POST /admin
    
    ```json
    {
        "jsonrpc": "2.0",
        "method": "getUpstream",
        "id": "1594974115190",
        "params": [
            "tars.tarsregistry.QueryObj"
        ]
    }    
    ```

    Response

    ```json
    {
        "tars.tarsregistry.QueryObj":[
            "10.217.3.178:17890",
            "10.217.1.212:17890"
        ]       
    }    
    ```

验证
====
```c++
#include "servant/Application.h"
#include <servant/QueryF.h>
#include <iostream>

using namespace std;
using namespace tars;

Communicator *_comm;

int main(int argc, char *argv[]) {
    _comm = new Communicator();
    auto servant = "tars.tarsregistry.QueryObj@tcp -h 172.16.8.95 -p 9090 -t 60000";
    auto servantPrx = _comm->stringToProxy<QueryFPrx>(servant);
    auto targetObj = "tars.tarsnotify.NotifyObj";
    auto v = servantPrx->findObjectById(targetObj);
    for (const auto &item: v) {
        std::cout << item.host << ":" << item.port << std::endl;
    }
    return 0;
} 
```

ToDo
====
+ 完善现有功能,完成格式校验和数据校验
+ 完善黑名单,熔断,限速逻辑
+ 增加 http 代理功能,兼容 TarsGateWay https://github.com/TarsCloud/TarsGateway


参考
========
* the ngx_stream_lua_module: https://github.com/openresty/stream-lua-nginx-module