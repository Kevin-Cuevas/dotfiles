return {
  {
    "hat0uma/csvview.nvim",
    ft = { "csv", "tsv" },
    config = function()
      require("csvview").setup({
        parser = {
          -- evita bloquear el hilo principal en archivos grandes
          async = true,
          -- tamaño de chunks del parser asíncrono (ajusta si hay parpadeos)
          async_chunksize = 50,
          -- Delimitadores: prioridad por ft, luego fallbacks para auto-detección
          delimiter = {
            ft = {
              csv = ",",
              tsv = "\t",
            },
            fallbacks = { ",", "\t", ";", "|", ":" },
          },
          -- habilitar detección automática
          auto_detect = {
            enable = true,
            candidates = { ",", ";", "\t", "|" },
          },
          -- caracteres de quote por defecto
          quote_char = '"',
          -- líneas máximas para lookahead en campos multilínea
          max_lookahead = 50,
        },

        view = {
          -- display_mode puede ser "border" o "highlight"
          display_mode = "border",
          spacing = 2,
          min_column_width = 5,
          max_column_width = 50,

          -- forzar que la primera línea sea el header
          -- usa 1 para indicar la primera línea (1-based)
          header_lnum = 1,

          -- sticky header: clave correcta "enabled" y "separator"
          sticky_header = {
            enabled = true,
            separator = "─", -- o false para no mostrar separador
          },
        },

        highlight = {
          column = true,
          delimiter = true,
          comment = true,
        },

        navigation = {
          text_objects = true,
        },
      })
    end,

    cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },

    keys = {
      {
        "<leader>uv",
        "<cmd>CsvViewToggle<cr>",
        desc = "Toggle CSV View",
        ft = { "csv", "tsv" },
      },
    },

    init = function()
      -- Umbral para auto-activar la vista csv al abrir (evita hacerlo en CSV enormes)
      local MAX_AUTO_LINES = 1000

      vim.api.nvim_create_autocmd("BufReadPost", {
        pattern = { "*.csv", "*.tsv" },
        callback = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local ok, lines = pcall(vim.api.nvim_buf_line_count, bufnr)
          if not ok then
            return
          end

          if lines <= MAX_AUTO_LINES then
            -- auto-activa csvview para archivos pequeños/medianos
            -- (si prefieres NO auto-activar, comenta la siguiente línea)
            vim.cmd("CsvViewEnable")
          else
            vim.notify(
              string.format("Archivo CSV grande (%d líneas). Usa :CsvViewToggle para activar la vista.", lines),
              vim.log.levels.INFO
            )
          end
        end,
      })

      -- Opcional: si quieres que cambiar el tamaño de la ventana refresque el sticky header,
      -- descomenta el bloque siguiente.
      --
      -- vim.api.nvim_create_autocmd({ "VimResized", "WinResized", "BufWinEnter" }, {
      --   pattern = { "*.csv", "*.tsv" },
      --   callback = function()
      --     -- re-aplica la vista si está activa (ligero "refresh")
      --     -- Nota: CsvView no expone una API pública de refresh conocida en la doc,
      --     -- así que usamos comando seguro (no hará nada si no está activa).
      --     vim.cmd("silent! CsvViewDisable")
      --     vim.cmd("silent! CsvViewEnable")
      --   end,
      -- })
    end,
  },
}
