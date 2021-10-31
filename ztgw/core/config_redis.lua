local setmetatable = setmetatable
local require      = require
local xpcall       = xpcall
local pcall        = pcall
local tostring     = tostring
local ngx          = ngx
local ngx_sleep    = ngx.sleep
local ngx_timer_at = ngx.timer.at
local ngx_time     = ngx.time
local exiting      = ngx.worker.exiting

local json = require("cjson")
local redis = require("resty.redis")

local _M = { version= 0.1 }

local mt = {
    __index = _M,
    __tostring = function(self)
        return " redis key: " .. self.key
    end
}

local modules = {}

function _M.get_redis_cli(config)
    local redis_cli = redis:new()
    local timeout = config.timeout or 5000
    redis_cli:set_timeout(timeout)

    local ok, err = redis_cli:connect(config.host, config.port)
    if not ok then
        return nil, err
    end

    if config.password then
        local count, err = redis_cli:get_reused_times()
        if count == 0 then
            local ok, err = redis_cli:auth(config.password)
            if not ok then
                return nil, err
            end
        elseif err then
            return nil, err
        end
    end

    if config.db then
        redis_cli:select(config.db)
    end

    return redis_cli, nil
end

local function sync_data(self)
    local redis_config = self.config.redis
    local redis_cli, err = _M.get_redis_cli(redis_config)
    if err ~= nil then
        ngx.log(ngx.ERR, "get redis failed:" .. err)
        return err
    end

    local res, err = redis_cli:get(self.key)
    if not res then
        ngx.log(ngx.ERR, "failed to get:" .. key .." from redis")
        return err
    end

    if res == ngx.null then
        ngx.log(ngx.ERR, "get invalid data by key:", self.key)
        return
    end

    local timeout = redis_config.timeout or 5000
    local pool_num = redis_config.size or 100
    local ok, err = redis_cli:set_keepalive(timeout, pool_num)
    if not ok then
        return nil, err
    end

    if self.config.secret then
        --ngx.log(ngx.ERR, "secret:" .. self.config.secret)
    end

    local data = json.decode(res)
    if data.timestamp == self.timestamp then
        return
    end

    if self.options.validate then
        local value, err = self.options.validate(data.data)
        if err ~= nil then
            ngx.log(ngx.ERR, "validate key:" .. self.key .." failed")
            return
        end

        self.value = value
    else
        ngx.log(ngx.ERR, "module: ", self.module .. " not have validate function")
    end
end

local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    local i = 0
    while not exiting() and self.running and i <= 32 do
        i = i + 1
        local ok, ok2, err = pcall(sync_data, self)
        if not ok then
            err = ok2
            ngx.log(ngx.ERR, "failed to fetch data from redis: ", err, ", ", tostring(self))
            ngx_sleep(3)
            break

        elseif not ok2 and err then
            if err ~= "timeout" and err ~= "Key not found"
                    and self.last_err ~= err then
                ngx.log(ngx.ERR, "failed to fetch data from etcd: ", err, ", ", tostring(self))
            end

            ngx_sleep(0.5)

        elseif not ok2 then
            ngx_sleep(0.05)
        end

        ngx.sleep(self.interval)
    end

    if not exiting() and self.running then
        ngx_timer_at(0, _automatic_fetch, self)
    end
end

function _M.new(name, config, options)
    local automatic = options and options.automatic
    local validate = options and options.validate
    local interval = options and options.interval
    local module = setmetatable({
        name = name,
        key = name,
        config = config,
        options = options,
        automatic = automatic,
        interval = interval,
        validate = validate,
        timestamp = nil,
        running = true,
        value = nil
    }, mt)

    if automatic then
        ngx_timer_at(0, _automatic_fetch, module)
    end

    return module, nil
end

return _M
