local H = {}

local child_args = { "-u", "scripts/minimal_init.lua", "--noplugin" }

function H.new_child()
  local child = MiniTest.new_child_neovim()
  child.restart(child_args)
  return child
end

function H.restart(child)
  child.restart(child_args)
end

--- Blocking HTTP GET from the test process (not the child).
---@return string body, integer code
function H.get(url, extra)
  local cmd = { "curl", "-s", "-m", "3", "-w", "\n%{http_code}" }
  vim.list_extend(cmd, extra or {})
  cmd[#cmd + 1] = url
  local r = vim.system(cmd, { text = true }):wait()
  local body, code = (r.stdout or ""):match("^(.*)\n(%d+)$")
  return body or "", tonumber(code) or 0
end

return H
