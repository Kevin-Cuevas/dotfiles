return {
  "saghen/blink.cmp",
  opts = {
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
    },
    snippets = {
      preset = "luasnip", -- ← ESTO ES LO IMPORTANTE
    },
  },
}
