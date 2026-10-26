return {
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "java_class" },
        providers = {
          -- nombre del archivo en `public class |` (ver lua/util/blink_java_class.lua)
          java_class = {
            name = "JavaClass",
            module = "util.blink_java_class",
            score_offset = 100,
          },
        },
      },
      snippets = {
        preset = "luasnip",
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
