return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    -- Machine name (hostname)
    local name = vim.uv.os_gethostname() or "HOST"

    -- Detect Termux (users starting with u0_a)
    if (vim.uv.os_get_passwd().username or ""):match("^u0_a%d+$") then
      name = "TERMUX"
    end

    -- Fonts from largest to smallest, in figlet/ (plain text if there's no toilet or none fits)
    local fonts_dir = vim.fn.stdpath("config") .. "/figlet"
    local fonts = { "ansi_shadow", "pagga", "future" }
    local has_toilet = vim.fn.executable("toilet") == 1
    local plain = { text = name, width = vim.fn.strdisplaywidth(name), height = 1 }

    -- Cache per font: { text, width, height }
    local banners = {}
    local function banner(font)
      if banners[font] == nil then
        banners[font] = false
        -- large -w so toilet doesn't split the name into several blocks
        local out = vim.system({ "toilet", "-d", fonts_dir, "-w", "999", "-f", font, name }, { text = true }):wait()
        if out.code == 0 and out.stdout ~= "" then
          local text = vim.trim(out.stdout)
          local lines = vim.split(text, "\n")
          local width = 0
          for _, line in ipairs(lines) do
            width = math.max(width, vim.fn.strdisplaywidth(line))
          end
          banners[font] = { text = text, width = width, height = #lines }
        end
      end
      return banners[font] or nil
    end

    -- Banners that fit the width, from largest to smallest
    local function candidates(width)
      local ret = {}
      if has_toilet then
        for _, font in ipairs(fonts) do
          local b = banner(font)
          if b and b.width <= width then
            ret[#ret + 1] = b
          end
        end
      end
      return ret
    end

    -- Layout that fits the height; degrades in order: gap 0, a shorter font,
    -- no startup and, last, the name in plain text
    local function fit(size, nkeys)
      local function rows(b, gap, startup)
        -- header + padding 2, keys + gaps + padding 1, startup
        return b.height + 2 + nkeys + gap * math.max(nkeys - 1, 0) + 1 + (startup and 1 or 0)
      end
      local banners_fit = candidates(size.width)
      for _, list in ipairs({ banners_fit, { plain } }) do
        for _, startup in ipairs({ true, false }) do
          for _, b in ipairs(list) do
            for _, gap in ipairs({ 1, 0 }) do
              if rows(b, gap, startup) <= size.height then
                return { banner = b, gap = gap, startup = startup }
              end
            end
          end
        end
      end
      return { banner = plain, gap = 0, startup = false }
    end

    opts.dashboard = opts.dashboard or {}
    opts.dashboard.enabled = true
    opts.dashboard.preset = opts.dashboard.preset or {}
    opts.dashboard.preset.header = name
    -- Normal menu width; in narrow windows it shrinks to the banner width
    local base_width = opts.dashboard.width or 60
    local min_width = 30

    -- Layout of the current render: the header decides it, keys and startup read it
    local layout = { gap = 1, startup = true }

    -- Replace header, keys and startup with sections recomputed on every render (resize included)
    opts.dashboard.sections = opts.dashboard.sections
      or { { section = "header" }, { section = "keys", gap = 1, padding = 1 }, { section = "startup" } }
    for i, section in ipairs(opts.dashboard.sections) do
      if type(section) == "table" and section.section == "header" then
        opts.dashboard.sections[i] = function(self)
          local size = self:size()
          local keys = self.opts.preset.keys
          layout = fit(size, type(keys) == "table" and #keys or 0)
          local b = layout.banner
          -- Resolved before the layout, so the new width applies to the current render
          if size.width < base_width + 10 then
            self.opts.width = math.min(base_width, size.width - 2, math.max(b.width, min_width))
          else
            self.opts.width = base_width
          end
          return { header = b.text, padding = 2 }
        end
      elseif type(section) == "table" and section.section == "keys" then
        opts.dashboard.sections[i] = function()
          return vim.tbl_extend("force", section, { gap = math.min(section.gap or 0, layout.gap) })
        end
      elseif type(section) == "table" and section.section == "startup" then
        opts.dashboard.sections[i] = function()
          return layout.startup and section or {}
        end
      end
    end
  end,
}
