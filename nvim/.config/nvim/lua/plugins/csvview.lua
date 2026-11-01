return {
  {
    "hat0uma/csvview.nvim",
    ft = { "csv", "tsv" },
    config = function()
      require("csvview").setup({
        parser = {
          -- avoids blocking the main thread on large files
          async = true,
          -- chunk size of the async parser (tweak if there's flicker)
          async_chunksize = 50,
          -- Delimiters: priority by ft, then fallbacks for auto-detection
          delimiter = {
            ft = {
              csv = ",",
              tsv = "\t",
            },
            fallbacks = { ",", "\t", ";", "|", ":" },
          },
          -- enable auto-detection
          auto_detect = {
            enable = true,
            candidates = { ",", ";", "\t", "|" },
          },
          -- default quote characters
          quote_char = '"',
          -- max lookahead lines for multi-line fields
          max_lookahead = 50,
        },

        view = {
          -- display_mode can be "border" or "highlight"
          display_mode = "border",
          spacing = 2,
          min_column_width = 5,
          max_column_width = 50,

          -- force the first line to be the header
          -- use 1 to mean the first line (1-based)
          header_lnum = 1,

          -- sticky header: the right keys are "enabled" and "separator"
          sticky_header = {
            enabled = true,
            separator = "─", -- or false to show no separator
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
      -- Threshold to auto-enable the csv view on open (skips huge CSVs)
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
            -- auto-enables csvview for small/medium files
            -- (if you'd rather NOT auto-enable it, comment out the next line)
            vim.cmd("CsvViewEnable")
          else
            vim.notify(
              string.format("Large CSV file (%d lines). Use :CsvViewToggle to enable the view.", lines),
              vim.log.levels.INFO
            )
          end
        end,
      })

      -- Optional: if you want resizing the window to refresh the sticky header,
      -- uncomment the block below.
      --
      -- vim.api.nvim_create_autocmd({ "VimResized", "WinResized", "BufWinEnter" }, {
      --   pattern = { "*.csv", "*.tsv" },
      --   callback = function()
      --     -- re-applies the view if it's active (a light "refresh")
      --     -- Note: CsvView exposes no public refresh API documented in its docs,
      --     -- so we use a safe command (does nothing if it isn't active).
      --     vim.cmd("silent! CsvViewDisable")
      --     vim.cmd("silent! CsvViewEnable")
      --   end,
      -- })
    end,
  },
}
