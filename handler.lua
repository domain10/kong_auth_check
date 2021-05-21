local BasePlugin = require "kong.plugins.base_plugin"
local MyAuthCheck = BasePlugin:extend()

local kong = kong
local url = require "socket.url"
local http = require "resty.http"
local cjson = require 'cjson'

local rpc = require "kong.plugins.my-auth-check.rpc"

MyAuthCheck.PRIORITY = 800
MyAuthCheck.VERSION="0.1.0"

function MyAuthCheck:new()
   MyAuthCheck.super.new(self, "my-auth-check")
end

-- 获取请求路径信息
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

local function responseFrontend(status, data)
    local header = {
        ["Content-Type"] = "application/json; charset=utf-8",
        ["Access-Control-Allow-Origin"] = "*",
        ["Access-Control-Max-Age"] = 3602,
    }
    if 204 == status then
        header["Access-Control-Allow-Methods"] = "GET,POST,PUT,DELETE,OPTIONS,HEAD,PATCH"
        header["Access-Control-Allow-Headers"] = "Permission-From,Permission-Mode,Permission-Page,Authorization,tokeTypes,Lang,Content-Type,Accept,Origin,User-Agent,DNT,Cache-Control,X-Mx-ReqToken,Keep-Alive,X-Requested-With,If-Modified-Since,Captcha,X-Result-Fields"
    end
    return kong.response.exit(status, data, header)
end

--
local function handleResponse(res, jump_upstream)
    local tmp = cjson.decode(res)
    if tmp["error"] ~= nil then
        local status = 500
        if "Error: Token is not valid" == tmp["error"]["message"] then
            status = 401
        elseif tmp["error"]["code"] ~= nil and tmp["error"]["code"] >= 100 and tmp["error"]["code"] <= 600 then
            status = tmp["error"]["code"]
        end
        return responseFrontend(status, { message = tmp["error"]["message"] })
    elseif tmp["result"] ~= nil then
        tmp = tmp["result"]
    end
	
    if tmp["jump"] ~= nil and jump_upstream[tmp["jump"]] ~= nil and jump_upstream[tmp["jump"]] ~= "" then
        ngx.ctx.balancer_address.host = jump_upstream[tmp["jump"]]
        --return ngx.redirect(tmp["jump_url"] .. ngx.var.request_uri, 301)
    end
end

-- 去用户中心验证
local function requestUcenter(url)
    local data = "route=" .. string.lower(ngx.var.request_method) .."|".. ngx.var.uri
    local requestUrl = parse_url(url)
    local httpc = http.new()
    
    httpc:set_timeout(5000)
    local ok, err = httpc:connect(requestUrl.host, tonumber(requestUrl.port))
    if not ok then
        return nil, "failed to connect to " .. url .. ": " .. err
    end
	
    local originHeader = ngx.req.get_headers()
    local myHeader = {
        ["Host"] = requestUrl.host,
    }
    if originHeader["authorization"] ~= nil then
        myHeader["Authorization"] = originHeader["authorization"]
    end
    if originHeader["toketypes"] ~= nil then
        myHeader["TokeTypes"] = originHeader["toketypes"]
    end
    if originHeader["permission-mode"] ~= nil and originHeader["permission-from"] ~= nil then
        myHeader["Permission-Mode"] = originHeader["permission-mode"]
        myHeader["Permission-From"] = originHeader["permission-from"]
    end
    if requestUrl.query ~= nil then
        data = requestUrl.query .. "&" .. data
    end
	
    local res, err = httpc:request({
        method = "GET",
        path = requestUrl.path,
        query = data,
        headers = myHeader,
    })
    if not res then
        return nil, "failed request to " .. url .. ": " .. err
    end
    local response_body = res:read_body()
    if res.status ~= 200 then
        return responseFrontend(res.status, response_body)
    end
    return response_body, nil
    -- ok, err = httpc:set_keepalive(keepalive)
    -- if not ok then
        -- kong.log.err("failed keepalive for ", host, ":", tostring(port), ": ", err)
    -- end
end

-- 用rpc到用户中心
local function rpcUcenter(conf)
    local originHeader = ngx.req.get_headers()
    local data = {
        ["route"] = string.lower(ngx.var.request_method) .."|".. ngx.var.uri,
    }
    if originHeader["authorization"] ~= nil then
        data["auth"] = originHeader["authorization"]
    end
    if originHeader["toketypes"] ~= nil then
        data["toketypes"] = originHeader["toketypes"]
    end
    if originHeader["permission-mode"] ~= nil and originHeader["permission-from"] ~= nil then
        data["mode"] = originHeader["permission-mode"]
        data["from"] = originHeader["permission-from"]
    end
    if conf.del_cache ~= nil then
        data["del_cache"] = conf.del_cache
    end
    if conf.not_check ~= nil then
        data["not_check"] = conf.not_check
    end
    if conf.strip_path ~= nil then
        data["strip_path"] = conf.strip_path
    end
    data = {
        ["jsonrpc"] = "2.0",
        ["method"] = "UserInterface@checkUrl",
        ["params"] = {["data"] = data},
    }

    local c = rpc:new()
    return c:rpc_access(conf.host, conf.port, data)
end

-- 检查配置和请求
local function checkConfigReq(conf)
    local res = true
    local originHeader = ngx.req.get_headers()
    local path = string.sub(ngx.var.uri .. '/',1,5)
	
    if conf.ucenter_url == nil and (conf.host == nil or conf.port == nil) then
        res = false
    elseif path == '/api/' or path == '/get/' or path == '/doc/' or path == '/post' or string.find(ngx.var.uri,'.',1,true) ~= nil or ngx.var.uri == '/system/gen_routes' then
        res = false
    elseif originHeader["toketypes"] ~= nil and string.lower(originHeader["toketypes"]) == "virtual" then
        res = false
    end
    return res
end

--
-- 读取文件内容
local function readFile(name)
    local c = ''
    local f = io.open(name, "r")
    if f ~= nil then
        c = f:read("*a")
        io.close(f)
    end
    return c
end

-- 检查表中是否存在值
local function tableValueIn(tbl, value)
    if tbl == nil then
        return false
    end
	
    for k, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- 分割字符串转为数组
local function explode(delimiter, str)
    local list = {}
    for v in string.gmatch(str .. delimiter, "(.-)" .. delimiter) do
        table.insert(list, v)
    end
    return list
end

-- 检查api
local function checkMenuApi(conf)
    local originHeader = ngx.req.get_headers()
    if originHeader['permission-page'] ~= nil and conf.frontend_dir ~= nil then
        local list = explode(',', originHeader['permission-page'])
    	
        -- ngx.say("Error acquiring proxy information")
        if #list > 1 then
            local content = readFile(conf.frontend_dir .."/".. list[1] ..".json")
            if content ~= '' then
                local apiList = cjson.decode(content)
                if apiList ~= nil and not tableValueIn(apiList, list[2]) then
                    return responseFrontend(ngx.HTTP_UNAUTHORIZED,{ message = "No permission to access, url is not in the page"})
                end
            end
        end
    end
end

function MyAuthCheck:access(conf)
    MyAuthCheck.super.access(self)
    if ngx.var.request_method == "OPTIONS" then
        return responseFrontend(204, nil)
    end
	
    if checkConfigReq(conf) then
        -- checkMenuApi(conf)
        -- local body, err = requestUcenter(conf.ucenter_url)
        local body, err = rpcUcenter(conf)
        if type(err) ~= "nil" then
            return responseFrontend(500, { message = err })
        elseif body ~= "" then
            handleResponse(body, conf.jump_upstream)
        end
    end
end

return MyAuthCheck
