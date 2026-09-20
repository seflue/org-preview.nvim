local H = require("tests.helpers")
local eq = MiniTest.expect.equality
local child = H.new_child()
local PORT = 5611
local URL = "http://127.0.0.1:" .. PORT

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      H.restart(child)
      child.lua(([[
        _G.server = require('org-preview.server')
        server.start({ host = '127.0.0.1', port = %d, handler = function(path)
          if path == '/' then
            -- vim.api inside a handler must work (handlers run on the main loop)
            return '<p>' .. vim.fs.basename(vim.api.nvim_buf_get_name(0)) .. '</p>'
          elseif path == '/boom' then
            error('handler exploded')
          end
        end })
      ]]):format(PORT))
    end,
    post_case = function()
      child.lua("server.stop()")
    end,
    post_once = child.stop,
  },
})

T["GET / returns handler body, handler may use vim.api"] = function()
  child.cmd("file some.org")
  local body, code = H.get(URL .. "/")
  eq(code, 200)
  eq(body, "<p>some.org</p>")
end

T["unknown path is 404"] = function()
  local _, code = H.get(URL .. "/nope")
  eq(code, 404)
end

T["favicon is 204 without a body"] = function()
  local body, code = H.get(URL .. "/favicon.ico")
  eq(code, 204)
  eq(body, "")
end

T["push reaches an /events subscriber"] = function()
  local out = {}
  local proc = vim.system({ "curl", "-s", "-N", "-m", "3", URL .. "/events" }, { text = true }, function(r)
    out.stdout = r.stdout
  end)
  vim.wait(300)
  child.lua([[server.push('<p>x</p>\n<p>y</p>')]])
  vim.wait(4000, function()
    return out.stdout ~= nil
  end)
  proc:wait()
  eq(out.stdout:find('data: "<p>x</p>\\n<p>y</p>"\n\n', 1, true) ~= nil, true)
end

T["late /events subscriber gets the last push replayed"] = function()
  child.lua([[server.push('<p>late</p>')]])
  local body = H.get(URL .. "/events", { "-N" })
  eq(body:find('data: "<p>late</p>"\n\n', 1, true) ~= nil, true)
end

T["handler error yields 500, socket is not left open"] = function()
  local body, code = H.get(URL .. "/boom")
  eq(code, 500)
  eq(body, "handler failed")
end

T["port in use is reported, not raised"] = function()
  local res =
    child.lua_get(([[{ server.start({ host = '127.0.0.1', port = %d, handler = function() end }) }]]):format(PORT))
  eq(res, { PORT }) -- already running in this child: idempotent, reports its port
  local other = MiniTest.new_child_neovim()
  H.restart(other)
  local ok, err = unpack(
    other.lua_get(
      ([[{ require('org-preview.server').start({ host = '127.0.0.1', port = %d, handler = function() end }) }]]):format(
        PORT
      )
    )
  )
  other.stop()
  eq(ok, vim.NIL)
  eq(err:find("EADDRINUSE", 1, true) ~= nil, true)
end

T["port 0 binds a free port and reports it"] = function()
  child.lua("server.stop()")
  local port = child.lua_get([[server.start({ host = '127.0.0.1', port = 0, handler = function() return 'auto' end })]])
  eq(type(port), "number")
  eq(port > 0, true)
  local body = H.get("http://127.0.0.1:" .. port .. "/")
  eq(body, "auto")
end

T["stop frees the port for a restart"] = function()
  child.lua("server.stop()")
  eq(child.lua_get("server.running()"), false)
  child.lua(([[server.start({ host = '127.0.0.1', port = %d, handler = function() return 'again' end })]]):format(PORT))
  local body = H.get(URL .. "/")
  eq(body, "again")
end

return T
