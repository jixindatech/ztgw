local require = require
local math    = math
local error   = error
local ngx     = ngx

local config    = require("ztgw.core.config")
local ssl       = require("ztgw.ssl")
local gw        = require("ztgw.gw")
local banlancer = require("ztgw.balancer")
local log       = require("ztgw.log")

local seed = ngx.time()

local _M = {version = 0.1}

local config_path =  ngx.config.prefix() .. "conf/config.yaml"

function _M.http_init()
    require("resty.core")
    math.randomseed(seed)

    local err
    err = config.load_conf(config_path)
    if err ~= nil then
        error(err)
    end
end

function _M.http_init_worker()
    local err = banlancer.init_worker()
    if err ~= nil then
        ngx.log(ngx.ERR, "balancer init worker failed:" .. err)
    end

    err = ssl.init_worker()
    if err ~= nil then
        ngx.log(ngx.ERR, "balancer init worker failed:" .. err)
    end

    err = gw.init_worker()
    if err ~= nil then
        ngx.log(ngx.ERR, "gw init worker failed:" .. err)
    end

    err = log.init_worker()
    if err ~= nil then
        ngx.log(ngx.ERR, "log init worker failed:" .. err)
    end

end

function _M.http_ssl_phase()
    local ngx_ctx = ngx.ctx
    ssl.run(ngx_ctx)
end

function _M.http_access_phase()
    local ngx_ctx = ngx.ctx
    gw.run(ngx_ctx)
end

function _M.http_banlancer_phase()
    local ngx_ctx = ngx.ctx
    banlancer.run(ngx_ctx)
end

function _M.http_log_phase()
    local ngx_ctx = ngx.ctx
    log.run(ngx_ctx)
end

return _M
