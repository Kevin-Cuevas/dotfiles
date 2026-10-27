return {
  {
    "saghen/blink.cmp",
    opts = {
      snippets = { preset = "luasnip" },
    },
  },

  -- ver util/blink_textedit_fix.lua
  {
    "saghen/blink.cmp",
    opts = function()
      require("util.blink_textedit_fix").apply()
    end,
  },
}
