return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
      -- HTML/CSS have no LazyVim extra: declaring them here makes Mason install
      -- them on any machine (installed by hand from :Mason they'd only exist
      -- on this one).
      servers = {
        html = {},
        cssls = {},
        emmet_language_server = {},
        -- From the lang.angular extra: without this it attaches to any .html in
        -- single-file mode (root nil) and adds nothing. Only with angular.json/nx.json.
        angularls = { workspace_required = true },
      },
    },
  },
}
