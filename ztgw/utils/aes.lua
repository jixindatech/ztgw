local require = require
local aes = require "resty.aes"

local iv = "yehuoshaobujin!!"
local _M = { version="0.1" }

function _M.decrypt(key, data)
    local ase_handle, err = aes:new(key, nil, aes.cipher(256,"cbc"), {iv=iv, method=nil})
    if err ~= nil then
        return nil, err
    end
    local res = ngx.decode_base64(data)
    return ase_handle:decrypt(res), nil
end

return _M
