if vim.g.loaded_org_preview then
  return
end
vim.g.loaded_org_preview = true

vim.api.nvim_create_user_command("OrgPreview", function()
  require("org-preview").start()
end, { desc = "Live-preview the current org buffer in the browser" })

vim.api.nvim_create_user_command("OrgPreviewToggle", function()
  require("org-preview").toggle()
end, { desc = "Start or stop the org preview" })

vim.api.nvim_create_user_command("OrgPreviewStop", function()
  require("org-preview").stop()
end, { desc = "Stop the org preview server" })
