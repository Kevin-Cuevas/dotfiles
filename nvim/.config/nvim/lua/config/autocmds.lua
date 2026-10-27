-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Para cuando se entra al terminal (incluye toggle)
vim.api.nvim_create_autocmd("TermEnter", {
  callback = function()
    vim.keymap.set("t", "<C-l>", "<C-l>", { buffer = true, silent = true })
  end,
})

vim.api.nvim_create_autocmd({ "BufWritePre" }, {
  pattern = { "*.html", "*.js", "*.css" },
  callback = function()
    vim.opt.backup = false
    vim.opt.writebackup = false
    vim.opt.swapfile = false
  end,
})
