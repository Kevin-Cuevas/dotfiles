-- Nord Aurora Pastel (light) -- formerly "Iceberg Light, Nord blues and grays":
-- Iceberg Light's structure with the original Nord Snow Storm background
-- (#eceff4) instead of Iceberg's darker one (#e8e9ec), and an almost
-- monochrome palette of Nord blues and grays (Frost 81a1c1/5e81ac/88c0d0/
-- 8fbcbb + Polar Night 3b4252/434c5e/4c566a), with red (bf616a) and green
-- (a3be8c) as the only exceptions.
-- terminal_color_* mirrors kitty's raw hex exactly (see below) so nvim's
-- embedded :terminal (prompt included) looks identical to a real kitty
-- window, ANSI chips included.
-- Later tweak: bg_alt/bg_highlight/border came calibrated for Iceberg's
-- darker background (#e8e9ec) -- against this paler one (#eceff4) they looked
-- like a box of a different color in NormalFloat/FloatBorder (the "frame" of
-- the Terminal panel on the Snacks dashboard, and the different background
-- of the :terminal buffer). Replaced by their canonical Nord equivalents
-- (Nord4 #d8dee9, Nord5 #e5e9f0).
-- "Snow Storm Ink": Nord's Frost/Aurora are made for a dark background; on
-- #eceff4 functions/types/strings sat at 1.7-2.3:1 (washed out) and comments
-- (6.4:1) read better than the code. Same hues, but darkened (lightness only)
-- to >= 4.6:1 (keywords 5.5:1), and comments lightened to 3.9:1 so they sit
-- below the code. The pastel lives in the surfaces (bg_alt, bg_highlight,
-- selection). Syntax only: terminal_color_* still matches kitty (there those
-- tones are also p10k/tmux badge backgrounds).
-- "Aurora Pastel": on top of Ink, three warm Nord Aurora tones come back,
-- darkened the same way (>= 4.6:1): purple (Nord15) for constants/booleans,
-- peach (Nord12) for numbers and amber (Nord13) for warnings. It breaks the
-- blue/gray/green/red-only rule on purpose: it tells more token types apart.

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
  fg = "#33374c",
  comment = "#6a7894", -- lightened Nord3: below the code
  -- Same as bg: used by NonText/Whitespace/VertSplit/etc, which stay
  -- invisible against the background (like nord.nvim in dark mode). Not to be
  -- confused with float_border below -- that's only the float's outline
  -- LINE, not its fill.
  border = "#eceff4",
  -- Subtle outline for floats: the float's background is still c.bg (no
  -- differently colored patch, that was the bug), but without any line the
  -- floating window's edge (e.g. the "Terminal" panel on the Snacks
  -- dashboard) can't be told apart from anything. Nord4, as subtle as
  -- before but now only on the outline, not filling the whole panel.
  float_border = "#d8dee9",
  -- Indent guides: Snacks links them to NonText, which here is c.border
  -- (= bg, invisible on purpose), so they vanished. Their own tone, subtle
  -- but visible (~1.8:1), like the NonText #6c7680 used in dark mode.
  guide = "#b8c0ce",

  -- Nord blue-gray (blue/blue2/cyan/teal/slate/ink, Frost/Polar Night) plus
  -- green (string), red (error) and Aurora's warm tones (purple/peach/amber,
  -- below), all darkened to read on #eceff4.
  blue = "#496e93", -- darkened Nord9: function, operator, links, field/property
  blue2 = "#446185", -- darkened Nord10: keyword/statement/label/tag (the strongest accent)
  cyan = "#357385", -- darkened Nord8: type/storageclass/alternate tag
  teal = "#457372", -- darkened Nord7: lighter secondary accent (builtins, constructor)
  slate = "#434c5e", -- constant/number (gray, not magenta)
  ink = "#3b4252", -- special/preproc/macro (darker gray)
  green = "#587341", -- darkened Nord14: string -- the only exception besides red
  red = "#b24852", -- darkened Nord11: error/exception -- the other exception
  purple = "#8b5c83", -- darkened Nord15: constant/boolean
  peach = "#a85237", -- darkened Nord12: number
  amber = "#8a6418", -- darkened Nord13: warning

  diff_add_bg = "#dee3de",
  diff_delete_bg = "#e2d5d9",
  diff_change_bg = "#d9dee6",
  diff_text_bg = "#dae3e8",
  search_bg = "#cad2de",
}

