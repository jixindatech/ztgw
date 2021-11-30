local ngx = ngx
local get_headers = ngx.req.get_headers

local _M = { version = "0.1" }

function _M.get_header(name)
    return get_headers()[name]
end

return _M
