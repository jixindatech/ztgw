local setmetatable = setmetatable
local require      = require
local xpcall       = xpcall
local pcall        = pcall
local ipairs       = ipairs
local new_tab      = table.new
local tab_insert   = table.insert
local type         = type
local tostring     = tostring
local sub_str      = string.sub
local ngx          = ngx
local ngx_sleep    = ngx.sleep
local ngx_timer_at = ngx.timer.at
local ngx_time     = ngx.time
local exiting      = ngx.worker.exiting
local ztgw_schema       = require("ztgw.schema")

local cjson = require("cjson.safe")
local redis = require("resty.redis")

local _M = { version= 0.1 }

local mt = {
    __index = _M,
    __tostring = function(self)
        return " redis key: " .. self.key
    end
}

local function short_key(self, str)
    return sub_str(str, #self.key + 2)
end

local function get_redis_cli(config)
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
    local redis_cli, err = get_redis_cli(redis_config)
    if err ~= nil then
        ngx.log(ngx.ERR, "get redis failed:" .. err)
        return err
    end

    local res, err = redis_cli:get(self.key)
    if not res then
        ngx.log(ngx.ERR, "failed to get:" .. self.key .." from redis")
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

    local data = cjson.decode(res)
    if data.timestamp == self.timestamp then
        return
    end

    if self.values then
        for _, item in ipairs(self.values) do
            if item then
                if item.clean_handlers then
                    for _, clean_handler in ipairs(item.clean_handlers) do
                        clean_handler(item)
                    end
                    item.clean_handlers = nil
                end
            end
        end
        self.values = nil
    end

    local items = data.values or {}
    self.values = new_tab(#items, 0)
    self.values_hash = new_tab(0, #items)

    local changed = false
    for i, item in ipairs(items) do
        local id = tostring(i)
        local key = item.id or "arr_" .. i

        local data_valid = true
        if type(item) ~= "table" then
            data_valid = false
            ngx.log(ngx.ERR, "type:" .. type(item))
            --ngx.log(ngx.ERR, "invalid item data of [", self.key .. "/" .. key, "], val: ", cjson.encode(item), ", it shoud be a object")
        end

        local conf_item = {value = item, modifiedIndex = data.timestamp, key = "/" .. self.key .. "/" .. key}

        if data_valid and self.schema then
            data_valid, err = ztgw_schema.check(self.schema, item)
            if not data_valid then
                ngx.log(ngx.ERR, cjson.encode(item))
                ngx.log(ngx.ERR, "failed to check item data of [", self.key, "] err:", err)
                --ngx.log(ngx.ERR, "failed to check item data of [", self.key, "] err:", err, " ,val: ", cjson.encode(item))
            end
        end

        if data_valid then
            tab_insert(self.values, conf_item)
            local item_id = conf_item.value.id or self.key .. "#" .. id
            item_id = tostring(item_id)
            self.values_hash[item_id] = #self.values
            conf_item.value.id = item_id
            conf_item.value.clean_handlers = {}
            --ngx.log(ngx.ERR, cjson.encode(conf_item))
        end
    end

    if self.filter then
        self.filter(items)
    end

    if changed then
        self.timestamp = data.timestamp or ngx_time()
        self.conf_version = self.conf_version + 1
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

function _M.get(self, key)
    if not self.values_hash then
        return
    end

    local arr_idx = self.values_hash[tostring(key)]
    if not arr_idx then
        return nil
    end

    return self.values[arr_idx]
end

function _M.new(name, config, options)
    local automatic = options and options.automatic
    local interval = options and options.interval
    local filter_fun = options and options.filter
    local schema = options and options.schema

    local module = setmetatable({
        name = name,
        key = name,
        config = config,
        options = options,
        automatic = automatic,
        interval = interval,
        timestamp = nil,
        running = true,
        conf_version = nil,
        value = nil,
        schema = schema,
        filter = filter_fun,
    }, mt)

    if automatic then
        ngx_timer_at(0, _automatic_fetch, module)
    end

    return module, nil
end

return _M
