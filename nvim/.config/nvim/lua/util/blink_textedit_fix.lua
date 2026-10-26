-- Parche blink: rango tras soutv
local M = {}

function M.apply()
  local list = require("blink.cmp.sources.lib.provider.list")
  local text_edits = require("blink.cmp.lib.text_edits")

  local append = list.append
  function list:append(response)
    for _, item in ipairs(response.items or {}) do
      item.request_line = item.request_line or self.context.line
    end
    return append(self, response)
  end

  local get_from_item = text_edits.get_from_item
  text_edits.get_from_item = function(item)
    local edit = get_from_item(item)
    local raw = item.textEdit
    local old_line, old_col = item.request_line, item.cursor_column
    if not (raw and old_line and old_col) then
      return edit
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    if edit.range.start.line ~= row - 1 or edit.range["end"].line ~= row - 1 then
      return edit
    end

    -- inicio en bytes (petición)
    local raw_range = raw.range or raw.insert or raw.replace
    local enc = text_edits.offset_encoding_from_item(item)
    local ok, start = pcall(vim.str_byteindex, old_line, enc, raw_range.start.character, false)
    if not ok or start > old_col then
      return edit
    end

    local line = vim.api.nvim_get_current_line()
    if line:sub(1, start) == old_line:sub(1, start) then
      return edit -- nada cambió antes
    end

    -- palabra del cursor (+ `@`)
    local before = line:sub(1, col)
    local new_start = #before - #before:match("[%w_$]*$")
    local lead = (raw.newText or item.label or ""):match("^[^%w_$]*")
    if #lead > 0 and before:sub(new_start - #lead + 1, new_start) == lead then
      new_start = new_start - #lead
    end
    edit.range.start.character = new_start
    return edit
  end
end

return M
