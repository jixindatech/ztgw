local type = type
local require = require
local ngx = ngx
local json = require("cjson.safe")
local lrucache = require("resty.lrucache")
local config = require("ztgw.core.config")
local request = require("ztgw.core.request")
local redis = require("ztgw.core.config_redis")
local aes   = require("ztgw.utils.aes")

local ngx_time = ngx.time
local is_internal = ngx.req.is_internal
local get_method = ngx.req.get_method
local read_body = ngx.req.read_body
local get_body =  ngx.req.get_body_data

local _M = { version = "0.1"}

local module_name = "gw"
local module = {}
local header_token = "ZTGW-Token"
local entry_num = 100

local forbidden_code = 401
local ttl = 60

function _M.init_worker()
    local options = {
        key = module_name,
        automatic = false,
    }

    local err
    module, err = config.new(module_name, options)
    if err ~= nil then
        return err
    end

    if module.config.secret == nil then
        return "token_secret is missing"
    end

    if #module.config.secret ~= 32 then
        return "invalid token_secret length, length of token_secret must be 32"
    end

    local cache, err = lrucache.new(entry_num)
    if err ~= nil then
        return err
    end

    module.cache = cache

    return nil
end

local function parse_token(secret, token)
    local email, err = aes.decrypt(secret, token)
    if err ~= nil then
        return nil, err
    end

    return email, nil
end

local function get_email_info(email)
    local redis_config = module.config.redis
    local redis_cli, err = redis.get_redis_cli(redis_config)
    if err ~= nil then
        return nil, err
    end

    local res, err = redis_cli:get(email)
    if not res then
        return nil, err
    end

    if res == ngx.null then
        return nil, "not found redis key:" .. email
    end

    local timeout = redis_config.timeout or 5000
    local pool_num = redis_config.size or 100
    local ok, err = redis_cli:set_keepalive(timeout, pool_num)
    if not ok then
        ngx.log(ngx.ERR, "redis set keepalive failed")
        redis_cli:close()
    end

    ngx.log(ngx.ERR, res)
    return json.decode(res), nil
end

function _M.run(ctx)
    if is_internal() then
        return
    end

    local server = ngx.var.host
    local token = request.get_header(header_token)
    if type(token) == "table" then
        ngx.exit(forbidden_code)
    end

    if token == nil then
        ngx.exit(forbidden_code)
    end

    local msg = ctx.msg
    if not msg then
        msg = {}
        ctx.msg = msg
    end

    msg.time = ngx_time()
    msg.resource = server
    msg.status = "success"
    msg.method = get_method()
    msg.body = ""
    local secret = module.config.secret
    if secret then
        local email = parse_token(secret, token)
        local data, stale_data, flags = module.cache:get(email)
        msg.user = email
        msg.ip = ngx.var.remote_addr
        if data ~= nil then
            if data[server] ~= nil then
                read_body()
                local data = get_body() or ""
                msg.body = data
                return
            else
                msg.status = "fail"
                ngx.exit(forbidden_code)
            end
        end

        local data, err = get_email_info(email)
        if data ==nil or err ~= nil then
            msg.status = "fail"
            ngx.log(ngx.ERR, err)
            ngx.exit(500)
        end

        module.cache:set(email, data, ttl)

        if data[server] ~= nil then
            return
        else
            msg.status = "fail"
            ngx.exit(forbidden_code)
        end
    end

    msg.status = "fail"
    ngx.exit(500)
end

return _M
