return {
  {
    "saghen/blink.cmp",
    opts = {
      snippets = { preset = "luasnip" },
      completion = {
        -- the preview shares the menu's surface colour (see BlinkCmpDoc in both
        -- themes) and gets an outline: with Normal's bg and no border it looked
        -- like text floating over the buffer
        documentation = { window = { border = "rounded" } },
        menu = {
          draw = {
            -- kind name (Variable, Class...) at the right: the icon alone doesn't tell them apart
            columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "kind" } },
          },
        },
      },
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
