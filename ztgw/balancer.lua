local require = require
local ngx = ngx
local json = require("cjson")
local balancer = require("ngx.balancer")
local config = require("ztgw.core.config")

local _M = { version = 0.1 }

local module

local function validate(data)
    return data
end

function _M.init_worker(config_data)
    local options = {
        interval = 10,
        key = "balancer",
        automatic = true,
        validate = validate,
    }

    local err
    module, err = config.new("balancer", options)
    if err ~= nil then
        return err
    end

    return nil
end

local function get_peer(ctx)
    local server = ngx.var.host
    local lb = module.value[server]
    if lb == nil then
        return nil, nil, "invalid host for lb"
    end

    local schedule = lb.schedule
    local upstreams = lb.upstreams
    local num = #upstreams
    local choice = 1
    ngx.log(ngx.ERR, schedule)
    if schedule == 'round' then
        if lb.next == nil then
            lb.next = 1
        end

        choice = lb.next%num + 1
        lb.next = lb.next + 1
    elseif schedule == 'hash' then
        local port = ngx.var.server_port
        local remote_ip = ngx.var.remote_addr
        local key = remote_ip..port
        local hash = ngx.crc32_long(key);
        choice = (hash%#upstreams) + 1
    else
        return nil, nil, "invalid schedule policy"
    end

    ngx.log(ngx.ERR, "choice:" .. choice)
    for k, v in pairs(upstreams) do
        ngx.log(ngx.ERR, "host:".. v.ip .. " port:".. v.port)
    end

    return upstreams[choice].ip, upstreams[choice].port, nil
end

function _M.run(ctx)
    if module and module.value then
        local host, port, err = get_peer(ctx)
        if host ~= nil and port ~= nil then
            local ok, err = balancer.set_current_peer(host, port)
            if not ok then
                ngx.log(ngx.ERR, "banlancer:", err)
            end
        else
            ngx.log(ngx.ERR, "banlancer err: ", err)
            ngx.exit(502)
        end
    else
        ngx.exit(502)
    end

end

return _M
