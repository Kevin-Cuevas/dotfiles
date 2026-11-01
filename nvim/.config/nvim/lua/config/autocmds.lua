-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- For entering the terminal (toggle included)
vim.api.nvim_create_autocmd("TermEnter", {
  callback = function()
    vim.keymap.set("t", "<C-l>", "<C-l>", { buffer = true, silent = true })
  end,
})

-- Watchers (live-server, vite, node --watch) ==> with backupcopy=auto nvim
-- sometimes saves by renaming: the file ends up with another inode, the
-- watcher keeps watching the old one and doesn't reload (or reloads twice).
-- "yes" overwrites in place. This used to turn writebackup/swapfile off with
-- vim.opt in BufWritePre: those options are global, so the first :w of a .js
-- turned them off for the whole session (Java included). opt_local doesn't
-- work for them; backupcopy is buffer-local.
vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "html",
    "css",
    "scss",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "json",
  },
  callback = function()
    vim.opt_local.backupcopy = "yes"
  end,
})
