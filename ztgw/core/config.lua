local io_open = io.open

local require = require
local yaml = require("tinyyaml")
local config_redis = require("ztgw.core.config_redis")

local _M = { version=0.1 }

local config_data
local modules = {}

local function read_file(path)
    local file, err = io_open(path, "rb")
    if not file then
        ngx.log(ngx.ERR, "faild to read config file:" .. path .. ", error info:", err)
        return nil, err
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end

function _M.load_conf(path)
    local data, err = read_file(path)
    if err ~= nil then
        return nil, err
    end

    config_data, err = yaml.parse(data)
    return err
end

function _M.new(name, options)
    if modules and modules[name] ~= nil then
        return nil, "already exist module:" .. name
    end

    if config_data and config_data.type == "redis" then
        local module, err = config_redis.new(name, config_data, options)
        if err ~= nil then
            return nil, err
        end

        modules[name] = module

        return module, nil
    else
        return nil, "config data is empty or wrong config type"
    end
end

return _M
