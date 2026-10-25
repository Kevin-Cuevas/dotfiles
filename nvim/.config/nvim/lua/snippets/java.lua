local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node

-- Palabras que se parecen a un tipo pero no declaran una variable
local not_a_type = {
  ["return"] = true,
  ["else"] = true,
  ["new"] = true,
  ["throw"] = true,
  ["case"] = true,
  ["package"] = true,
  ["import"] = true,
  ["goto"] = true,
}

-- Nombre de la variable en una línea de declaración ==> string o nil
-- (int x = 1; | String s; | List<String> xs = ...; | for (int i = 0 | for (String s : xs))
local function declared_in(line)
  line = line:gsub("//.*$", ""):gsub("^%s*final%s+", "")
  local ty, name = line:match("^%s*for%s*%(%s*final%s+([%w_%.<>%[%]]+)%s+([%a_][%w_]*)%s*[=:]")
  if not name then
    ty, name = line:match("^%s*for%s*%(%s*([%w_%.<>%[%]]+)%s+([%a_][%w_]*)%s*[=:]")
  end
  if not name then
    ty, name = line:match("^%s*([%w_%.%[%]]+)%s+([%a_][%w_]*)%s*[=;]")
  end
  if not name then
    -- tipos con genéricos pueden llevar espacios: Map<String, Integer> m =
    ty, name = line:match("^%s*([%w_%.]+<.->[%[%]]*)%s+([%a_][%w_]*)%s*[=;]")
  end
  if name and not not_a_type[ty] then
    return name
  end
end

-- Última variable declarada por encima de la línea actual
local function last_variable()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, row - 1, false)
  for n = #lines, 1, -1 do
    local name = declared_in(lines[n])
    if name then
      return name
    end
  end
  return ""
end

-- Cabeceras que se parecen a un método pero son otra cosa
local not_a_method = {
  ["if"] = true,
  ["for"] = true,
  ["while"] = true,
  ["switch"] = true,
  ["catch"] = true,
  ["synchronized"] = true,
  ["return"] = true,
  ["new"] = true,
  ["try"] = true,
  ["else"] = true,
}

-- Nombre del método que envuelve la línea actual ==> string o ""
local function current_method()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, row, false)
  for n = #lines, 1, -1 do
    local line = lines[n]:gsub("//.*$", "")
    -- tipo de retorno (o modificador) + nombre + ( ... ), sin ';' al final
    local name = line:match("^%s*[%w_<>%[%]%.,%s]-%s([%a_][%w_]*)%s*%b()[%w_%s,]*{?%s*$")
    if not name then
      -- constructor: public Foo( ... ) {
      name = line:match("^%s*%a+%s+([%a_][%w_]*)%s*%b()[%w_%s,]*{?%s*$")
    end
    if name and not not_a_method[name] and not line:match("^%s*[%w_%.]+%s*%b();") then
      return name
    end
  end
  return ""
end

local function class_name()
  return vim.fn.expand("%:t:r")
end

return {
  -- soutv: System.out.println("x = " + x); con la última variable declarada
  s("soutv", {
    t('System.out.println("'),
    f(function(args)
      return args[1][1]
    end, { 1 }),
    t(' = " + '),
    d(1, function()
      return sn(nil, { i(1, last_variable()) })
    end),
    t(");"),
    i(0),
  }),

  -- soutm: System.out.println("Clase.metodo");
  s("soutm", {
    t('System.out.println("'),
    f(function()
      local m = current_method()
      return class_name() .. (m ~= "" and ("." .. m) or "")
    end),
    t('");'),
    i(0),
  }),

  -- soute: System.err.println("...");
  s("soute", {
    t('System.err.println("'),
    i(1),
    t('");'),
    i(0),
  }),
}
