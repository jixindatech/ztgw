local require = require
local print = print
local execute = os.execute
local stderr = io.stderr

local ver  = require("ztgw.core.version")
local util = require("ztgw.cli.util")

local _M = {}

local function help()
    print([[
Usage: ztgw [action] <argument>

help:       show this message, then exit
start:      start the ztgw server
stop:       stop the ztgw server
restart:    restart the ztgw server
version:    print the version of ztgw
]])

end

local function version()
    print(ver['VERSION'])
end

local function config_test(env)
    local cmd = env.openresty_args .. [[ -t -q ]]

    -- When success,
    -- On linux, os.execute returns 0,
    -- On macos, os.execute returns 3 values: true, exit, 0, and we need the first.
    local ret, err = util.exec_cmd((cmd))
    if (ret == 0 or ret == true) then
        return true, ""
    end

    return false, err
end

local function stop(env)
    local res, err = config_test(env)
    if err ~= nil then
        util.exit(err)
    end

    local cmd = env.openresty_args .. [[ -s stop ]]

    -- When success,
    -- On linux, os.execute returns 0,
    -- On macos, os.execute returns 3 values: true, exit, 0, and we need the first.
    local ret, err = util.exec_cmd((cmd))
    if (ret == 0 or ret == true) then
        return true, ""
    end
end

local function start(env)
    local res, err = config_test(env)
    if err ~= nil then
        util.exit(err)
    end

    local cmd = env.openresty_args

    -- When success,
    -- On linux, os.execute returns 0,
    -- On macos, os.execute returns 3 values: true, exit, 0, and we need the first.
    local ret, err = util.exec_cmd((cmd))
    if (ret == 0 or ret == true) then
        return true, ""
    end

end

local function restart(env)
    local res, err = config_test(env)
    if err ~= nil then
        util.exit(err)
    end

    local cmd = env.openresty_args .. [[ -s reload ]]

    -- When success,
    -- On linux, os.execute returns 0,
    -- On macos, os.execute returns 3 values: true, exit, 0, and we need the first.
    local ret, err = util.exec_cmd((cmd))
    if (ret == 0 or ret == true) then
        return true, ""
    end

end

local action = {
    version = version,
    start = start,
    stop  = stop,
    restart = restart,
}

function _M.exec(envs, arg)
    local cmd = arg[1]
    if not cmd then
        return help()
    end

    if not action[cmd] then
        stderr:write("invalid argument: ", cmd, "\n")
        return help()
    end

    action[cmd](envs, arg[2])
end

return _M
