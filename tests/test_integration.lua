local H = require("tests.helpers")
local eq = MiniTest.expect.equality
local child = H.new_child()
local PORT = 5612
local URL = "http://127.0.0.1:" .. PORT .. "/"

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- MiniTest.skip only takes effect inside pre_case or the case itself.
      if vim.fn.executable("pandoc") == 0 then
        MiniTest.skip("pandoc not installed")
      end
      H.restart(child)
      child.cmd("runtime plugin/org-preview.lua")
      child.lua(([[
        require('org-preview').setup({ open = false, port = %d, debounce_ms = 50 })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { '* First heading', 'Some text.' })
      ]]):format(PORT))
    end,
    post_case = function()
      child.lua("require('org-preview').stop()")
    end,
    post_once = child.stop,
  },
})

T["checkhealth runs without error"] = function()
  child.cmd("checkhealth org-preview")
  local text = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  eq(text:find("org-preview", 1, true) ~= nil, true)
  eq(text:find("ERROR", 1, true), nil)
end

T["user commands exist"] = function()
  eq(child.fn.exists(":OrgPreview"), 2)
  eq(child.fn.exists(":OrgPreviewStop"), 2)
end

T[":OrgPreview serves the rendered buffer"] = function()
  child.cmd("OrgPreview")
  local body, code
  vim.wait(3000, function()
    body, code = H.get(URL)
    return code == 200 and body:find("First heading", 1, true) ~= nil
  end)
  eq(code, 200)
  eq(body:find("<h1[^>]*>First heading") ~= nil, true)
  eq(body:find("water.css", 1, true) ~= nil, true)
  eq(body:find('<nav id="TOC"', 1, true) ~= nil, true)
  eq(body:find('href="#first-heading"', 1, true) ~= nil, true)
end

T["buffer edits re-render without saving"] = function()
  child.cmd("OrgPreview")
  vim.wait(500)
  child.lua([[vim.api.nvim_buf_set_lines(0, 0, 0, false, { '* Edited heading' })]])
  child.cmd("doautocmd TextChanged")
  local body
  vim.wait(3000, function()
    body = H.get(URL)
    return body:find("Edited heading", 1, true) ~= nil
  end)
  eq(body:find("<h1[^>]*>Edited heading") ~= nil, true)
end

T["reloading the file from disk re-renders"] = function()
  local path = vim.fn.tempname() .. ".org"
  child.cmd("write " .. path)
  child.cmd("OrgPreview")
  vim.wait(500)
  vim.fn.writefile({ "* Reloaded heading" }, path)
  child.cmd("edit!")
  local body
  vim.wait(3000, function()
    body = H.get(URL)
    return body:find("Reloaded heading", 1, true) ~= nil
  end)
  vim.fn.delete(path)
  eq(body:find("<h1[^>]*>Reloaded heading") ~= nil, true)
end

T["deleting the buffer stops the preview"] = function()
  child.cmd("OrgPreview")
  vim.wait(500)
  child.cmd("bdelete!")
  local code
  vim.wait(3000, function()
    _, code = H.get(URL)
    return code == 0
  end)
  eq(code, 0)
end

return T
