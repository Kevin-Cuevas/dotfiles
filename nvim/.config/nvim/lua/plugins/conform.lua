-- shfmt al guardar con el estilo de los scripts de los dotfiles (Google Shell
-- Style Guide): 2 espacios, `case` indentado (-ci) y |/&& al inicio de la
-- línea cuando se parte (-bn). Sin esto conform solo le pasa -i 2 y cada
-- guardado desharía ese formato.
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        shfmt = { prepend_args = { "-i", "2", "-ci", "-bn" } },
      },
    },
  },
}
