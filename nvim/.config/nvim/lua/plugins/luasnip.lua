-- LuaSnip ya viene del extra coding.luasnip; aquí solo lo propio
return {
  {
    "L3MON4D3/LuaSnip",
    opts = {
      update_events = { "TextChanged", "TextChangedI" },
    },
    config = function(_, opts)
      require("luasnip").setup(opts)
      require("luasnip.loaders.from_lua").lazy_load({
        paths = { vim.fn.stdpath("config") .. "/lua/snippets" },
      })
    end,
  },
}
