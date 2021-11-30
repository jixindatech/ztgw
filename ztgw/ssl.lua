local byte = string.byte
local ipairs = ipairs
local type = type
local ngx  = ngx
local require = require
local cjson = require("cjson.safe")
local ngx_ssl = require("ngx.ssl")
local radixtree = require("resty.radixtree")
local config = require("ztgw.core.config")
local schema = require("ztgw.schema")

local _M = {version = "0.1" }

local module_name = "ssl"
local module

local ssl_router
local ssl_router_version

function _M.init_worker()
    local options = {
        interval = 10,
        key = module_name,
        automatic = true,
        schema = schema.ssl,
    }

    local err
    module, err = config.new(module_name, options)
    if err ~= nil then
        return err
    end

    return nil
end

local function create_router(items)
    local ssl_items = items or {}

    local route_items = { }
    local idx = 0

    for _, ssl in ipairs(ssl_items) do
        if type(ssl) == "table" then
            local sni = ssl.value.sni:reverse()
            ngx.log(ngx.ERR, 'sni:'..sni)
            idx = idx + 1
            route_items[idx] = {
                paths = sni,
                handler = function (ctx)
                    if not ctx then
                        return
                    end
                    ctx.matched_ssl = ssl
                    ctx.matched_sni = sni
                end
            }
        end
    end

    local router, err = radixtree.new(route_items)
    if not router then
        return nil, err
    end

    return router
end

local function set_pem_ssl_key(cert, key)
    local ok, err = ngx_ssl.clear_certs()
    if not ok then
        ngx.log(ngx.ERR, "failed to clear existing (fallback) certificates")
        return err
    end

    local der_cert_chain, err = ngx_ssl.cert_pem_to_der(cert)
    if not der_cert_chain then
        ngx.log(ngx.ERR, "failed to convert certificate chain ",
                "from PEM to DER: ", err)
        return err
    end

    local ok, err = ngx_ssl.set_der_cert(der_cert_chain)
    if not ok then
        ngx.log(ngx.ERR, "failed to set DER cert: ", err)
        return err
    end

    local der_pkey, err = ngx_ssl.priv_key_pem_to_der(key)
    if not der_pkey then
        ngx.log(ngx.ERR, "failed to convert private key ",
                "from PEM to DER: ", err)
        return err
    end

    local ok, err = ngx_ssl.set_der_priv_key(der_pkey)
    if not ok then
        ngx.log(ngx.ERR, "failed to set DER private key: ", err)
        return err
    end

    return nil
end

function _M.run()
    local err
    if not ssl_router or
            ssl_router_version ~= module.conf_version then
        ssl_router, err = create_router(module.values)
        if not ssl_router then
            return nil, "failed to create radixtree router: " .. err
        end
        ssl_router_version = module.conf_version
    end

    local ctx = {}
    local sni
    sni, err = ngx_ssl.server_name()
    if type(sni) ~= "string" then
        return nil, "failed to fetch SNI: " .. (err or "not found")
    end

    local ok = ssl_router:dispatch(sni:reverse(), nil, ctx)
    if not ok then
        return nil, "not found any valid sni configuration"
    end

    local matched_ssl = ctx.matched_ssl
    err = set_pem_ssl_key(matched_ssl.value.cert, matched_ssl.value.key)
    if err then
        return nil, err
    end

    return ctx.matched_sni, nil
end

return _M

