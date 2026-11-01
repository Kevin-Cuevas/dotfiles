-- Sends text blocks/selections (SQL, anything) to an already open tmux pane
-- (e.g. running mycli/pgcli), without leaving neovim.
-- Requires running nvim inside a tmux session.
return {
  "jpalardy/vim-slime",
  init = function()
    vim.g.slime_target = "tmux"
    vim.g.slime_default_config = {
      socket_name = "default",
      target_pane = "{last}", -- ultimo pane usado
    }
    vim.g.slime_dont_ask_default = 1
    vim.g.slime_bracketed_paste = 1 -- keeps mycli/pgcli from misreading the paste
  end,
}
