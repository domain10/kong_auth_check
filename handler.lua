local BasePlugin = require "kong.plugins.base_plugin"
local MyAuthCheck = BasePlugin:extend()

local kong = kong
local url = require "socket.url"
local http = require "resty.http"
local cjson_safe = require 'cjson';

MyAuthCheck.PRIORITY = 800
MyAuthCheck.VERSION="0.1.0"

function MyAuthCheck:new()
   MyAuthCheck.super.new(self, "change-url")
end

function segmentationString(str,mstring)
    if type(str)~="nil" then
        local index=string.find(mstring,str,1,true)
        if type(index)~="nil" then
            return string.sub(mstring,(index+string.len(str)))
        else
            return mstring
        end
    else
        return mstring
    end
end

--获取请求路径信息
local function parse_url(host_url)
    local parsed_url = url.parse(host_url)
    
    if not parsed_url.port then
        if parsed_url.scheme == "http" then
            parsed_url.port = 80
        elseif parsed_url.scheme == "https" then
            parsed_url.port = 443
        end
    end
    if not parsed_url.path then
        parsed_url.path = "/"
    end
    
    return parsed_url
end

-- 去用户中心验证
function requestUcenter(url, body, token)
    local requestUrl = parse_url(url)
    local httpc = http.new()
    
    httpc:set_timeout(10000)
    ok, err = httpc:connect(requestUrl.host, tonumber(requestUrl.port))
    if not ok then
        return nil, "failed to connect to " .. url .. ": " .. err
    end
    
    local res, err = httpc:request({
        method = "POST",
        path = requestUrl.path,
        query = requestUrl.query,
        headers = {
            ["Host"] = requestUrl.host,
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = token,-- ngx_encode_base64(token)
        },
        body = body,
    })
    if not res then
        return nil, "failed request to " .. url .. ": " .. err
    end
    local response_body = res:read_body()
    if res.status ~= 200 then
        return kong.response.exit(res.status, { message = response_body })
    end
    
    -- ok, err = httpc:set_keepalive(keepalive)
    -- if not ok then
        -- kong.log.err("failed keepalive for ", host, ":", tostring(port), ": ", err)
    -- end
    
    return response_body, nil
end


function MyAuthCheck:access(conf)
    MyAuthCheck.super.access(self)
    -- ngx.log(ngx.ERR, "1: ".. ngx.var.request_method ..", upstream_uri:" .. ngx.var.upstream_uri .."\n")
    if conf.ucenter_url ~= nil then
        -- ngx.var.upstream_uri
        local originHeader = ngx.req.get_headers()
        if originHeader["authorization"] == nil then
            return kong.response.exit(400, { message = "token missing" })
        end
        
        local data = "route=" .. ngx.var.request_method .."|".. ngx.var.request_uri
        local body, err = requestUcenter(conf.ucenter_url, data, originHeader["authorization"])
        if type(err) ~= "nil" then
            return kong.response.exit(500, { message = err })
        end
    end
end

return MyAuthCheck
