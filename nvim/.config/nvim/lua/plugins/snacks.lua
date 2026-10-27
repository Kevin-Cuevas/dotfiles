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
      bigfile = {
        enabled = true,
        size = 8 * 1024 * 1024, -- 8 MB
      },
    },
  },
}
