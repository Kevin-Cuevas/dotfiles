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

  local function apply(dark)
    if is_dark == dark then
      return
    end
    is_dark = dark
    if dark then
      opts.set_dark_mode()
    else
      opts.set_light_mode()
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

    vim.api.nvim_create_autocmd("TermResponse", {
      group = group,
      once = true,
      callback = function(ev)
        pcall(function()
          timeout:stop()
        end)
        query_in_flight = false

        local seq = ev.data and ev.data.sequence or ""
        local r, g, b = seq:match("\027%]11;rgb:(%x+)/(%x+)/(%x+)")
        if not r then
          return
        end

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

  local timer = vim.uv.new_timer()
  timer:start(opts.update_interval or 3000, opts.update_interval or 3000, vim.schedule_wrap(query))
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
}
