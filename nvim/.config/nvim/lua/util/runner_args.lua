-- @args header of a file ==> what <leader>ra asks before running it (see
-- util/runner.lua). One line in the first 50, any comment style:
--
--   // @args category:hardware|cursos|software  limit:int=3  verbose?:bool  --port:number=3000
--
-- Each token is [--]name[?][:type][=default]:
--   type     string (default) | number | int | bool | a|b|c (choices, picked from a menu)
--   ?        optional: left empty it is not passed (a trailing positional is
--            dropped, one in the middle stays as '' so the rest keep their place)
--   =value   pre-filled when there is no memory of the last run ("quoted" if
--            it has spaces)
--   --name   flag: `--name value`, or just `--name` for a bool; always optional
-- Positionals go first, then flags. Every value is shell-escaped: spaces,
-- quotes or `$` reach the program as typed, never the shell.
-- Java in Maven/Gradle: exec.args / --args drop empty args, so an empty
-- optional in the middle shifts the rest there. Use a --flag for those.
local M = {}

local types = { string = true, number = true, int = true, bool = true }

-- Split on spaces outside quotes ==> `text="hola nord"` is one token; the
-- quotes go away (single or double, like the shell)
local function tokenize(spec)
  local tokens, cur, quote = {}, {}, nil
  for ch in spec:gmatch(".") do
    if quote then
      if ch == quote then
        quote = nil
      else
        table.insert(cur, ch)
      end
    elseif ch == '"' or ch == "'" then
      quote = ch
    elseif ch:match("%s") then
      if #cur > 0 then
        table.insert(tokens, table.concat(cur))
        cur = {}
      end
    else
      table.insert(cur, ch)
    end
  end
  if #cur > 0 then
    table.insert(tokens, table.concat(cur))
  end
  return tokens
end

local function parse_token(token)
  local flag, rest = token:match("^(%-%-)(.+)$")
  rest = rest or token
  local head, default = rest:match("^([^=]*)=(.*)$")
  head = head or rest
  local name, kind = head:match("^([^:]+):(.*)$")
  name, kind = name or head, kind or ""
  local optional = name:sub(-1) == "?"
  if optional then
    name = name:sub(1, -2)
  end

  local arg = { name = name, flag = flag ~= nil, optional = optional or flag ~= nil, default = default }
  if kind:find("|", 1, true) then
    arg.type, arg.choices = "choice", vim.split(kind, "|", { trimempty = true })
  else
    -- unknown types (old headers wrote anything there) behave as string
    arg.type = types[kind:lower()] and kind:lower() or "string"
  end
  return arg
end

-- @args of a file ==> list of { name, type, choices, default, optional, flag },
-- or nil when it has none
function M.parse(file)
  if vim.fn.filereadable(file) == 0 then
    return nil
  end
  for _, line in ipairs(vim.fn.readfile(file, "", 50)) do
    local spec = line:match("@args%s+(.+)")
    if spec then
      -- block comment closers are not args: /* @args a b */, <!-- @args a -->
      spec = spec:gsub("%s*%*/%s*$", ""):gsub("%s*%-%->%s*$", "")
      local args = {}
      for _, token in ipairs(tokenize(spec)) do
        table.insert(args, parse_token(token))
      end
      return #args > 0 and args or nil
    end
  end
  return nil
end

-- Why a value does not fit its arg ==> nil when it does
local function invalid(arg, v)
  if v == "" then
    return not arg.optional and "required" or nil
  elseif arg.type == "number" and not tonumber(v) then
    return "not a number"
  elseif arg.type == "int" and not v:match("^%-?%d+$") then
    return "not an integer"
  end
end

local function title(arg)
  return (arg.flag and "--" or "") .. arg.name:gsub("^%l", string.upper)
end

