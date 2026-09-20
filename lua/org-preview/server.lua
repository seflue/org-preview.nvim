-- Minimal HTTP server on vim.uv: serves pages through an injected route
-- handler and keeps `GET /events` open as a Server-Sent Events stream.
-- Routing lives in the caller so new routes (e.g. following org links to
-- other files) can be added without touching this module.
--
-- Each TCP chunk is parsed as one request. Browsers on loopback send a GET
-- in a single packet, which is the only client this server is meant for.
local uv = vim.uv
local M = {}

local state = { srv = nil, clients = {}, last_msg = nil }

local function respond(c, status, ctype, body)
  if c:is_closing() then
    return
  end
  c:write(
    ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"):format(status, ctype, #body)
      .. body,
    function()
      c:close()
    end
  )
end

local function prune()
  for i = #state.clients, 1, -1 do
    if state.clients[i]:is_closing() then
      table.remove(state.clients, i)
    end
  end
end

local function on_request(c, req, handler)
  local path = req:match("^GET (%S+)")
  if not path then
    return respond(c, "400 Bad Request", "text/plain", "GET only")
  end
  -- Browsers request it on every page load; a 204 keeps the console clean.
  if path == "/favicon.ico" then
    if c:is_closing() then
      return
    end
    return c:write("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n", function()
      c:close()
    end)
  end
  if path == "/events" then
    c:write(
      "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
        .. "Cache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
    )
    prune()
    state.clients[#state.clients + 1] = c
    -- Replay the latest payload so a client that connects (or reconnects
    -- after a server restart) after the last push is not left empty.
    if state.last_msg then
      c:write(state.last_msg)
    end
    return
  end
  -- read_start runs in a fast event context where vim.api is forbidden;
  -- hop to the main loop so handlers may touch buffers.
  vim.schedule(function()
    local ok, body = pcall(handler, path)
    if not ok then
      vim.notify("org-preview: " .. tostring(body), vim.log.levels.ERROR)
      return respond(c, "500 Internal Server Error", "text/plain", "handler failed")
    end
    if not body then
      return respond(c, "404 Not Found", "text/plain", "not found")
    end
    respond(c, "200 OK", "text/html; charset=utf-8", body)
  end)
end

--- Start listening. handler(path) returns the HTML body or nil for 404.
--- port 0 lets the OS pick a free one. Returns the bound port, or nil plus
--- a message when the address cannot be bound.
---@param opts { host: string, port: integer, handler: fun(path: string): string|nil }
---@return integer|nil port, string|nil err
function M.start(opts)
  if state.srv then
    return state.srv:getsockname().port
  end
  local srv = uv.new_tcp()
  local ok, err = srv:bind(opts.host, opts.port)
  if ok then
    ok, err = srv:listen(16, function(lerr)
      if lerr then
        return
      end
      local c = uv.new_tcp()
      srv:accept(c)
      c:read_start(function(rerr, req)
        if rerr or not req then
          if not c:is_closing() then
            c:close()
          end
          return
        end
        on_request(c, req, opts.handler)
      end)
    end)
  end
  if not ok then
    srv:close()
    return nil, ("cannot listen on %s:%d: %s"):format(opts.host, opts.port, tostring(err))
  end
  state.srv = srv
  return srv:getsockname().port
end

--- Send one SSE message (JSON-encoded so multi-line HTML fits one data: line).
---@param payload string
function M.push(payload)
  prune()
  local msg = "data: " .. vim.json.encode(payload) .. "\n\n"
  state.last_msg = msg
  for _, c in ipairs(state.clients) do
    c:write(msg)
  end
end

function M.stop()
  for _, c in ipairs(state.clients) do
    if not c:is_closing() then
      c:close()
    end
  end
  state.clients = {}
  state.last_msg = nil
  if state.srv then
    state.srv:close()
    state.srv = nil
  end
end

function M.running()
  return state.srv ~= nil
end

return M
