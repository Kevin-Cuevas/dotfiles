-- Fuente de blink.cmp: en `public class |` sugiere el nombre del archivo, que
-- en Java debe coincidir con el del tipo público. Se registra en
-- plugins/java.lua.
local source = {}

local kinds = "class|interface|enum|record"

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return vim.bo.filetype == "java"
end

function source:get_completions(ctx, callback)
  local empty = { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  -- solo tipos de primer nivel: sin sangría y con `public` (hasta `public final class`)
  local before = ctx.line:sub(1, ctx.cursor[2])
  local matched = false
  for kw in kinds:gmatch("[^|]+") do
    if before:match("^public%s+[%w%s]-" .. kw .. "%s+[%w_]*$") or before:match("^public%s+" .. kw .. "%s+[%w_]*$") then
      matched = true
      break
    end
  end
  local name = vim.fn.expand("%:t:r")
  if not matched or not name:match("^[%a_][%w_]*$") then
    return callback(empty)
  end

  callback({
    items = {
      {
        label = name,
        kind = vim.lsp.protocol.CompletionItemKind.Class,
        insertText = name,
        filterText = name,
        labelDetails = { description = "file name" },
        score_offset = 100,
      },
    },
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  })
  return function() end
end

return source
