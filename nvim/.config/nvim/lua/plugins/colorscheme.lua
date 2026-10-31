-- SSH sessions have no DBus session forwarded, so the DBus portal query
-- that f-person/auto-dark-mode.nvim relies on errors out silently and
-- set_dark_mode/set_light_mode never get called again after the initial
-- fallback below. Instead of the portal, ask the terminal itself for its
-- background color via the OSC 11 escape sequence -- this travels through
-- the same pty/SSH channel as everything else nvim prints, so it works
-- transparently over SSH and is inherently scoped to *this* session's
-- terminal: two different users (or the same user in two SSH sessions)
-- each query their own kitty window, never each other's.
local function start_ssh_term_bg_sync(opts)
  local is_dark = nil -- nil = not yet known
  local query_in_flight = false
  local timer = vim.uv.new_timer()
  local notified = false -- a theme notification is waiting for its OSC 11

  local function apply(dark)
    local was_notified = notified
    notified = false
    if is_dark == dark then
      return
    end
    -- a notification followed by a real switch: the terminal pushes them,
    -- polling is no longer needed
    if was_notified and timer:is_active() then
      timer:stop()
    end
    is_dark = dark
    local set = dark and opts.set_dark_mode or opts.set_light_mode
    if vim.v.vim_did_enter == 1 then
      -- we're inside a TermResponse autocmd here, and autocmds don't nest:
      -- `:colorscheme` would skip every ColorScheme handler (lualine, snacks
      -- dashboard...), leaving e.g. a stale statusline strip. Outside it,
      -- they all run.
      vim.schedule(set)
    else
      set() -- startup: paint once, before the UI shows anything
    end
  end

  local function hi_byte(hex)
    return tonumber(hex:sub(1, 2), 16)
  end

  local function query()
    if query_in_flight then
      return
    end
    query_in_flight = true

    local group = vim.api.nvim_create_augroup("SshTermBgQuery", { clear = true })

    local timeout = vim.defer_fn(function()
      query_in_flight = false
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end, 500)

    -- Not `once`: other replies (DA1, a theme notification) can land first;
    -- wait for the OSC 11 one instead of giving up on whatever comes.
    vim.api.nvim_create_autocmd("TermResponse", {
      group = group,
      callback = function(ev)
        local seq = ev.data and ev.data.sequence or ""
        local r, g, b = seq:match("\027%]11;rgb:(%x+)/(%x+)/(%x+)")
        if not r then
          return
        end
        pcall(function()
          timeout:stop()
        end)
        query_in_flight = false
        pcall(vim.api.nvim_del_augroup_by_id, group)

        local lum = (0.299 * hi_byte(r) + 0.587 * hi_byte(g) + 0.114 * hi_byte(b)) / 255
        apply(lum < 0.5)
      end,
    })

    vim.api.nvim_ui_send("\027]11;?\027\\")
  end

  -- Resolve the real background before anything is painted, so startup
  -- applies a colorscheme exactly once instead of painting the fallback
  -- and immediately repainting with the corrected value a moment later.
  query()
  vim.wait(200, function()
    return is_dark ~= nil
  end, 10)
  if is_dark == nil then
    apply(opts.fallback ~= "light")
  end

  timer:start(opts.update_interval or 3000, opts.update_interval or 3000, vim.schedule_wrap(query))

  -- Theme change notifications (DEC mode 2031): kitty pushes one on every
  -- light/dark switch, and tmux 3.8 forwards it to panes that asked (local
  -- or remote tmux, as long as each one in the chain is 3.8+). So instead of
  -- asking every 500ms, subscribe and query only when it arrives; the first
  -- one followed by a real switch proves the chain works and stops the
  -- polling (see apply). Without a notifying terminal (Konsole, tmux < 3.8)
  -- nothing arrives and polling just stays.
  -- nvim 0.12 hands the reply to TermResponse as "\27[0n", dropping the
  -- "?997;1" (dark) / "?997;2" (light), so it is only a trigger and OSC 11
  -- still says which one; a full reply is used as is. "\27[0n" is also the
  -- plain DSR "ok" reply (nvim gets one at startup), hence stopping only
  -- after a switch, never on the trigger alone.
  local function subscribe(on)
    vim.api.nvim_ui_send(on and "\027[?2031h" or "\027[?2031l")
  end
  vim.api.nvim_create_autocmd("TermResponse", {
    group = vim.api.nvim_create_augroup("SshTermThemeNotify", { clear = true }),
    callback = function(ev)
      local seq = ev.data and ev.data.sequence or ""
      local mode = seq:match("^\027%[%?997;([12])n$")
      if not mode and seq ~= "\027[0n" then
        return
      end
      notified = true
      if mode then
        apply(mode == "1")
      else
        vim.schedule(query)
      end
    end,
  })
  -- the mode outlives nvim in the terminal: off on exit/suspend, or the
  -- shell would get "^[[?997;2n" typed at its prompt on the next switch
  vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, {
    callback = function()
      subscribe(false)
    end,
  })
  vim.api.nvim_create_autocmd("VimResume", {
    callback = function()
      subscribe(true)
      query()
    end,
  })
  subscribe(true)
end

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
      update_interval = 500,
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
      if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
        start_ssh_term_bg_sync(opts)
      else
        -- Nord dark is the safe baseline before detection even runs: if
        -- the portal query can't be reached at all, auto-dark-mode.nvim's
        -- query errors out and it silently never calls set_dark_mode/
        -- set_light_mode -- this stays the colorscheme instead of
        -- whatever lazy.nvim installed as its bootstrap default.
        opts.set_dark_mode()
        require("auto-dark-mode").setup(opts)
      end
    end,
  },

  -- dark theme (light one: colors/nord-snow-storm.lua)
  {
    "gbprod/nord.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      terminal_colors = true,
      styles = {
        comments = { italic = true },
      },
      -- lighter grey for hidden files (Snacks), NonText and comments
      on_highlights = function(highlights)
        highlights.NonText = { fg = "#6C7680" }
        highlights.SnacksHidden = { fg = "#6C7680" }
        highlights.Comment = { fg = "#6C7680", italic = true }
        -- dashboard banner in Nord frost, like dev-motd
        highlights.SnacksDashboardHeader = { fg = "#88C0D0", bold = true }
      end,
    },
  },
}
