local type = type
local tostring = tostring
local require = require
local tab_insert = table.insert
local tab_clear  = table.clear
local lfs   = require("lfs")
local yaml  = require("tinyyaml")
local cjson = require("cjson.safe")
local radixtree = require("resty.radixtree")
local producer = require "resty.kafka.producer"
local logger = require("resty.logger.socket")
local schema = require("ztgw.schema")
local config = require("ztgw.core.config")
local request = require("ztgw.core.request")
local aes   = require("ztgw.utils.aes")

local ngx = ngx
local ngx_time = ngx.time
local is_internal = ngx.req.is_internal
local get_method = ngx.req.get_method
local read_body = ngx.req.read_body
local get_body =  ngx.req.get_body_data

local gw_config = ngx.config.prefix() .. "etc/gw.yaml"
local cached_version
local module = {}
local module_name = "gw"
local header_token = "ZTGW-Token"
local users = {}
local forbidden_code
local broker_list = {}
local kafka_topic = ""

local _M = { version = "0.1"}

_M.name = module_name

local user_email_pat = "^[_A-Za-z0-9-]+(\\.[_A-Za-z0-9-]+)*@[A-Za-z0-9]+(\\.[A-Za-z0-9]+)*(\\.[A-Za-z]{2,})$"
local user_email_def = {
    type = "string",
    pattern = user_email_pat,
}

local gw_schema = {
    type = "object",
    properties = {
        id = schema.id_shema,
        name = user_email_def,
        resources = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    host = {
                        type = "string"
                    },
                    path = {
                        type = "string"
                    },
                    methods = {
                        type = "array",
                        items = {
                            type = "string"
                        }
                    }
                }
            }
        }
    }
}

function _M.init_worker()
    local options = {
        key = module_name,
        schema = gw_schema,
        automatic = true,
        interval = 10,
    }

    local err
    module, err = config.new(module_name, options)
    if err ~= nil then
        return err
    end

    local attributes
    attributes, err = lfs.attributes(gw_config)
    if not attributes then
        ngx.log(ngx.ERR, "failed to fetch ", gw_config, " attributes: ", err)
        return
    end

    local f
    f, err = io.open(gw_config, "r")
    if not f then
        ngx.log(ngx.ERR, "failed to open file ", gw_config, " : ", err)
        return err
    end

    local yaml_config = f:read("*a")
    f:close()

    local gw_yaml = yaml.parse(yaml_config)
    if not gw_yaml then
        return err
    end

    module.local_config = gw_yaml

    if module.local_config.log == nil then
        return "gw config log is missing"
    end

    if module.local_config.log.kafka and module.local_config.log.kafka.broker ~= nil then
        for _, item in pairs(module.local_config.log.kafka.broker) do
            tab_insert(broker_list, item)
        end
        if #broker_list == 0 then
            return "kafka configuration is missing"
        end

        kafka_topic = module.local_config.log.kafka.topic or "ztgw"
    end

    forbidden_code = module.local_config.deny_code or 401
    return nil
end

local function empty_func()

end

local function create_user_map(values)
    users = {}
    for _, user in ipairs(values or {}) do
        local radixtree_host_routes = {}
        for _, resource in ipairs(user.value.resources or {}) do
            local radixtree_uri_route
            if #resource.methods > 0 then
                radixtree_uri_route = {
                    paths = resource.path or "/*",
                    methods = resource.methods,
                    handler = function (api_ctx)
                        api_ctx.gw_matched = true
                    end
                }
            else
                radixtree_uri_route = {
                    paths = resource.path or "/*",
                    handler = function (api_ctx)
                        api_ctx.gw_matched = true
                    end
                }
            end

            local radixtree_uri_routes = {}
            tab_insert(radixtree_uri_routes, radixtree_uri_route)
            local sub_router = radixtree.new(radixtree_uri_routes)

            tab_insert(radixtree_host_routes, {
                paths = resource.host:reverse(),
                filter_fun = function(vars, opts, ...)
                    return sub_router:dispatch(vars.uri, opts, ...)
                end,
                handler = empty_func,
            })
        end

        local user_host_router
        if #radixtree_host_routes > 0 then
            user_host_router = radixtree.new(radixtree_host_routes)
        end

        users[user.value.id] = {
            id = user.value.id,
            email = user.value.name,
            resources = user_host_router,
            secret = user.value.secret,
        }
    end
