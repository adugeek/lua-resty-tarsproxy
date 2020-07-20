local proxyCache = ngx.shared.tarsProxyCache
local cjson = require("cjson")
local math = require("math")
local ngxLog = ngx.log
local roudonValue = 0

local _M = {
    _VERSION = '0.0.1'
}

function _M.setUpstream(self, servant, upstream)
    proxyCache:set(servant .. "_address", upstream)
end

function _M.deleteUpstream(self, servant)
    proxyCache:delete(servant .. "_address")
end

function _M.getUpstream(self, servant)
    return proxyCache:get(servant .. "_address")
end

function _M.getAddress(self, servant)
    local address = proxyCache:get(servant .. "_address")
    if not address then
        ngxLog(ngx.ERR, "cache nil ", servant)
        return nil
    end
    local t = cjson.decode(address)
    if t and #t ~= 0 then
        local which = 0
        local errorTimesKey = ""
        local errorTimes = 0;
        for i = roudonValue, roudonValue + #t - 1 do
            which = roudonValue % #t + 1
            address = t[which]
            errorTimesKey = address .. "_error"
            errorTimes = proxyCache:get(errorTimesKey)
            if not errorTimes then
                roudonValue = i + 1
                return address
            end
        end
    end
    return nil
end

function _M.reportAddressError(self, address)
    local errorTimesKey = address .. "_error"
    local errorTimes = proxyCache:get(errorTimesKey)
    if not errorTimes then
        proxyCache:incr(errorTimesKey, 1, 0, 1); -- 首次报错,1秒钟后重置
        -- todo 添加定时任务,每间隔一定时间,重连此 address
        return
    end

    -- 以下逻辑由定时重试任务触发
    if errorTimes <= 1 then
        proxyCache:incr(errorTimesKey, 1, 0, 2); -- 第二次报错,2秒钟后重置
    else
        -- 报错操作两次,重置时间设置为 min(errorTimes*1, 10)
        proxyCache:incr(errorTimesKey, 1, 0, math.min(errorTimes * 1, 8));
    end
end

return _M
