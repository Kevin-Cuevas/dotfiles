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

    -- Cache por fuente: { text, width }
    local banners = {}
    local function banner(font)
      if banners[font] == nil then
        banners[font] = false
        -- -w grande para que toilet no parta el nombre en varios bloques
        local out = vim.system({ "toilet", "-d", fonts_dir, "-w", "999", "-f", font, name }, { text = true }):wait()
        if out.code == 0 and out.stdout ~= "" then
          local text = vim.trim(out.stdout)
          local width = 0
          for _, line in ipairs(vim.split(text, "\n")) do
            width = math.max(width, vim.fn.strdisplaywidth(line))
          end
          banners[font] = { text = text, width = width }
        end
      end
      return banners[font] or nil
    end

    -- Primera fuente que cabe en la ventana del dashboard
    local function header(width)
      if has_toilet then
        for _, font in ipairs(fonts) do
          local b = banner(font)
          if b and b.width <= width then
            return b.text, b.width
          end
        end
      end
      return name, vim.fn.strdisplaywidth(name)
    end

    opts.dashboard = opts.dashboard or {}
    opts.dashboard.enabled = true
    opts.dashboard.preset = opts.dashboard.preset or {}
    opts.dashboard.preset.header = name
    -- Ancho normal del menú; en ventanas angostas se encoge al ancho del banner
    local base_width = opts.dashboard.width or 60
    local min_width = 30

    -- Sustituir la sección header por una que se recalcula en cada render (resize incluido)
    opts.dashboard.sections = opts.dashboard.sections
      or { { section = "header" }, { section = "keys", gap = 1, padding = 1 }, { section = "startup" } }
    for i, section in ipairs(opts.dashboard.sections) do
      if type(section) == "table" and section.section == "header" then
        opts.dashboard.sections[i] = function(self)
          local win_width = self:size().width
          local text, width = header(win_width)
          -- Se resuelve antes del layout, así que el nuevo ancho aplica al render actual
          if win_width < base_width + 10 then
            self.opts.width = math.min(base_width, win_width - 2, math.max(width, min_width))
          else
            self.opts.width = base_width
          end
          return { header = text, padding = 2 }
        end
      end
    end
  end,
}
