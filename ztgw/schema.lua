local require = require
local jsonschema = require 'jsonschema'

local _M = {}

local id_schema = {
    anyOf = {
        {
            type = "string", minLength = 1, maxLength = 32,
            pattern = [[^[0-9]+$]]
        },
        {type = "integer", minimum = 1}
    }
}

local ipv4_def = "[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}"
local ipv6_def = "([a-fA-F0-9]{0,4}:){0,8}(:[a-fA-F0-9]{0,4}){0,8}"
        .. "([a-fA-F0-9]{0,4})?"
local ip_def = {
    {pattern = "^" .. ipv4_def .. "$"},
    {pattern = "^" .. ipv4_def .. "/[0-9]{1,2}$"},
    {pattern = "^" .. ipv6_def .. "$"},
    {pattern = "^" .. ipv6_def .. "/[0-9]{1,3}$"},
}
_M.ip_def = ip_def

local remote_addr_def = {
    description = "client IP",
    type = "string",
    anyOf = ip_def,
}

local host_def_pat = "^\\*?[0-9a-zA-Z-.]+$"
local host_def = {
    type = "string",
    pattern = host_def_pat,
}
_M.host_def = host_def

_M.ssl = {
    type = "object",
    properties = {
        cert = {
            type = "string", minLength = 128, maxLength = 64*1024
        },
        key = {
            type = "string", minLength = 128, maxLength = 64*1024
        },
        sni = {
            type = "string",
            pattern = [[^\*?[0-9a-zA-Z-.]+$]],
        }
    },
    required = {"sni", "key", "cert"},
    additionalProperties = false,
}

local health_checker = {
    type = "object",
    properties = {
        active = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = {"http", "https", "tcp"},
                    default = "http"
                },
                timeout = {type = "integer", default = 1},
                concurrency = {type = "integer", default = 10},
                host = host_def,
                http_path = {type = "string", default = "/"},
                https_verify_certificate = {type = "boolean", default = true},
                healthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1, default = 0},
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = {200, 302}
                        },
                        successes = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        }
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1, default = 0},
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = {429, 404, 500, 501, 502, 503, 504, 505}
                        },
                        http_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        },
                        tcp_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 3
                        }
                    }
                },
                req_headers = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                        uniqueItems = true,
                    },
                }
            }
        },
        passive = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = {"http", "https", "tcp"},
                    default = "http"
                },
                healthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                            default = {200, 201, 202, 203, 204, 205, 206, 207,
                                208, 226, 300, 301, 302, 303, 304, 305,
                                306, 307, 308}
                        },
                        successes = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        }
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                            default = {429, 500, 503}
                        },
                        tcp_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 7
                        },
                        http_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        },
                    }
                }
            }
        }
    },
    additionalProperties = false,
    anyOf = {
        {required = {"active"}},
        {required = {"active", "passive"}},
    },
}

local upstream_schema = {
    type = "object",
    properties = {
        nodes = {
            description = "nodes of upstream",
            type = "object",
            patternProperties = {
                [".*"] = {
                    description = "weight of node",
                    type = "integer",
                    minimum = 0,
                }
            },
            minProperties = 1,
        },
        retries = {
            type = "integer",
            minimum = 1,
        },
        timeout = {
            type = "object",
            properties = {
                connect = {type = "number", minimum = 0},
                send = {type = "number", minimum = 0},
                read = {type = "number", minimum = 0},
            },
            required = {"connect", "send", "read"},
        },
        type = {
            description = "algorithms of load balancing",
            type = "string",
            enum = {"chash", "roundrobin"}
        },
        checks = health_checker,
        key = {
            description = "the key of chash for dynamic load balancing",
            type = "string",
            pattern = [[^((uri|server_name|server_addr|request_uri|remote_port]]
                    .. [[|remote_addr|query_string|host|hostname)]]
                    .. [[|arg_[0-9a-zA-z_-]+)$]],
        },
        desc = {type = "string", maxLength = 256},
        id = id_schema
    },
    required = {"nodes", "type"},
    additionalProperties = false,
}

_M.route = {
    type = "object",
    properties = {
        host = host_def,
        upstream_id = id_schema,
    },
    anyOf = {
        {required = {"upstream_id", "host"}},
    },
    additionalProperties = false,
}

function _M.check(chema, item)
    local validator = jsonschema.generate_validator(chema)
    return validator(item)
end

_M.id_shema = id_schema

return _M
