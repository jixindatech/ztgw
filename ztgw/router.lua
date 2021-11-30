local byte = string.byte
local type = type
local ipairs = ipairs
local pairs = pairs
local tab_insert = table.insert
local tab_clear = table.clear
local cjson = require("cjson.safe")
local ngx  = ngx
local require = require
local radixtree = require("resty.radixtree")
local config = require("ztgw.core.config")
local schema = require("ztgw.schema")
local balancer = require("ztgw.router.balancer")
local ip        = require("ztgw.utils.ip")

local _M = {version = "0.1" }

local module_name = "router"
local module

local cached_version
local host_router
local only_uri_router

function _M.init_worker()
    local options = {
        interval = 10,
        key = module_name,
        automatic = true,
        schema = schema.router,
    }

    local err
    module, err = config.new(module_name, options)
    if err ~= nil then
        return err
    end

    return nil
end

function _M.get_upstream(api_ctx, router)
    local server_picker = balancer.get_server_picker(router.value.upstream, router.value.id, module.conf_version)
    if not server_picker then
        return nil, nil, "failed to fetch server picker"
    end

    local server, err = server_picker.val.get(api_ctx)
    if not server then
        return nil, nil, "failed to find valid upstream server, " .. err
    end

    local balancer_ip, balancer_port, err = ip.parse_addr(server)
    api_ctx.balancer_ip = balancer_ip
    api_ctx.balancer_port = balancer_port

    --return balancer_ip, balancer_port, err
    ngx.log(ngx.ERR, balancer_ip .. tostring(balancer_port))

    return "127.0.0.1", 6000, nil
end

local function push_host_router(route, host_routes, only_uri_routes)
    if type(route) ~= "table" then
        return
    end

    local filter_fun, err
    if route.value.filter_func then
        filter_fun, err = loadstring(
                "return " .. route.value.filter_func,
                "router#" .. route.value.id)
        if not filter_fun then
            core.log.error("failed to load filter function: ", err,
                    " route id: ", route.value.id)
            return
        end

        filter_fun = filter_fun()
    end

    local hosts = route.value.hosts or {route.value.host}

    local radixtree_route = {
        paths = route.value.uris or route.value.uri,
        methods = route.value.methods,
        remote_addrs = route.value.remote_addrs
                or route.value.remote_addr,
        vars = route.value.vars,
        filter_fun = filter_fun,
        handler = function (api_ctx)
            api_ctx.matched_params = nil
            api_ctx.matched_route = route
        end
    }
    if #hosts == 0 then
        tab_insert(only_uri_routes, radixtree_route)
        return
    end

    for i, host in ipairs(hosts) do
        local host_rev = host:reverse()
        if not host_routes[host_rev] then
            host_routes[host_rev] = {radixtree_route}
        else
            tab_insert(host_routes[host_rev], radixtree_route)
        end
    end

end

local function empty_func() end
local function create_radixtree_router(routes)
    local host_routes = {}
    local only_uri_routes = {}
    host_router = nil

    for _, route in ipairs(routes or {}) do
        push_host_router(route, host_routes, only_uri_routes)
    end

    -- create router: host_router
    local host_router_routes = {}
    for host_rev, routes in pairs(host_routes) do
        local sub_router = radixtree.new(routes)
        tab_insert(host_router_routes, {
            paths = host_rev,
            filter_fun = function(vars, opts, ...)
                return sub_router:dispatch(vars.uri, opts, ...)
            end,
            handler = empty_func,
        })
    end

    if #host_router_routes > 0 then
        host_router = radixtree.new(host_router_routes)
    end

    only_uri_router = radixtree.new(only_uri_routes)
    return true
end

local match_opts = {}
function _M.match(api_ctx)
    if not cached_version or cached_version ~= module.conf_version then
        create_radixtree_router(module.values)
        cached_version = module.conf_version
    end

    tab_clear(match_opts)
    match_opts.method = api_ctx.var.request_method
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var
    match_opts.host = api_ctx.var.host

    if host_router then
        local host_uri = api_ctx.var.host
        local ok = host_router:dispatch(host_uri:reverse(), match_opts, api_ctx)
        if ok then
            return true
        end
    end

    local ok = only_uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx)
    if ok then
        return true
    end

    ngx.log(ngx.ERR, "not find any matched route")
    return true
end

return _M

