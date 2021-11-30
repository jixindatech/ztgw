local _M = {}

function _M.get_envs(home, path, cpath)
    local openresty_args = [[openresty -p ]] .. home .. [[ -c ]]
            .. home .. [[/conf/nginx.conf]] .. [[ -g 'daemon off;' ]]

    local envs = {
        openresty_args = openresty_args
    }
    return envs
end

return _M
