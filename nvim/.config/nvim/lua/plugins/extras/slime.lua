-- Manda bloques/selecciones de texto (SQL, lo que sea) a un pane de tmux
-- ya abierto (ej. corriendo mycli/pgcli), sin salir de neovim.
-- Requiere correr nvim dentro de una sesion de tmux.
return {
  "jpalardy/vim-slime",
  init = function()
    vim.g.slime_target = "tmux"
    vim.g.slime_default_config = {
      socket_name = "default",
      target_pane = "{last}", -- ultimo pane usado
    }
    vim.g.slime_dont_ask_default = 1
    vim.g.slime_bracketed_paste = 1 -- evita que mycli/pgcli interprete mal el paste
  end,
}
