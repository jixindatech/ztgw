local require = require
local cjson = require("cjson.safe")
local config = require("gw.core.config")
local zt = require("gw.plugins.zt")


local _M = {}
-- local local_plugins = { zt }
local local_plugins = { }
local function plugin_init_worker()
    for _, item in ipairs(local_plugins) do
        if item.init_worker then
            local ok, err = item.init_worker()
            if err ~= nil then
                return nil, err
            end
        end
    end

    return true, nil
end

function _M.init_worker()
    return plugin_init_worker()
end

function _M.run(phase, ctx)
    for _, item in ipairs(local_plugins) do
        if item[phase] then
            local code ,err = item[phase](ctx)
        end
    end
end

return _M
