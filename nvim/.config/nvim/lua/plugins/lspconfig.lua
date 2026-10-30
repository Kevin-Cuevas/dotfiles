return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
      -- HTML/CSS no tienen extra de LazyVim: declararlos aquí hace que Mason
      -- los instale en cualquier máquina (instalados a mano desde :Mason solo
      -- existirían en esta).
      servers = {
        html = {},
        cssls = {},
        emmet_language_server = {},
        -- Del extra lang.angular: sin esto se conecta a cualquier .html en modo
        -- archivo suelto (root nil) y no aporta nada. Solo con angular.json/nx.json.
        angularls = { workspace_required = true },
      },
    },
  },
}