-- Neovim's embedded :terminal has its own ANSI palette, separate from
-- kitty's — without this, terminal buffers (e.g. the prompt shown inside
-- nvim's own terminal) fall back to Neovim's generic default colors instead
-- of matching kitty's light-theme.auto.conf. Raw hex, mirrored 1:1 from
-- light-theme.auto.conf.
vim.g.terminal_color_background = c.bg
vim.g.terminal_color_foreground = c.fg
vim.g.terminal_color_0 = "#3b4252"
vim.g.terminal_color_8 = "#434c5e"
vim.g.terminal_color_1 = "#bf616a"
vim.g.terminal_color_9 = "#bf616a"
vim.g.terminal_color_2 = "#a3be8c"
vim.g.terminal_color_10 = "#a3be8c"
vim.g.terminal_color_3 = "#8a6418"
vim.g.terminal_color_11 = "#a85237"
vim.g.terminal_color_4 = "#81a1c1"
vim.g.terminal_color_12 = "#5e81ac"
vim.g.terminal_color_5 = "#d8dee9"
vim.g.terminal_color_13 = "#8b5c83"
vim.g.terminal_color_6 = "#88c0d0"
vim.g.terminal_color_14 = "#8fbcbb"
vim.g.terminal_color_7 = "#d8dee9"
vim.g.terminal_color_15 = "#eceff4"

local hl = vim.api.nvim_set_hl

-- Base UI
hl(0, "Normal", { fg = c.fg, bg = c.bg })
hl(0, "NormalFloat", { fg = c.fg, bg = c.bg })
hl(0, "FloatBorder", { fg = c.float_border, bg = c.bg })
hl(0, "FloatTitle", { fg = c.blue2, bg = c.bg, bold = true })
hl(0, "ColorColumn", { bg = c.bg_alt })
hl(0, "Cursor", { fg = c.bg, bg = c.fg })
hl(0, "CursorLine", { bg = c.bg_highlight })
hl(0, "CursorLineNr", { fg = c.fg, bold = true })
hl(0, "LineNr", { fg = c.comment })
hl(0, "SignColumn", { fg = c.comment, bg = c.bg })
-- WinSeparator is the border of real splits (e.g. the "border top" Snacks
-- puts by default on windows like the terminal preview under the dashboard)
-- -- unlike c.border (which stays on NonText/Whitespace/etc, invisible on
-- purpose). In dark mode that border IS visible, so it uses the same tone as
-- FloatBorder, not the invisible one.
hl(0, "VertSplit", { fg = c.float_border })
hl(0, "WinSeparator", { fg = c.float_border })
hl(0, "Visual", { bg = c.bg_highlight })
hl(0, "VisualNOS", { bg = c.bg_highlight })
hl(0, "Search", { fg = c.fg, bg = c.search_bg })
hl(0, "IncSearch", { fg = c.bg, bg = c.blue2 })
hl(0, "CurSearch", { fg = c.bg, bg = c.blue2 })
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
hl(0, "WarningMsg", { fg = c.amber })
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
hl(0, "Constant", { fg = c.purple })
hl(0, "String", { fg = c.green })
hl(0, "Character", { fg = c.green })
hl(0, "Number", { fg = c.peach })
hl(0, "Boolean", { fg = c.purple })
hl(0, "Float", { fg = c.peach })
hl(0, "Identifier", { fg = c.fg })
hl(0, "Function", { fg = c.blue })
hl(0, "Statement", { fg = c.blue2, bold = true })
hl(0, "Conditional", { fg = c.blue2, bold = true })
hl(0, "Repeat", { fg = c.blue2, bold = true })
hl(0, "Label", { fg = c.blue2 })
hl(0, "Operator", { fg = c.blue })
hl(0, "Keyword", { fg = c.blue2, bold = true })
hl(0, "Exception", { fg = c.red, bold = true })
hl(0, "PreProc", { fg = c.ink })
hl(0, "Include", { fg = c.ink })
hl(0, "Define", { fg = c.ink })
hl(0, "Macro", { fg = c.ink })
hl(0, "PreCondit", { fg = c.ink })
hl(0, "Type", { fg = c.cyan })
hl(0, "StorageClass", { fg = c.cyan })
hl(0, "Structure", { fg = c.cyan })
hl(0, "Typedef", { fg = c.cyan })
hl(0, "Special", { fg = c.ink })
hl(0, "SpecialChar", { fg = c.teal })
hl(0, "Tag", { fg = c.blue2 })
hl(0, "Delimiter", { fg = c.comment })
hl(0, "SpecialComment", { fg = c.comment, italic = true })
hl(0, "Debug", { fg = c.red })
hl(0, "Underlined", { fg = c.blue, underline = true })
hl(0, "Ignore", { fg = c.border })
hl(0, "Error", { fg = c.red, bold = true })
hl(0, "Todo", { fg = c.fg, bg = c.search_bg, bold = true })

