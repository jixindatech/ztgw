local require = require
local io_open = io.open
local yaml = require("tinyyaml")
local config_redis = require("ztgw.core.config_redis")
local config_yaml = require("ztgw.core.config_yaml")

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

function _M.get_config_type()
    if config_data then
        return config_data.config_type
    end

    return nil
end

function _M.new(name, options)
    if config_data then
        if config_data.config_type == "redis" then
            local module, err = config_redis.new(name, config_data, options)
            if err ~= nil then
                return nil, err
            end

            return module, nil
        elseif config_data.config_type == "yaml" then
            local module, err = config_yaml.new(name, config_data, options)
            if err ~= nil then
                return nil, err
            end

            return module, nil
        else
            return nil, "wrong config_type"
        end
    else
        return nil, "config data is empty or wrong config_type"
    end
end

return _M
