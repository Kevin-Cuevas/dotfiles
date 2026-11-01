local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node

-- Words that look like a type but don't declare a variable
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

-- Variable name on a declaration line ==> string or nil
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
    -- generic types can contain spaces: Map<String, Integer> m =
    ty, name = line:match("^%s*([%w_%.]+<.->[%[%]]*)%s+([%a_][%w_]*)%s*[=;]")
  end
  if name and not not_a_type[ty] then
    return name
  end
end

-- Last variable declared above the current line
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

-- Headers that look like a method but are something else
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

-- Name of the method enclosing the current line ==> string or ""
local function current_method()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, row, false)
  for n = #lines, 1, -1 do
    local line = lines[n]:gsub("//.*$", "")
    -- return type (or modifier) + name + ( ... ), no ';' at the end
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
  -- soutv: System.out.println("x = " + x); with the last declared variable
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

  -- soutm: System.out.println("Class.method");
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
