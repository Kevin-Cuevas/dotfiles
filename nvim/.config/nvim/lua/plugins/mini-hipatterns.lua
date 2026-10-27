return {
  "nvim-mini/mini.hipatterns",
  opts = function(_, opts)
    local hi = require("mini.hipatterns")

    -- Extender los highlighters existentes
    opts.highlighters = vim.tbl_extend("force", opts.highlighters or {}, {
      -- RGB colors: rgb(255, 0, 0)
      rgb = {
        pattern = "rgb%(%s*%d+%s*,%s*%d+%s*,%s*%d+%s*%)",
        group = function(_, match)
          local r, g, b = match:match("rgb%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)")
          return hi.compute_hex_color_group(string.format("#%02x%02x%02x", tonumber(r), tonumber(g), tonumber(b)), "bg")
        end,
      },

      -- RGBA colors: rgba(255, 0, 0, 0.5)
      rgba = {
        pattern = "rgba%(%s*%d+%s*,%s*%d+%s*,%s*%d+%s*,%s*[%d%.]+%s*%)",
        group = function(_, match)
          local r, g, b = match:match("rgba%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,")
          return hi.compute_hex_color_group(string.format("#%02x%02x%02x", tonumber(r), tonumber(g), tonumber(b)), "bg")
        end,
      },

      -- HSL colors: hsl(120, 100%, 50%)
      hsl = {
        pattern = "hsl%(%s*%d+%s*,%s*%d+%%%s*,%s*%d+%%%s*%)",
        group = function(_, match)
          local h, s, l = match:match("hsl%(%s*(%d+)%s*,%s*(%d+)%%%s*,%s*(%d+)%%%s*%)")
          -- Convertir HSL a RGB
          h, s, l = tonumber(h) / 360, tonumber(s) / 100, tonumber(l) / 100
          local function hsl_to_rgb(h, s, l)
            local r, g, b
            if s == 0 then
              r, g, b = l, l, l
            else
              local function hue_to_rgb(p, q, t)
                if t < 0 then
                  t = t + 1
                end
                if t > 1 then
                  t = t - 1
                end
                if t < 1 / 6 then
                  return p + (q - p) * 6 * t
                end
                if t < 1 / 2 then
                  return q
                end
                if t < 2 / 3 then
                  return p + (q - p) * (2 / 3 - t) * 6
                end
                return p
              end
              local q = l < 0.5 and l * (1 + s) or l + s - l * s
              local p = 2 * l - q
              r = hue_to_rgb(p, q, h + 1 / 3)
              g = hue_to_rgb(p, q, h)
              b = hue_to_rgb(p, q, h - 1 / 3)
            end
            return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
          end
          local r, g, b = hsl_to_rgb(h, s, l)
          return hi.compute_hex_color_group(string.format("#%02x%02x%02x", r, g, b), "bg")
        end,
      },

      -- HSLA colors: hsla(120, 100%, 50%, 0.5)
      hsla = {
        pattern = "hsla%(%s*%d+%s*,%s*%d+%%%s*,%s*%d+%%%s*,%s*[%d%.]+%s*%)",
        group = function(_, match)
          local h, s, l = match:match("hsla%(%s*(%d+)%s*,%s*(%d+)%%%s*,%s*(%d+)%%%s*,")
          h, s, l = tonumber(h) / 360, tonumber(s) / 100, tonumber(l) / 100
          local function hsl_to_rgb(h, s, l)
            local r, g, b
            if s == 0 then
              r, g, b = l, l, l
            else
              local function hue_to_rgb(p, q, t)
                if t < 0 then
                  t = t + 1
                end
                if t > 1 then
                  t = t - 1
                end
                if t < 1 / 6 then
                  return p + (q - p) * 6 * t
                end
                if t < 1 / 2 then
                  return q
                end
                if t < 2 / 3 then
                  return p + (q - p) * (2 / 3 - t) * 6
                end
                return p
              end
              local q = l < 0.5 and l * (1 + s) or l + s - l * s
              local p = 2 * l - q
              r = hue_to_rgb(p, q, h + 1 / 3)
              g = hue_to_rgb(p, q, h)
              b = hue_to_rgb(p, q, h - 1 / 3)
            end
            return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
          end
          local r, g, b = hsl_to_rgb(h, s, l)
          return hi.compute_hex_color_group(string.format("#%02x%02x%02x", r, g, b), "bg")
        end,
      },
    })

    return opts
  end,
}
