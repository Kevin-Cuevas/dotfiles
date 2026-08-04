return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 1000,
    dependencies = {
      "gbprod/nord.nvim",
    },
    opts = {
      update_interval = 3000,
      set_dark_mode = function()
        vim.o.background = "dark"
        vim.cmd.colorscheme("nord")
      end,
      set_light_mode = function()
        vim.o.background = "light"
        vim.cmd.colorscheme("nord-snow-storm")
      end,
    },
  },
}
