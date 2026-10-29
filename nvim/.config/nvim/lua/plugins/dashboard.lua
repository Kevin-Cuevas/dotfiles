return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    -- Nombre de la máquina (hostname)
    local name = vim.uv.os_gethostname() or "HOST"

    -- Detectar si es Termux (usuarios que empiezan con u0_a)
    if (vim.uv.os_get_passwd().username or ""):match("^u0_a%d+$") then
      name = "TERMUX"
    end

    -- Fuentes de mayor a menor, en figlet/ (texto plano si no hay toilet o ninguna cabe)
    local fonts_dir = vim.fn.stdpath("config") .. "/figlet"
    local fonts = { "ansi_shadow", "pagga", "future" }
    local has_toilet = vim.fn.executable("toilet") == 1
    local plain = { text = name, width = vim.fn.strdisplaywidth(name), height = 1 }

    -- Cache por fuente: { text, width, height }
    local banners = {}
    local function banner(font)
      if banners[font] == nil then
        banners[font] = false
        -- -w grande para que toilet no parta el nombre en varios bloques
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

    -- Banners que caben a lo ancho, de mayor a menor
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

    -- Layout que cabe a lo alto; se degrada en orden: gap 0, fuente más baja,
    -- sin startup y, al final, el nombre en texto plano
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
    -- Ancho normal del menú; en ventanas angostas se encoge al ancho del banner
    local base_width = opts.dashboard.width or 60
    local min_width = 30

    -- Layout del render actual: lo decide el header y lo leen keys y startup
    local layout = { gap = 1, startup = true }

    -- Sustituir header, keys y startup por secciones que se recalculan en cada render (resize incluido)
    opts.dashboard.sections = opts.dashboard.sections
      or { { section = "header" }, { section = "keys", gap = 1, padding = 1 }, { section = "startup" } }
    for i, section in ipairs(opts.dashboard.sections) do
      if type(section) == "table" and section.section == "header" then
        opts.dashboard.sections[i] = function(self)
          local size = self:size()
          local keys = self.opts.preset.keys
          layout = fit(size, type(keys) == "table" and #keys or 0)
          local b = layout.banner
          -- Se resuelve antes del layout, así que el nuevo ancho aplica al render actual
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
