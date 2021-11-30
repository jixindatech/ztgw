local require = require
local cjson  = require("cjson.safe")
local lrucache    = require("resty.lrucache")
local roundrobin  = require("resty.roundrobin")
local resty_chash = require("resty.chash")
local healthcheck = require("resty.healthcheck")
local config      = require("ztgw.core.config")
local ip          = require("ztgw.utils.ip")
local balancer    = require("ngx.balancer")
local set_more_tries   = balancer.set_more_tries
local get_last_failure = balancer.get_last_failure
local set_timeouts     = balancer.set_timeouts
local tostring    = tostring
local pairs       = pairs
local tab_insert  = table.insert
local str_char    = string.char
local str_gsub    = string.gsub

local _M = { version = 0.1 }

local cached_item = 1024
local cached_ttl = 60 * 60
local picker_cache = lrucache.new(cached_item)

local module
local module_name = "upstream"

local function init_func(upstream_item)

end

function _M.init_worker(config_data)
    local options = {
        interval = 10,
        key = module_name,
        automatic = true,
        conf_version = nil,
        init_func = init_func,
    }

    local err
    module, err = config.new(module_name, options)
    if err ~= nil then
        return err
    end

    return nil
end

local function create_checker(upstream)
    local checker = healthcheck.new({
        name = "upstream#" .. upstream.id,
        shm_name = "upstream-healthcheck",
        checks = upstream.checks,
    })

    local host = upstream.checks and upstream.checks.host
    for addr, weight in pairs(upstream.nodes) do
        local ip, port = ip.parse_addr(addr)
        local ok, err = checker:add_target(ip, port, host, true)
        if not ok then
            ngx.log(ngx.ERR, "failed to add new health check target: ", addr, " err: ", err)
        end
    end

    tab_insert(upstream.clean_handlers, function (upstream_item)
        upstream_item.value.checker:stop()
    end)

    return checker
end

local function retry_handle(upstream, ctx)
    local retries = upstream.retries
    if retries and retries > 0 then
        ctx.balancer_try_count = (ctx.balancer_try_count or 0) + 1
        ngx.log(ngx.ERR, 'retry count:'..tostring(ctx.balancer_try_count or 0))
        if ctx.balancer_try_count > 1 then
            return balancer.get_last_failure()
        end

        if ctx.balancer_try_count == 1 then
            balancer.set_more_tries(retries)
        end
    end
end

local function get_health_nodes(upstream, checker)
    if not checker then
        return upstream.nodes
    end

    local host = upstream.checks and upstream.checks.host
    local up_nodes = {}

    local count = 0
    for addr, weight in pairs(upstream.nodes) do
        local ip, port = ip.parse_addr(addr)
        local ok, err = checker:get_target_status(ip, port, host)
        if ok then
            count = count + 1
            up_nodes[addr] = weight
        else
            ngx.log(ngx.ERR, 'get target status error:'..err)
        end
    end

    if count == 0 then
        ngx.log(ngx.ERR, "all upstream nodes is unhealth, use default")
        up_nodes = upstream.nodes
    end

    return up_nodes
end

local function get_upstream_healthchecker(upstream)
    if upstream.checker then
        return upstream.checker
    end

    upstream.checker = create_checker(upstream)
    return upstream.checker
end

local function get_server_picker(upstream, checker, version)
    local key = upstream.type .. "#upstream_" .. upstream.id
    if picker_cache  then
        local picker = picker_cache:get(key)
        if picker and picker._cache_ver == version then
            return picker
        end
    else
        return nil, "invalid lru cache"
    end

    local obj
    local up_nodes = get_health_nodes(upstream, checker)
    if upstream.type == "roundrobin" then
        local picker = roundrobin:new(up_nodes)
        obj =  {
            upstream = upstream,
            get = function ()
                return picker:find()
            end
        }
    end

    if upstream.type == "chash" then
        local str_null = str_char(0)

        local count = 0
        local servers, nodes = {}, {}
        for serv, weight in pairs(up_nodes) do
            local id = str_gsub(serv, ":", str_null)

            servers[id] = serv
            nodes[id] = weight
            count = count + 1
        end

        local picker = resty_chash:new(nodes)
        local key = upstream.key
        obj =  {
            upstream = upstream,
            count = count,
            get = function (ctx)
                if ctx.balancer_try_count > count then
                    return nil, "all server tried"
                end

                local id, index
                if (ctx.upstream_tried_index ~= nil) then
                    id, index = picker:next(ctx.upstream_tried_index)
                    return servers[id]
                else
                    id, index = picker:find(ctx.var[key])
                    ctx.upstream_tried_index = index
                end

                return servers[id]
            end
        }
    end

    local cached_obj = {value = obj, _cache_ver = version}
    picker_cache:set(key, cached_obj, cached_ttl)

    return cached_obj, nil
end

function _M.get(api_ctx, id)
    local upstream_item = module:get(id)
    if upstream_item == nil then
        return nil, "invalid upstream id"
    end

    local version = upstream_item.modifiedIndex
    local upstream = upstream_item.value

    local checker
    if upstream.checks then
        checker = get_upstream_healthchecker(upstream)
    end

    local state, code = retry_handle(upstream, api_ctx)
    if checker then
        if state == "failed" then
            if code == 504 then
                checker:report_timeout(api_ctx.balancer_ip, api_ctx.balancer_port, upstream.checks.host)
            else
                checker:report_tcp_failure(api_ctx.balancer_ip, api_ctx.balancer_port, upstream.checks.host)
            end
        elseif state == "next" then
            checker:report_http_status(api_ctx.balancer_ip, api_ctx.balancer_port, upstream.checks.host, code)
        end
    end

    local server_picker, err = get_server_picker(upstream, checker, version)
    if err ~= nil then
        return "", 0, err
    end

    local server, err = server_picker.value.get(api_ctx)
    if not server then
        return nil, nil, "failed to find valid upstream server, " .. err
    end

    local balancer_ip, balancer_port, err = ip.parse_addr(server)
    api_ctx.balancer_server = server
    api_ctx.balancer_ip = balancer_ip
    api_ctx.balancer_port = balancer_port

    return balancer_ip, balancer_port, err
end

return _M