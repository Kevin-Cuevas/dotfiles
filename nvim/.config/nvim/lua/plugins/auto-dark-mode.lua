-- auto-dark-mode.nvim (local sessions) queries the OS light/dark preference
-- via D-Bus (org.freedesktop.portal.Settings), which only exists on a
-- machine with an actual desktop session running. Over SSH into a headless
-- host, that query errors (no portal service), parse_query_response returns
-- nil, and the plugin silently never fires — nvim ends up with no explicit
-- colorscheme at all, not just "the wrong one."
--
-- OSC11.nvim (SSH sessions) fixes this the same way we fixed tmux's status
-- bar over SSH: instead of asking the (remote) OS what theme it's in, it
-- asks the actual terminal doing the rendering — kitty, at the far end of
-- however many SSH/tmux hops — for its live background color via an OSC 11
-- query, which nvim already sends natively; the plugin just listens for the
-- response. Requires tmux's `allow-passthrough on` (already set, for
-- LazyVim's image support).
local in_ssh = vim.env.SSH_TTY ~= nil

return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 1000,
    cond = not in_ssh,
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
  {
    "afonsofrancof/OSC11.nvim",
    lazy = false,
    priority = 1000,
    cond = in_ssh,
    dependencies = {
      "gbprod/nord.nvim",
    },
    config = function()
      -- Sane default before the terminal answers the OSC 11 query (the
      -- plugin's own recommendation) — avoids a flash of nvim's unstyled
      -- built-in colors between startup and the first TermResponse.
      vim.o.background = "dark"
      vim.cmd.colorscheme("nord")

      require("osc11").setup({
        on_dark = function()
          vim.o.background = "dark"
          vim.cmd.colorscheme("nord")
        end,
        on_light = function()
          vim.o.background = "light"
          vim.cmd.colorscheme("nord-snow-storm")
        end,
      })
    end,
  },
}
