-- Iceberg Light, azules y grises Nord -- estructura de Iceberg Light con el
-- fondo del Nord Snow Storm original (#eceff4) en vez del fondo mas oscuro
-- de Iceberg (#e8e9ec), y una paleta casi monocroma de azules y grises de
-- Nord (Frost 81a1c1/5e81ac/88c0d0/8fbcbb + Polar Night 3b4252/434c5e/
-- 4c566a), con rojo (bf616a) y verde (a3be8c) como unicas excepciones.
-- terminal_color_* mirrors kitty's raw hex exactly (see below) so nvim's
-- embedded :terminal (prompt included) looks identical to a real kitty
-- window, ANSI chips included.
-- Ajuste posterior: bg_alt/bg_highlight/border venian calibrados para el
-- fondo mas oscuro de Iceberg (#e8e9ec) -- contra este fondo mas palido
-- (#eceff4) se veian como un recuadro de otro color en NormalFloat/
-- FloatBorder (el "marco" del panel de Terminal en el dashboard de Snacks,
-- y el fondo distinto del buffer de :terminal). Reemplazados por sus
-- equivalentes Nord canonicos (Nord4 #d8dee9, Nord5 #e5e9f0).

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
  comment = "#4c566a",
  -- Igual al bg: usado por NonText/Whitespace/VertSplit/etc, que siguen
  -- invisibles contra el fondo (igual que nord.nvim en oscuro). No confundir
  -- con float_border de abajo -- eso es solo la LINEA del contorno del
  -- float, no el relleno.
  border = "#eceff4",
  -- Contorno sutil para el float: el fondo del float sigue siendo c.bg (sin
  -- parche de otro color, ese era el bug), pero sin ninguna linea el limite
  -- de la ventana flotante (ej. el panel "Terminal" del dashboard de Snacks)
  -- no se distingue de nada. Nord4, igual de sutil que antes pero ahora
  -- solo en el contorno, no rellenando todo el panel.
  float_border = "#d8dee9",

  -- Casi monocromo azul-gris Nord. blue/blue2/cyan/teal/slate/ink son todos
  -- de la familia Frost/Polar Night; green y red son las unicas excepciones
  -- (string y error/exception respectivamente).
  blue = "#81a1c1", -- funcion, operador, links, field/property
  blue2 = "#5e81ac", -- keyword/statement/label/tag (el acento mas fuerte)
  cyan = "#88c0d0", -- tipo/storageclass/tag alterno
  teal = "#8fbcbb", -- acento secundario mas claro (builtins, constructor)
  slate = "#434c5e", -- constante/numero (gris, no magenta)
  ink = "#3b4252", -- special/preproc/macro (gris mas oscuro)
  green = "#a3be8c", -- string -- unica excepcion junto al rojo
  red = "#bf616a", -- error/exception -- la otra excepcion

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
vim.g.terminal_color_3 = "#3b4252"
vim.g.terminal_color_11 = "#4c566a"
vim.g.terminal_color_4 = "#81a1c1"
vim.g.terminal_color_12 = "#5e81ac"
vim.g.terminal_color_5 = "#d8dee9"
vim.g.terminal_color_13 = "#434c5e"
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
-- WinSeparator es el borde de splits reales (ej. el "border top" que
-- Snacks le pone por defecto a ventanas como el preview de terminal debajo
-- del dashboard) -- distinto de c.border (que se queda en NonText/
-- Whitespace/etc, invisible a proposito). En oscuro ese borde SI se ve, asi
-- que usa el mismo tono que FloatBorder, no el invisible.
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
hl(0, "WarningMsg", { fg = c.ink })
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
hl(0, "Constant", { fg = c.slate })
hl(0, "String", { fg = c.green })
hl(0, "Character", { fg = c.green })
hl(0, "Number", { fg = c.slate })
hl(0, "Boolean", { fg = c.slate })
hl(0, "Float", { fg = c.slate })
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
hl(0, "DiagnosticWarn", { fg = c.ink })
hl(0, "DiagnosticInfo", { fg = c.blue })
hl(0, "DiagnosticHint", { fg = c.cyan })
hl(0, "DiagnosticOk", { fg = c.green })
hl(0, "DiagnosticUnderlineError", { sp = c.red, underline = true })
hl(0, "DiagnosticUnderlineWarn", { sp = c.ink, underline = true })
hl(0, "DiagnosticUnderlineInfo", { sp = c.blue, underline = true })
hl(0, "DiagnosticUnderlineHint", { sp = c.cyan, underline = true })
hl(0, "DiagnosticVirtualTextError", { fg = c.red, bg = c.diff_delete_bg })
hl(0, "DiagnosticVirtualTextWarn", { fg = c.ink, bg = c.diff_text_bg })
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
