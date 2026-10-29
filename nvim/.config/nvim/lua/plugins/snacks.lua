return {
  {
    "folke/snacks.nvim",
    opts = {
      notifier = {
        enabled = true,
        top_down = false, -- notifications grow from the bottom
      },
      -- images float in the top right corner, leaving the text free
      styles = {
        snacks_image = {
          relative = "editor",
          col = -1,
        },
      },
      image = {
        enabled = true,
        doc = {
          inline = false, -- only on hover, in a float
          float = true,
          max_width = 60,
          max_height = 25,
        },
      },
      -- explorer sidebar scales with the terminal: 30% of the columns,
      -- between 20 and the default 40 (resolved each time it opens)
      picker = {
        sources = {
          explorer = {
            layout = function()
              local width = math.min(40, math.max(20, math.floor(vim.o.columns * 0.3)))
              return { preset = "sidebar", preview = false, layout = { width = width, min_width = width } }
            end,
          },
        },
      },
      bigfile = {
        enabled = true,
        size = 8 * 1024 * 1024, -- 8 MB
      },
    },
  },
}
