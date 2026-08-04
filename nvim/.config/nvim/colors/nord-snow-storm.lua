-- Nord "Snow Storm" (light ambiance), companion to nord.nvim for dark mode.
-- Nord has no official light variant; the Frost/Aurora accents here are the
-- same hues darkened to keep ~4.5:1 contrast on a light bg (mirrors the
-- same palette used in kitty's light-theme.auto.conf for consistency).

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") then
  vim.cmd("syntax reset")
end
vim.o.termguicolors = true
vim.o.background = "light"
vim.g.colors_name = "nord-snow-storm"

local c = {
  bg = "#eceff4",
  bg_alt = "#e5e9f0",
  bg_highlight = "#d8dee9",
  fg = "#2e3440",
  comment = "#4c566a",
  border = "#d8dee9",

  red = "#bb404c",
  orange = "#b04e2f",
  yellow = "#8e640f",
  green = "#56743c",
  teal = "#407473",
  cyan = "#2d7488",
  blue = "#436f9a",
  blue2 = "#486d9c",
  magenta = "#905986",

  diff_add_bg = "#dde5df",
  diff_delete_bg = "#e3d3d8",
  diff_change_bg = "#d9e1eb",
  diff_text_bg = "#e3ceca",
  search_bg = "#ebd8b0",
}

-- Neovim's embedded :terminal has its own ANSI palette, separate from
-- kitty's — without this, terminal buffers (e.g. the prompt shown inside
-- nvim's own terminal) fall back to Neovim's generic default colors instead
-- of matching kitty's light-theme.auto.conf. Same mapping, same hex values.
vim.g.terminal_color_background = c.bg
vim.g.terminal_color_foreground = c.fg
vim.g.terminal_color_0 = c.fg
vim.g.terminal_color_8 = c.comment
vim.g.terminal_color_1 = c.red
vim.g.terminal_color_9 = c.red
vim.g.terminal_color_2 = c.green
vim.g.terminal_color_10 = c.green
vim.g.terminal_color_3 = c.yellow
vim.g.terminal_color_11 = c.orange
vim.g.terminal_color_4 = c.blue
vim.g.terminal_color_12 = c.blue2
vim.g.terminal_color_5 = c.magenta
vim.g.terminal_color_13 = c.magenta
vim.g.terminal_color_6 = c.cyan
vim.g.terminal_color_14 = c.teal
vim.g.terminal_color_7 = c.border
vim.g.terminal_color_15 = "#f5f7fa"

local hl = vim.api.nvim_set_hl

-- Base UI
hl(0, "Normal", { fg = c.fg, bg = c.bg })
hl(0, "NormalFloat", { fg = c.fg, bg = c.bg_alt })
hl(0, "FloatBorder", { fg = c.border, bg = c.bg_alt })
hl(0, "FloatTitle", { fg = c.blue2, bg = c.bg_alt, bold = true })
hl(0, "ColorColumn", { bg = c.bg_alt })
hl(0, "Cursor", { fg = c.bg, bg = c.fg })
hl(0, "CursorLine", { bg = c.bg_alt })
hl(0, "CursorLineNr", { fg = c.fg, bold = true })
-- nord.nvim (dark) uses the "brightest" Polar Night shade here, not the
-- near-invisible border tone — mirror that with c.comment (still muted, but
-- clearly readable) instead of c.border.
hl(0, "LineNr", { fg = c.comment })
hl(0, "SignColumn", { fg = c.comment, bg = c.bg })
hl(0, "VertSplit", { fg = c.border })
hl(0, "WinSeparator", { fg = c.border })
hl(0, "Visual", { bg = c.bg_highlight })
hl(0, "VisualNOS", { bg = c.bg_highlight })
hl(0, "Search", { fg = c.fg, bg = c.search_bg })
hl(0, "IncSearch", { fg = c.bg, bg = c.orange })
hl(0, "CurSearch", { fg = c.bg, bg = c.orange })
hl(0, "MatchParen", { bg = c.bg_highlight, bold = true })
hl(0, "NonText", { fg = c.border })
hl(0, "EndOfBuffer", { fg = c.border })
hl(0, "Whitespace", { fg = c.border })
hl(0, "SpecialKey", { fg = c.border })
hl(0, "Folded", { fg = c.comment, bg = c.bg_alt })
hl(0, "FoldColumn", { fg = c.comment, bg = c.bg })
hl(0, "Directory", { fg = c.blue2 })
hl(0, "Title", { fg = c.blue2, bold = true })
hl(0, "ModeMsg", { fg = c.comment })
hl(0, "MoreMsg", { fg = c.green })
hl(0, "Question", { fg = c.blue2 })
hl(0, "WarningMsg", { fg = c.orange })
hl(0, "ErrorMsg", { fg = c.red, bold = true })
hl(0, "WildMenu", { fg = c.bg, bg = c.blue2 })
hl(0, "Pmenu", { fg = c.fg, bg = c.bg_alt })
hl(0, "PmenuSel", { fg = c.bg, bg = c.blue2, bold = true })
hl(0, "PmenuSbar", { bg = c.bg_alt })
hl(0, "PmenuThumb", { bg = c.comment })
hl(0, "StatusLine", { fg = c.fg, bg = c.bg_alt })
hl(0, "StatusLineNC", { fg = c.comment, bg = c.bg_alt })
hl(0, "TabLine", { fg = c.comment, bg = c.bg_alt })
hl(0, "TabLineFill", { bg = c.bg_alt })
hl(0, "TabLineSel", { fg = c.fg, bg = c.bg_highlight, bold = true })
hl(0, "WinBar", { fg = c.fg, bg = c.bg })
hl(0, "WinBarNC", { fg = c.comment, bg = c.bg })

-- Syntax
hl(0, "Comment", { fg = c.comment, italic = true })
hl(0, "Constant", { fg = c.magenta })
hl(0, "String", { fg = c.green })
hl(0, "Character", { fg = c.green })
hl(0, "Number", { fg = c.magenta })
hl(0, "Boolean", { fg = c.magenta })
hl(0, "Float", { fg = c.magenta })
hl(0, "Identifier", { fg = c.fg })
hl(0, "Function", { fg = c.cyan })
hl(0, "Statement", { fg = c.blue2, bold = true })
hl(0, "Conditional", { fg = c.blue2, bold = true })
hl(0, "Repeat", { fg = c.blue2, bold = true })
hl(0, "Label", { fg = c.blue2 })
hl(0, "Operator", { fg = c.blue })
hl(0, "Keyword", { fg = c.blue2, bold = true })
hl(0, "Exception", { fg = c.red, bold = true })
hl(0, "PreProc", { fg = c.orange })
hl(0, "Include", { fg = c.orange })
hl(0, "Define", { fg = c.orange })
hl(0, "Macro", { fg = c.orange })
hl(0, "PreCondit", { fg = c.orange })
hl(0, "Type", { fg = c.teal })
hl(0, "StorageClass", { fg = c.teal })
hl(0, "Structure", { fg = c.teal })
hl(0, "Typedef", { fg = c.teal })
hl(0, "Special", { fg = c.orange })
hl(0, "SpecialChar", { fg = c.orange })
hl(0, "Tag", { fg = c.blue2 })
hl(0, "Delimiter", { fg = c.comment })
hl(0, "SpecialComment", { fg = c.comment, italic = true })
hl(0, "Debug", { fg = c.red })
hl(0, "Underlined", { fg = c.blue, underline = true })
hl(0, "Ignore", { fg = c.border })
hl(0, "Error", { fg = c.red, bold = true })
hl(0, "Todo", { fg = c.yellow, bg = c.bg_alt, bold = true })

-- Treesitter (fall back cleanly to the base groups above via linking)
hl(0, "@variable", { link = "Identifier" })
hl(0, "@variable.builtin", { fg = c.blue2, italic = true })
hl(0, "@parameter", { fg = c.fg, italic = true })
hl(0, "@field", { fg = c.blue })
hl(0, "@property", { fg = c.blue })
hl(0, "@constructor", { fg = c.teal })
hl(0, "@constant", { link = "Constant" })
hl(0, "@constant.builtin", { fg = c.magenta, bold = true })
hl(0, "@string", { link = "String" })
hl(0, "@string.escape", { fg = c.orange })
hl(0, "@function", { link = "Function" })
hl(0, "@function.builtin", { fg = c.cyan, italic = true })
hl(0, "@method", { link = "Function" })
hl(0, "@keyword", { link = "Keyword" })
hl(0, "@keyword.function", { fg = c.blue2, bold = true })
hl(0, "@keyword.return", { fg = c.blue2, bold = true })
hl(0, "@type", { link = "Type" })
hl(0, "@type.builtin", { fg = c.teal, italic = true })
hl(0, "@namespace", { fg = c.teal })
hl(0, "@module", { fg = c.teal })
hl(0, "@attribute", { fg = c.orange })
hl(0, "@tag", { link = "Tag" })
hl(0, "@tag.attribute", { fg = c.blue })
hl(0, "@tag.delimiter", { fg = c.comment })
hl(0, "@punctuation.delimiter", { fg = c.comment })
hl(0, "@punctuation.bracket", { fg = c.fg })
hl(0, "@punctuation.special", { fg = c.orange })
hl(0, "@comment", { link = "Comment" })
hl(0, "@markup.heading", { fg = c.blue2, bold = true })
hl(0, "@markup.strong", { fg = c.fg, bold = true })
hl(0, "@markup.italic", { fg = c.fg, italic = true })
hl(0, "@markup.link", { fg = c.blue, underline = true })
hl(0, "@markup.link.url", { fg = c.blue, underline = true })
hl(0, "@markup.raw", { fg = c.teal })
hl(0, "@markup.list", { fg = c.orange })

-- Diagnostics
hl(0, "DiagnosticError", { fg = c.red })
hl(0, "DiagnosticWarn", { fg = c.orange })
hl(0, "DiagnosticInfo", { fg = c.blue })
hl(0, "DiagnosticHint", { fg = c.teal })
hl(0, "DiagnosticOk", { fg = c.green })
hl(0, "DiagnosticUnderlineError", { sp = c.red, underline = true })
hl(0, "DiagnosticUnderlineWarn", { sp = c.orange, underline = true })
hl(0, "DiagnosticUnderlineInfo", { sp = c.blue, underline = true })
hl(0, "DiagnosticUnderlineHint", { sp = c.teal, underline = true })
hl(0, "DiagnosticVirtualTextError", { fg = c.red, bg = c.diff_delete_bg })
hl(0, "DiagnosticVirtualTextWarn", { fg = c.orange, bg = c.diff_text_bg })
hl(0, "DiagnosticVirtualTextInfo", { fg = c.blue, bg = c.diff_change_bg })
hl(0, "DiagnosticVirtualTextHint", { fg = c.teal, bg = c.bg_alt })

-- Diff
hl(0, "DiffAdd", { bg = c.diff_add_bg })
hl(0, "DiffChange", { bg = c.diff_change_bg })
hl(0, "DiffDelete", { fg = c.comment, bg = c.diff_delete_bg })
hl(0, "DiffText", { bg = c.diff_text_bg, bold = true })

-- Git signs
hl(0, "GitSignsAdd", { fg = c.green })
hl(0, "GitSignsChange", { fg = c.blue })
hl(0, "GitSignsDelete", { fg = c.red })

-- LSP
hl(0, "LspReferenceText", { bg = c.bg_highlight })
hl(0, "LspReferenceRead", { bg = c.bg_highlight })
hl(0, "LspReferenceWrite", { bg = c.bg_highlight })
hl(0, "LspCodeLens", { fg = c.comment })
hl(0, "LspInlayHint", { fg = c.comment, bg = c.bg_alt, italic = true })

-- blink.cmp
hl(0, "BlinkCmpMenu", { link = "Pmenu" })
hl(0, "BlinkCmpMenuBorder", { link = "FloatBorder" })
hl(0, "BlinkCmpMenuSelection", { link = "PmenuSel" })
hl(0, "BlinkCmpDoc", { link = "NormalFloat" })
hl(0, "BlinkCmpDocBorder", { link = "FloatBorder" })

-- snacks.nvim
hl(0, "SnacksHidden", { fg = c.border })
hl(0, "SnacksDashboardHeader", { fg = c.blue2, bold = true })
hl(0, "SnacksDashboardDesc", { fg = c.fg })
hl(0, "SnacksDashboardFooter", { fg = c.comment, italic = true })
-- Untracked/ignored default to linking at "NonText", which is deliberately
-- near-invisible here for eob tildes/whitespace — wrong for file names.
hl(0, "SnacksPickerGitStatusUntracked", { fg = c.comment })
hl(0, "SnacksPickerGitStatusIgnored", { fg = c.comment, italic = true })
-- Same "NonText" default problem for the dir-prefix shown before filenames
-- in pickers (e.g. "scripts/" before "script.js").
hl(0, "SnacksPickerDir", { fg = c.comment })
