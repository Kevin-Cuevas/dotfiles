-- auto-dark-mode.nvim (local sessions) queries the OS light/dark preference
-- via D-Bus (org.freedesktop.portal.Settings), which only exists on a
-- machine with an actual desktop session running — works great locally.
--
-- Over SSH, that query fails (no portal service on a headless host) and the
-- plugin just never fires. We first tried fixing this the same way the tmux
-- status bar was fixed over SSH (asking the terminal directly via an OSC 11
-- query, via OSC11.nvim), but tmux intercepts those queries, caches the
-- answer per attached client, and doesn't reliably forward/refresh it (see
-- tmux issue #3582) — it never actually reflected the live theme in
-- practice, even on a brand-new connection.
--
-- Instead, $NVIM_THEME is set by the ssh() wrapper in zsh/.zshrc right
-- before connecting — it queries the SAME D-Bus portal, but locally, where
-- it actually works — and forwarded over SSH via SendEnv (ssh/.ssh/config)
-- + AcceptEnv on the remote sshd. Deliberately a snapshot taken at connect
-- time, not a live follow like the local D-Bus polling: switching your
-- desktop theme mid-session won't retroactively update an already-open
-- remote nvim, you have to reconnect.
local in_ssh = vim.env.SSH_TTY ~= nil

local function set_dark()
  vim.o.background = "dark"
  vim.cmd.colorscheme("nord")
end

local function set_light()
  vim.o.background = "light"
  vim.cmd.colorscheme("nord-snow-storm")
end

return {
  -- LazyVim always runs its OWN `colorscheme` option (default: tokyonight)
  -- as part of its own init, unconditionally, AFTER every lazy=false
  -- plugin's config() has already run — so setting a colorscheme from a
  -- plain plugin config() gets clobbered no matter what scheduling trick
  -- you try. Overriding this option is the only reliable way to win the
  -- initial paint; it's LazyVim's own documented extension point for this.
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        if in_ssh and vim.env.NVIM_THEME == "light" then
          set_light()
        else
          set_dark()
        end
      end,
    },
  },
  {
    "gbprod/nord.nvim",
    lazy = false,
    priority = 1000,
  },
  -- Local sessions only: corrects the initial paint above to light, async,
  -- once the D-Bus query resolves (and again every update_interval after).
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
      set_dark_mode = set_dark,
      set_light_mode = set_light,
    },
  },
}
