local byte = string.byte
local ngx  = ngx
local require = require
local ssl = require("ngx.ssl")
local config = require("ztgw.core.config")

local _M = {version = "0.1" }

local module_name = "cert"
local module

local function validate(data)
    return data
end

function _M.init_worker()
    local options = {
        interval = 10,
        key = module_name,
        automatic = true,
        validate = validate,
    }

    local err
    module, err = config.new(module_name, options)
    if err ~= nil then
        return err
    end

    return nil
end

function _M.run()
    if module and module.value then
        local certificates = module.value
        local server, err = ssl.server_name()
        if err ~= nil then
            ngx.exit(ngx.ERROR)
        end

        if certificates[server] == nil then
            ngx.log(ngx.ERR, "ssl: not found certificates")
            ngx.exit(ngx.ERROR)
        end

        local crt = certificates[server].pub
        local key = certificates[server].pri

        local ok, err = ssl.clear_certs()
        if not ok then
            ngx.log(ngx.ERR, "failed to clear existing (fallback) certificates")
            return ngx.exit(ngx.ERROR)
        end

        local der_cert_chain, err = ssl.cert_pem_to_der(crt)
        if not der_cert_chain then
            ngx.log(ngx.ERR, "failed to convert certificate chain ",
                "from PEM to DER: ", err)
            return ngx.exit(ngx.ERROR)
        end

        local ok, err = ssl.set_der_cert(der_cert_chain)
        if not ok then
            ngx.log(ngx.ERR, "failed to set DER cert: ", err)
            return ngx.exit(ngx.ERROR)
        end

        local der_pkey, err = ssl.priv_key_pem_to_der(key)
        if not der_pkey then
            ngx.log(ngx.ERR, "failed to convert private key ",
                "from PEM to DER: ", err)
            return ngx.exit(ngx.ERROR)
        end

        local ok, err = ssl.set_der_priv_key(der_pkey)
        if not ok then
            ngx.log(ngx.ERR, "failed to set DER private key: ", err)
            return ngx.exit(ngx.ERROR)
        end

    else
        return ngx.exit(ngx.ERROR)
    end

    --[[
    local name, err = ssl.server_name()
    ngx.log(ngx.ERR, "ssl name:", name)
    --local addr, addrtyp, err = ssl.raw_client_addr()
    local addr, addrtyp, err = ssl.raw_server_addr()
    if not addr then
        ngx.log(ngx.ERR, "failed to fetch raw server addr: ", err)
        return
    end

    if addrtyp == "inet" then  -- IPv4
        local ip = string.format("%d.%d.%d.%d", byte(addr, 1), byte(addr, 2),
            byte(addr, 3), byte(addr, 4))
        ngx.log(ngx.ERR, "Using IPv4 address: " .. ip)

    elseif addrtyp == "unix" then  -- UNIX
        ngx.log(ngx.ERR, "Using unix socket file: " .. addr)

    else  -- IPv6
        -- leave as an exercise for the readers
    end
    ]]--
end

return _M

