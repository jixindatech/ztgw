local exit = os.exit
local stderr = io.stderr
local popen = io.popen

local _M = {}

function _M.exit(...)
    stderr:write(...)
    exit(1)
end

function _M.exec_cmd(cmd)
    local t, err = popen(cmd)
    if not t then
        return nil, "failed to execute command: " .. cmd .. ", error info: " .. err
    end

    local data, err = t:read("*all")
    t:close()

    if err ~= nil then
        return nil, "failed to read execution result of: " .. cmd .. ", error info: " .. err
    end

    return data
end

return _M