-- Treesitter (fall back cleanly to the base groups above via linking)
hl(0, "@variable", { link = "Identifier" })
hl(0, "@variable.builtin", { fg = c.blue2, italic = true })
hl(0, "@parameter", { fg = c.fg, italic = true })
hl(0, "@field", { fg = c.blue })
hl(0, "@property", { fg = c.blue })
hl(0, "@constructor", { fg = c.teal })
hl(0, "@constant", { link = "Constant" })
hl(0, "@constant.builtin", { fg = c.blue2, bold = true })
hl(0, "@string", { link = "String" })
hl(0, "@string.escape", { fg = c.ink })
hl(0, "@function", { link = "Function" })
hl(0, "@function.builtin", { fg = c.teal, italic = true })
hl(0, "@method", { link = "Function" })
hl(0, "@keyword", { link = "Keyword" })
hl(0, "@keyword.function", { fg = c.blue2, bold = true })
hl(0, "@keyword.return", { fg = c.blue2, bold = true })
hl(0, "@type", { link = "Type" })
hl(0, "@type.builtin", { fg = c.cyan, italic = true })
hl(0, "@namespace", { fg = c.cyan })
hl(0, "@module", { fg = c.cyan })
hl(0, "@attribute", { fg = c.ink })
hl(0, "@tag", { link = "Tag" })
hl(0, "@tag.attribute", { fg = c.blue })
hl(0, "@tag.delimiter", { fg = c.comment })
hl(0, "@punctuation.delimiter", { fg = c.comment })
hl(0, "@punctuation.bracket", { fg = c.fg })
hl(0, "@punctuation.special", { fg = c.ink })
hl(0, "@comment", { link = "Comment" })
hl(0, "@markup.heading", { fg = c.blue2, bold = true })
hl(0, "@markup.strong", { fg = c.fg, bold = true })
hl(0, "@markup.italic", { fg = c.fg, italic = true })
hl(0, "@markup.link", { fg = c.blue, underline = true })
hl(0, "@markup.link.url", { fg = c.blue, underline = true })
hl(0, "@markup.raw", { fg = c.cyan })
hl(0, "@markup.list", { fg = c.ink })

-- Diagnostics
hl(0, "DiagnosticError", { fg = c.red })
hl(0, "DiagnosticWarn", { fg = c.amber })
hl(0, "DiagnosticInfo", { fg = c.blue })
hl(0, "DiagnosticHint", { fg = c.cyan })
hl(0, "DiagnosticOk", { fg = c.green })
hl(0, "DiagnosticUnderlineError", { sp = c.red, underline = true })
hl(0, "DiagnosticUnderlineWarn", { sp = c.amber, underline = true })
hl(0, "DiagnosticUnderlineInfo", { sp = c.blue, underline = true })
hl(0, "DiagnosticUnderlineHint", { sp = c.cyan, underline = true })
hl(0, "DiagnosticVirtualTextError", { fg = c.red, bg = c.diff_delete_bg })
hl(0, "DiagnosticVirtualTextWarn", { fg = c.amber, bg = c.diff_text_bg })
hl(0, "DiagnosticVirtualTextInfo", { fg = c.blue, bg = c.diff_change_bg })
hl(0, "DiagnosticVirtualTextHint", { fg = c.cyan, bg = c.bg_alt })

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
-- hidden files: faint but visible (with c.border they took the background
-- color), like the dark theme's #6C7680
hl(0, "SnacksHidden", { fg = c.comment })
hl(0, "SnacksIndent", { fg = c.guide })
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
-- Same again for hidden/ignored entries in the explorer (".local-logs",
-- dotfiles, node_modules): PathHidden/PathIgnored link to NonText, so their
-- names took the background color and vanished.
-- Dimmer than c.comment (3.85:1) so they stand apart from regular entries and
-- the dir prefix; #939eb3 is 2.3:1 on bg, faint but still readable.
hl(0, "SnacksPickerPathHidden", { fg = "#939eb3" })
hl(0, "SnacksPickerPathIgnored", { fg = "#939eb3", italic = true })
