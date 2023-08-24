-- rpc模块
require "lua_pack"
local bpack = string.pack
local bunpack = string.unpack
local cjson = require 'cjson'

local tcp = ngx.socket.tcp

local _M = {_VERSION = '0.1'}

local mt = { __index = _M }

function _M.new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end
    return setmetatable({ _sock = sock,}, mt)
end


function _M.set_timeout(self, timeout)
    local sock = rawget(self, "_sock")
    if not sock then
        error("not initialized", 2)
        return
    end

    sock:settimeout(timeout)
end


function _M.set_timeouts(self, connect_timeout, send_timeout, read_timeout)
    local sock = rawget(self, "_sock")
    if not sock then
        error("not initialized", 2)
        return
    end

    sock:settimeouts(connect_timeout, send_timeout, read_timeout)
end


function _M.connect(self, host, port_or_opts, opts)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    local unix

    do
        local typ = type(host)
        if typ ~= "string" then
            error("bad argument #1 host: string expected, got " .. typ, 2)
        end

        if string.sub(host, 1, 5) == "unix:" then
            unix = true
        end

        if unix then
            typ = type(port_or_opts)
            if port_or_opts ~= nil and typ ~= "table" then
                error("bad argument #2 opts: nil or table expected, got " .. typ, 2)
            end
        else
            typ = type(port_or_opts)
            if typ ~= "number" then
                port_or_opts = tonumber(port_or_opts)
                if port_or_opts == nil then
                    error("bad argument #2 port: number expected, got " .. typ, 2)
                end
            end

            if opts ~= nil then
                typ = type(opts)
                if typ ~= "table" then
                    error("bad argument #3 opts: nil or table expected, got " .. typ, 2)
                end
            end
        end

    end

    local ok, err

    if unix then
         -- second argument of sock:connect() cannot be nil
         if port_or_opts ~= nil then
             ok, err = sock:connect(host, port_or_opts)
             opts = port_or_opts
         else
             ok, err = sock:connect(host)
         end
    else
        ok, err = sock:connect(host, port_or_opts, opts)
    end

    if not ok then
        return ok, err
    end

    if opts and opts.ssl then
        ok, err = sock:sslhandshake(false, opts.server_name, opts.ssl_verify)
        if not ok then
            return ok, "failed to do ssl handshake: " .. err
        end
    end

    return ok, err
end


function _M.set_keepalive(self, ...)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function _M.get_reused_times(self)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end


function _M.close(self)
    local sock = rawget(self, "_sock")
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end

--
local function _gen_req(args)
    local data = cjson.encode(args)
    return bpack(">I>I", #data, 0) .. data
end

local function _handle_resp(data)
    local pos, size, dtype = bunpack(data, ">I>I")
    return size
end

local function _read_reply(sock)
    local header, err = sock:receive(8)
	if not header then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end
    local size = _handle_resp(header)
    if size < 0 then
        return nil
    end

    local data, err = sock:receive(size)
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    return data
end

function _M.rpc_access(self, host, port, args)
    local ok, err = self:connect(host, port)
    if not ok then
        return nil, "failed to connect: " .. err
    end
	
    local sock = rawget(self, "_sock")
    sock:settimeout(5000)

    local data = _gen_req(args)
    local bytes, err = sock:send(data)
	if not bytes then
        return nil, "failed to send: " ..err
    end
    local res, err = _read_reply(sock)
    --
    if not err then
        ok, err = sock:setkeepalive(180000, 8)
        if not ok then
            sock:close()
        end
    end

    return res, err
end

return _M