-- Ask one arg ==> menu for choices/bool (the preferred value on top, if any), a
-- prompt for the rest that asks again until the value is valid. `pos` is
-- "2/3". on_value(nil) when cancelled with <Esc>.
local function ask_one(arg, pos, preferred, on_value)
  if arg.type == "choice" or arg.type == "bool" then
    local items = arg.type == "bool" and { "yes", "no" } or vim.deepcopy(arg.choices)
    if arg.optional and arg.type == "choice" then
      table.insert(items, "(none)")
    end
    for i, it in ipairs(items) do
      if it == preferred or (preferred == "" and it == "(none)") then
        table.insert(items, 1, table.remove(items, i))
        break
      end
    end
    vim.ui.select(items, { prompt = string.format("%s (%s)", title(arg), pos) }, function(choice)
      if choice then
        on_value(choice == "(none)" and "" or choice)
      else
        on_value(nil)
      end
    end)
    return
  end

  local function prompt(default)
    local label = string.format(" %s [%s%s] (%s) ", title(arg), arg.type, arg.optional and "?" or "", pos)
    vim.ui.input({ prompt = label, default = default }, function(input)
      if not input then
        return on_value(nil)
      end
      input = vim.trim(input)
      local err = invalid(arg, input)
      if err then
        vim.notify(string.format("%s: %s", title(arg), err), vim.log.levels.WARN, { title = "Run System" })
        return prompt(input)
      end
      on_value(input)
    end)
  end
  prompt(preferred or "")
end

-- Shell args from the answers ==> argv string (escaped) + what the banner shows
-- (`category=hardware limit=3 --port=3000`)
function M.build(args, values)
  local q = vim.fn.shellescape
  local pos, argv, shown, flag_argv, flag_shown = {}, {}, {}, {}, {}
  for _, arg in ipairs(args) do
    local v = values[arg.name] or ""
    if not arg.flag then
      if arg.type == "bool" then
        v = v == "yes" and "true" or v == "no" and "false" or v
      end
      table.insert(pos, { name = arg.name, optional = arg.optional, v = v })
    elseif arg.type == "bool" then
      if v == "yes" then
        table.insert(flag_argv, "--" .. arg.name)
        table.insert(flag_shown, "--" .. arg.name)
      end
    elseif v ~= "" then
      table.insert(flag_argv, "--" .. arg.name .. " " .. q(v))
      table.insert(flag_shown, "--" .. arg.name .. "=" .. v)
    end
  end
  -- empty optionals at the end are dropped; in the middle they keep their place
  while #pos > 0 and pos[#pos].v == "" and pos[#pos].optional do
    table.remove(pos)
  end
  for _, p in ipairs(pos) do
    table.insert(argv, q(p.v))
    table.insert(shown, p.name .. "=" .. (p.v == "" and "''" or p.v))
  end
  return table.concat(vim.list_extend(argv, flag_argv), " "), table.concat(vim.list_extend(shown, flag_shown), " ")
end

-- Re-run with the last answers ==> no prompts: every arg takes its memory, else
-- its default. Only the ones left without a valid value get asked (a required
-- arg added to the header since the last run, or one whose type changed).
-- Same on_done as M.ask.
function M.reuse(args, last, on_done)
  last = type(last) == "table" and last or {}
  local values, missing = {}, {}
  for _, arg in ipairs(args) do
    local v = last[arg.name] or arg.default or ""
    if invalid(arg, v) then
      table.insert(missing, arg)
    else
      values[arg.name] = v
    end
  end
  local function finish()
    local argv, shown = M.build(args, values)
    on_done(argv, shown, values)
  end
  if #missing == 0 then
    return finish()
  end
  M.ask(missing, last, function(_, _, asked)
    for name, v in pairs(asked) do
      values[name] = v
    end
    finish()
  end)
end

-- Ask every arg in order ==> on_done(argv, shown, values) with values = { name
-- = raw answer } for the memory. `last` is that table from the previous run.
-- Nothing runs if any prompt is cancelled.
function M.ask(args, last, on_done)
  last = type(last) == "table" and last or {}
  local values = {}
  local function ask_next(i)
    if i > #args then
      local argv, shown = M.build(args, values)
      return on_done(argv, shown, values)
    end
    local arg = args[i]
    -- nil = nothing to prefer (no memory, no default): menus keep their order
    local preferred = last[arg.name] or arg.default
    ask_one(arg, i .. "/" .. #args, preferred, function(v)
      if v == nil then
        return -- <Esc>
      end
      values[arg.name] = v
      ask_next(i + 1)
    end)
  end
  ask_next(1)
end

return M
