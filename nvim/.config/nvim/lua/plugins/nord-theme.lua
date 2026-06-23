return {
  {
    "gbprod/nord.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("nord").setup({
        styles = {
          comments = { italic = true },
        },

        on_highlights = function(highlights, colors)
          -- 👇 Intenta detectar los nombres correctos del grupo
          -- Puedes ajustar esto si Snacks usa otro grupo

          -- Ejemplo 1: Si usa 'NonText'
          highlights.NonText = {
            fg = "#6C7680", -- gris más claro
          }

          -- Ejemplo 2: Si Snacks define algo como 'SnacksHidden'
          highlights.SnacksHidden = {
            fg = "#6C7680",
          }

          -- Ejemplo 3: Para comentarios más visibles también
          highlights.Comment = {
            fg = "#6C7680",
            italic = true,
          }
        end,
      })

      vim.cmd.colorscheme("nord")
    end,
  },
}
