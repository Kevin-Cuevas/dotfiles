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

-- Watchers (live-server, vite, node --watch) ==> con backupcopy=auto nvim a veces
-- guarda renombrando: el archivo queda con otro inode, el watcher sigue mirando
-- el viejo y no recarga (o recarga dos veces). "yes" sobrescribe en el sitio.
-- Antes esto apagaba writebackup/swapfile con vim.opt en BufWritePre: esas
-- opciones son globales, así que el primer :w de un .js las apagaba en toda la
-- sesión (Java incluido). opt_local no sirve para ellas; backupcopy sí es local.
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
