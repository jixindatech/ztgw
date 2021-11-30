local require = require
local lrucache    = require("resty.lrucache")
local roundrobin  = require("resty.roundrobin")
local resty_chash = require("resty.chash")

local str_char    = string.char
local str_gsub    = string.gsub
local pairs       = pairs

local _M = {}

local cached_item = 1024
local cached_ttl = 60 * 60
local picker_cache = lrucache.new(cached_item)

function _M.get_server_picker(upstream, id, version)
    local key = upstream.type .. "#route_" .. id
    if picker_cache  then
        local picker = picker_cache:get(key)
        if picker and picker._cache_ver == version then
            return picker
        end
    else
        return nil, "invalid lru cache"
    end

    local obj
    if upstream.type == "roundrobin" then
        local picker = roundrobin:new(upstream.nodes)
        obj =  {
            upstream = upstream,
            get = function ()
                return picker:find()
            end
        }
    end

    if upstream.type == "chash" then
        local str_null = str_char(0)

        local servers, nodes = {}, {}
        for serv, weight in pairs(upstream.nodes) do
            local id = str_gsub(serv, ":", str_null)

            servers[id] = serv
            nodes[id] = weight
        end

        local picker = resty_chash:new(nodes)
        local key = upstream.key
        obj =  {
            upstream = upstream,
            get = function (ctx)
                local id = picker:find(ctx.var[key])
                -- core.log.warn("chash id: ", id, " val: ", servers[id])
                return servers[id]
            end
        }
    end
    local cached_obj = {val = obj, _cache_ver = version}
    picker_cache:set(key, cached_obj, cached_ttl)

    return cached_obj, nil
end

return _M