local M = {}

function M.check()
  vim.health.start("org-preview")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim " .. tostring(vim.version()))
  else
    vim.health.error("Neovim >= 0.10 required (vim.system, vim.uv, vim.ui.open)")
  end

  local ok, backend = pcall(require("org-preview.backends").get, require("org-preview").opts.backend)
  if not ok then
    vim.health.error(tostring(backend))
  elseif backend.render then
    vim.health.ok("backend: custom render function")
  elseif vim.fn.executable(backend.cmd[1]) == 1 then
    vim.health.ok("backend: " .. backend.cmd[1] .. " found (" .. vim.fn.exepath(backend.cmd[1]) .. ")")
  else
    vim.health.error(
      "backend command not executable: " .. backend.cmd[1],
      { "Install " .. backend.cmd[1] .. " or configure another backend" }
    )
  end
end

return M
