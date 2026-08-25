return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 1000,
    dependencies = {
      "gbprod/nord.nvim",
    },
    opts = {
      fallback = "dark",
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
    config = function(_, opts)
      -- Nord dark is the safe baseline before detection even runs: if the
      -- portal query can't be reached at all (e.g. SSH into the home
      -- server with no DBus session forwarded), auto-dark-mode.nvim's
      -- query errors out and it silently never calls set_dark_mode/
      -- set_light_mode -- this stays the colorscheme instead of whatever
      -- lazy.nvim installed as its bootstrap default.
      opts.set_dark_mode()
      require("auto-dark-mode").setup(opts)
    end,
  },
}
