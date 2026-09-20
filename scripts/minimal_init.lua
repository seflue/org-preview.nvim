-- Test bootstrap: plugin on rtp, mini.nvim cloned into deps/ on first run.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local mini = root .. "/deps/mini.nvim"
if not vim.uv.fs_stat(mini) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/echasnovski/mini.nvim", mini })
end
vim.opt.rtp:prepend(mini)

require("mini.test").setup()
