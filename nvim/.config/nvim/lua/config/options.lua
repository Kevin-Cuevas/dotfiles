-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- make every yank use the system register
vim.opt.clipboard = "unnamedplus"

-- force Neovim to use OSC52 as the provider outside TMUX
if vim.env.SSH_TTY then
  vim.g.clipboard = "osc52"
end