end

local function get_user_info(id)
    if not cached_version or cached_version ~= module.conf_version then
        create_user_map(module.values)
        cached_version = module.conf_version
    end

    if users[id] == nil then
        return nil, 'invalid user id'
    end

    return users[id], nil
end

local function get_user(token)
    local data, err = cjson.decode(token)
    if err ~= nil then
        return nil, err
    end

    local user
    user, err = get_user_info(tostring(data.id))
    if err ~= nil then
        return nil, err
    end

    local user_data
    user_data, err = aes.decrypt(user.secret, data.data)
    if err ~= nil then
        return nil, err
    end

    local user_item = cjson.decode(user_data)
    if user_item ~= nil and user_item.email == user.email then
        return user
    end

    return  nil, 'invalid user'
end

local match_opts = {}
function _M.access(ctx)
    if is_internal() then
        return
    end

    local server = ngx.var.host

    if false then
        local msg = { }
        if not ctx.gw_msg then
            ctx.gw_msg = msg
        end

        msg.time = ngx_time()
        msg.resource = server
        msg.status = "success"
        msg.method = get_method()
        msg.body = ""

        return
    end

    local token = request.get_header(header_token)
    if type(token) == "table" then
        ngx.exit(forbidden_code)
    end

    if token == nil then
        ngx.exit(forbidden_code)
    end

    local user, err = get_user(token)
    if err ~= nil or user == nil then
        ngx.log(ngx.ERR, err or 'user is nil')
        ngx.exit(forbidden_code)
    end


    local msg = { }
    if not ctx.gw_msg then
        ctx.gw_msg = msg
    end

    msg.time = ngx_time()
    msg.resource = server
    msg.status = "success"
    msg.method = get_method()
    msg.uri = ngx.var.uri
    msg.body = ""

    msg.user = user.email
    msg.ip = ngx.var.remote_addr
    if user.resources then
        tab_clear(match_opts)
        match_opts.method = ctx.var.request_method
        match_opts.remote_addr = ctx.var.remote_addr
        match_opts.vars = ctx.var
        match_opts.host = ctx.var.host

        local host = ctx.var.host
        local ok, err = user.resources:dispatch(host:reverse(), match_opts, ctx)
        if ok and ctx.gw_matched then
            read_body()
            local body = get_body() or ""
            msg.body = body
            return
        else
            ngx.log(ngx.ERR, 'not matched')
        end
    else
        ngx.log(ngx.ERR, 'user resources is nil')
    end

    msg.status = "fail"
    ngx.exit(forbidden_code)
end

local function file(msg)
    local logstr = cjson.encode(msg)
    ngx.log(ngx.ERR, logstr)

end

local function rsyslog(msg)
    if not logger.initted() then
        local ok, err = logger.init {
            host = module.local_config.log.rsyslog.host,
            port = module.local_config.log.rsyslog.port,
            sock_type = module.local_config.log.rsyslog.type,
            flush_limit = 1,
            --drop_limit = 5678,
            timeout = 10000,
            pool_size = 100
        }
        if not ok then
            ngx.log(ngx.ERR, "failed to initialize the logger: ", err)
            return
        end
    end

    local logstr = cjson.encode(msg)
    local bytes, err = logger.log(logstr.."\n")
    if err then
        ngx.log(ngx.ERR, "failed to log message: ", err)
        return
    end

end

local function kafkalog(msg)
    local message = cjson.encode(msg)
    local bp = producer:new(broker_list, { producer_type = "async" })
    local ok, err = bp:send(kafka_topic, nil, message)
    if not ok then
        ngx.log(ngx.ERR, "kafka send err:", err)
        return
    end
end

function _M.log(ctx)
    local msg = ctx.gw_msg
    if msg ~= nil then
        if module and module.local_config.log.file then
            file(msg)
        end

        if module and module.local_config.log.rsyslog then
            rsyslog(msg)
        end

        if module and module.local_config.log.kafka then
            kafkalog(msg)
        end
    end
end

return _M
