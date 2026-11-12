-- noice's "mini" view (LSP progress, short messages like the :w "written"
-- line) is a rectangular float as wide as its longest line, blended at 30%
-- by default: every code line under that rectangle looked dimmed, even far
-- from the actual text. Fully transparent background: only the message
-- characters cover the code.
-- Long messages (the full path in "file" 10L, 200B) also crossed the whole
-- screen: cap the width at 50% of the columns and wrap instead of cutting.
-- max_width must be a number (noice does math.min on it, "50%" errors), so it
-- is computed once at startup; wrap is required, noice defaults it to false.
return {
  "folke/noice.nvim",
  opts = {
    views = {
      mini = {
        size = { max_width = math.floor(vim.o.columns * 0.5) },
        win_options = { winblend = 100, wrap = true },
      },
    },
  },
}
