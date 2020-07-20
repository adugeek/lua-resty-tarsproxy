local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local table = table
local setmetatable = setmetatable
local ngxLog = ngx.log
local ngxRegex = ngx.re
local ngxReqSocket = ngx.req.socket

local upstream = require("tars.upstream")
local cjson = require("cjson")

local Response200 = 'HTTP/1.1 200 OK\r\n\r\n'
local Response201 = 'HTTP/1.1 201 Created\r\n\r\n'
local Response400 = 'HTTP/1.1 400 Bad Request\r\n\r\n'

local function handleSetUpstream(params)
    for servantName, address in pairs(params) do
        local addressStr = cjson.encode(address)
        upstream:setUpstream(servantName, addressStr)
    end
end

local function handleDeleteUpstream(params)
    for i, _ in ipairs(params) do
        upstream:deleteUpstream(params[i])
    end
end

local function handleGetUpstream(params)
    local t = {}
    for i, v in ipairs(params) do
        local address = upstream:getUpstream(v)
        if not address then
            t[v] = {}
        else
            t[v] = cjson.decode(address)
        end
    end
    return cjson.encode(t)
end

local _M = {
    _VERSION = '0.0.1',
}

local mt = { __index = _M }

function _M.new(self)
    local downSocket, err = ngxReqSocket(true)
    if not downSocket then
        return nil, err
    end
    return setmetatable({
        downSocket = downSocket
    }, mt)
end

local contentLengthRex = [[Content-Length: (\d+)]]

function _M.run(self)
    local downSocket = self.downSocket
    local data, err = downSocket:receive('*l')
    if data ~= "POST /admin HTTP/1.1" then
        return
    end
    local bodyLength
    while true do
        local data, err = downSocket:receive('*l')
        if not data then
            if err then
                downSocket:send("failed to read the data stream: ")
                break
            end
        end
        if data == "" then
            break
        end
        local m, err = ngxRegex.match(data, contentLengthRex, "jis")
        if m then
            bodyLength = tonumber(m[1])
        end
    end
    if not bodyLength then
        return
    end

    local body = downSocket:receive(bodyLength)
    --[[
    body 预期格式如下,后续会引入  api7/jsonschema 做严格校验

    setUpstream
    {
      "jsonrpc": "2.0",
      "method": "setUpstream",
      "id": "1594974115190",
      "params": {
        "tars.tarsnotify.NotifyObj": [
          "172.16.8.95:3325",
          "172.16.8.95:3327",
          "172.16.8.95:3328"
        ],
        "Test.HelloServer.HelloObj": [
          "172.16.8.95:3325",
          "172.16.8.95:3327",
          "172.16.8.95:3328"
        ]
      }
    },

    deleteUpstream
    {
      "jsonrpc": "2.0",
      "method": "deleteUpstream",
      "id": "1594974115190",
      "params": [
        "tars.tarsnotify.NotifyObj",
        "Test.HelloServer.HelloObj"
      ]
    }

     getUpstream
    {
      "jsonrpc": "2.0",
      "method": "getUpstream",
      "id": "1594974115190",
      "params": [
        "tars.tarsnotify.NotifyObj",
        "Test.HelloServer.HelloObj"
      ]
    }

    --]]
    if not body then
        return
    end

    --todo 格式校验以及数据去重
    local t = cjson.decode(body)
    if t.method == "setUpstream" then
        handleSetUpstream(t.params)
        downSocket:send(Response200)
    elseif t.method == "deleteUpstream" then
        handleDeleteUpstream(t.params)
        downSocket:send(Response200)
    elseif t.method == "getUpstream" then
        local address = handleGetUpstream(t.params)
        local res = {
            "HTTP/1.1 200 OK\r\n",
            "Content-Length: ", tostring(#address), "\r\n",
            "\r\n",
            address
        }
        downSocket:send(table.concat(res, ''))
    else
        downSocket:send(Response400)
    end
end

return _M
