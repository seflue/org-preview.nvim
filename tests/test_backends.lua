local H = require("tests.helpers")
local eq = MiniTest.expect.equality
local backends = require("org-preview.backends")
local child = H.new_child()
local PORT = 5613
local URL = "http://127.0.0.1:" .. PORT .. "/"

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      H.restart(child)
    end,
    post_case = function()
      child.lua("require('org-preview').stop()")
    end,
    post_once = child.stop,
  },
})

T["unknown backend name errors with a clear message"] = function()
  MiniTest.expect.error(function()
    backends.get("nope")
  end, "unknown backend")
  MiniTest.expect.error(function()
    backends.get({})
  end, "unknown backend")
end

T["missing command is reported through the callback"] = function()
  local got
  backends.run({ cmd = { "org-preview-no-such-binary" } }, { "* x" }, function(html, err)
    got = { html, err }
  end)
  vim.wait(2000, function()
    return got ~= nil
  end)
  eq(got[1], nil)
  eq(got[2]:find("cannot run org-preview-no-such-binary", 1, true) ~= nil, true)
end

T["render-function backend serves its fragment end to end"] = function()
  child.lua(([[
    require('org-preview').setup({
      open = false, port = %d, debounce_ms = 50, css = { 'x.css' },
      backend = { render = function(lines, cb) cb('<p id="custom">' .. #lines .. ' lines</p>') end },
    })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a', 'b', 'c' })
    require('org-preview').start()
  ]]):format(PORT))
  local body, code
  vim.wait(3000, function()
    body, code = H.get(URL)
    return code == 200 and body:find("custom", 1, true) ~= nil
  end)
  eq(code, 200)
  eq(body:find('<p id="custom">3 lines</p>', 1, true) ~= nil, true)
  eq(body:find('<link rel="stylesheet" href="x.css">', 1, true) ~= nil, true)
end

T["automatic port is kept across stop/start and toggle"] = function()
  child.lua([[
    require('org-preview').setup({
      open = false, port = 0, backend = { render = function(_, cb) cb('<p>x</p>') end },
    })
    require('org-preview').start()
  ]])
  local url = child.lua_get("require('org-preview').url()")
  eq(url:match("^http://127%.0%.0%.1:(%d+)/$") ~= nil, true)
  eq(url:match(":0/$"), nil)
  child.lua("require('org-preview').stop()")
  child.lua("require('org-preview').start()")
  eq(child.lua_get("require('org-preview').url()"), url)
  child.lua("require('org-preview').toggle()") -- running -> stopped
  eq(child.lua_get("require('org-preview.server').running()"), false)
  child.lua("require('org-preview').toggle()") -- stopped -> running, same port
  eq(child.lua_get("require('org-preview').url()"), url)
  local body = H.get(url)
  eq(body:find("<p>x</p>", 1, true) ~= nil, true)
end

return T
