local setmetatable = setmetatable

local sub = string.sub
local byte = string.byte
local format = string.format

local bit = require("bit")
local lshift = bit.lshift

local ngx = ngx
local ngxLog = ngx.log
local ngxRegexMatch = ngx.re.match
local ngxReqSocket = ngx.req.socket
local ngxTcpSocket = ngx.socket.tcp
local ngxThreadspawn = ngx.thread.spawn
local ngxThreadwait = ngx.thread.wait

local upstream = require("tars.upstream")
local ffi = require "ffi"
local parser = ffi.load('parser')

ffi.cdef [[
    int parser(const char **servantName, size_t *servantNameLen, const char *buff, size_t size)
]]

local addressParen = [[([a-zA-Z0-9.]+):([1-9][0-9]+)]]

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

local function transUp(upScoket, downSocket)
    while true do
        local data = upScoket:receiveany(2 * 1024) -- 一次最多转发2k,够用了
        if not data then
            break
        end
        local _, err = downSocket:send(data)
        if err then
            break
        end
    end
end

local function transDown(downSocket, upScoket)
    while true do
        local requestLenTag, err = downSocket:receive(4)
        if err then
            break
        end
        local requestLen = lshift(byte(requestLenTag, 1), 24) + lshift(byte(requestLenTag, 2), 16) + lshift(byte(requestLenTag, 3), 8) + byte(requestLenTag, 4)
        local requestData, err = downSocket:receive(requestLen - 4)
        if err then
            break
        end
        local _, err = upScoket:send({ requestLenTag, requestData })
        if err then
            break
        end
    end
end

function _M.run(self)
    -- 处理流程 ---
    --0. 认证,需要时再加吧
    --1. 读取首次请求数据
    --2. 解析出目标Obj
    --3. todo 判断 clientIp 是否在 目标Obj 黑名单  (-- 全局黑名单计划放在 filter_by_lua 里面处理)
    --4. todo 判断是否限速 -> {目标Obj 总限速 和 针对 clientIp 的限速}
    --5. 获取后端地址  --附加了round-robin 和 熔断策略
    --6. 连接到目标地址,生成 upSocket
    --7  发送首次请求数据
    --8. 双向透明转发 downSocket, upSocket. 任意一端 socket 断开链接,或数据读取错误则退出   --透明转发不方便做慢速监控,但吞吐速度可能会快一丢丢
    --9. 转发结束后,如果 upSocket 还有效,放入链接池备用

    local downSocket = self.downSocket

    local requestLenTag, err = downSocket:receive(4)
    if err then
        return
    end

    local requestLen = lshift(byte(requestLenTag, 1), 24) + lshift(byte(requestLenTag, 2), 16) + lshift(byte(requestLenTag, 3), 8) + byte(requestLenTag, 4)
    local requestData, err = downSocket:receive(requestLen - 4)
    if err then
        return
    end

    local servantName = ffi.new('const char * [1]')
    local servantNameLen = ffi.new('size_t [1]')

    local res = parser.parser(servantName, servantNameLen, requestData, #requestData)
    if res ~= 0 then
        return
    end

    local servantName = ffi.string(servantName[0], servantNameLen[0])
    ngxLog(ngx.ERR, "servantName: ", servantName)

    local upAddress = upstream:getAddress(servantName)
    if not upAddress then
        return
    end

    local match, err = ngxRegexMatch(upAddress, addressParen)
    if err then
        return
    end

    local upSocket = ngxTcpSocket()
    local ok, err = upSocket:connect(match[1], tonumber(match[2]))
    if not ok then
        upstream:reportAddressError(upAddress)
        return
    end

    local _, err = upSocket:send({requestLenTag, requestData})
    if err then
        return
    end

    local co_up = ngxThreadspawn(transUp, upSocket, downSocket)
    local co_down = ngxThreadspawn(transDown,downSocket, upSocket)
    ngxThreadwait(co_up, co_down)

    -- make sure buffers are clean
    ngx.flush(true)

    if upSocket.shutdown then
        upSocket:shutdown("send")
    end
    if upSocket.close ~= nil then
        upSocket:setkeepalive(6000, 3) -- 链接池不宜超时设置不宜过长,链接数也不宜过大
    end

    if downSocket.shutdown then
        downSocket:shutdown("send")
    end
    if downSocket.close ~= nil then
        downSocket:close()
    end
end

return _M
