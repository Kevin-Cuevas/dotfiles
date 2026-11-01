-- shfmt on save with the dotfiles' script style (Google Shell Style Guide):
-- 2 spaces, indented `case` (-ci) and |/&& at the start of the line when
-- wrapping (-bn). Without this conform only passes -i 2 and every save would
-- undo that formatting.
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
