-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- que todos los yanks usen el registro del sistema
vim.opt.clipboard = "unnamedplus"

-- forzar Neovim a usar OSC52 como provider sin TMUX
if vim.env.SSH_TTY then
  vim.g.clipboard = "osc52"
end
