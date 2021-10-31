local require = require
local table_insert = table.insert
local tostring = tostring
local pairs = pairs

local cjson = require("cjson.safe")
local logger = require("resty.logger.socket")
local producer = require("resty.kafka.producer")
local config = require("ztgw.core.config")

local _M = { version = "0.1" }
local module_name = "log"
local module

local broker_list = {}
local kafka_topic = ""

function _M.init_worker()
    local options = {
        key = module_name,
        automatic = false,
    }

    local err
    module, err = config.new(module_name, options)
    if err ~= nil then
        return err
    end

    if module.config.log == nil then
        return "log type is missing"
    end

    if module.config.log.kafka.broker ~= nil then
        for _, item in pairs(module.config.log.kafka.broker) do
            table_insert(broker_list, item)
        end
    end
    if #broker_list == 0 then
        return "kafka configuration is missing"
    end

    kafka_topic = module.config.log.kafka.topic or "ztgw"

end

local function kafkalog(msg)
    local message = cjson.encode(msg)
    local bp = producer:new(broker_list, { producer_type = "async" })
    local ok, err = bp:send(kafka_topic, nil, message)
    if not ok then
        ngx.log(ngx.ERR, "kafka send err:", err)
        return
    end
end

local function rsyslog(msg)
    if not logger.initted() then
        local ok, err = logger.init {
            host = module.config.log.rsyslog.host,
            port = module.config.log.rsyslog.port,
            sock_type = module.config.log.rsyslog.type,
            flush_limit = 1,
            --drop_limit = 5678,
            timeout = 10000,
            pool_size = 100
        }
        if not ok then
            ngx.log(ngx.ERR, "failed to initialize the logger: ", err)
            return
        end
    end

    local logstr = " user=" .. msg.user ..
            " method=" .. msg.method ..
            " resource=" .. msg.resource ..
            " body=" .. msg.body ..
            " time=" .. tostring(msg.time) ..
            " status=" .. msg.status ..
            " ip=" .. msg.ip .. "\n"

    local bytes, err = logger.log(logstr)
    if err then
        ngx.log(ngx.ERR, "failed to log message: ", err)
        return
    end

end

local function file(msg)
    local logstr = cjson.encode(msg)
    ngx.log(ngx.ERR, logstr)

end

function _M.run(ctx)
    local msg = ctx.msg
    if msg ~= nil then
        if module and module.config.log.file then
            file(msg)
        end

        if module and module.config.log.rsyslog then
            rsyslog(msg)
        end

        --if module and module.config.log.kafka then
        --    kafkalog(msg)
        --end
    end


end

return _M
