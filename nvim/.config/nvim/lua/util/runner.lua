-- File runner for <leader>rr / <leader>ra (keys in plugins/terminal.lua) ==>
-- builds the shell command per extension and opens a floating Snacks terminal.
local M = {}

-- Detect Java build system ==> Maven/Gradle/Plain
local function detect_java_project_type(dir)
  local current_dir = dir
  while current_dir ~= "/" and current_dir ~= "" do
    if vim.fn.filereadable(current_dir .. "/pom.xml") == 1 then
      return "maven", current_dir
    end
    if
      vim.fn.filereadable(current_dir .. "/build.gradle") == 1
      or vim.fn.filereadable(current_dir .. "/build.gradle.kts") == 1
    then
      return "gradle", current_dir
    end
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end
  return "plain", dir
end

-- Detect Rust ==> check for Cargo.toml
local function detect_cargo_project(dir)
  local current_dir = dir
  while current_dir ~= "/" and current_dir ~= "" do
    if vim.fn.filereadable(current_dir .. "/Cargo.toml") == 1 then
      return true, current_dir
    end
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end
  return false, dir
end

local java_types = {
  class_declaration = true,
  record_declaration = true,
  enum_declaration = true,
  interface_declaration = true,
}

-- Java main() methods of a file, via treesitter ==> list of { class, first, last }:
-- binary class name (pkg.Outer$Inner) and the 0-based rows of that class.
local function java_mains(file)
  local src = table.concat(vim.fn.readfile(file), "\n")
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "java")
  if not ok then
    return {}
  end
  local root = parser:parse()[1]:root()
  local text = function(node)
    return vim.treesitter.get_node_text(node, src)
  end

  local pkg = ""
  local mains = {}
  local function visit(node)
    local t = node:type()
    if t == "package_declaration" then
      for child in node:iter_children() do
        if child:type() == "scoped_identifier" or child:type() == "identifier" then
          pkg = text(child) .. "."
        end
      end
    elseif t == "method_declaration" then
      local name, mods = node:field("name")[1], node:child(0)
      local params = text(node:field("parameters")[1]):gsub("%s", "")
      local is_main = name
        and text(name) == "main"
        and node:field("type")[1]:type() == "void_type"
        and mods:type() == "modifiers"
        and text(mods):find("public")
        and text(mods):find("static")
        and (
          params:match("^%(String%[%][%w_$]+%)$")
          or params:match("^%(String%.%.%.[%w_$]+%)$")
          or params:match("^%(String[%w_$]+%[%]%)$")
        )
      if is_main then
        -- enclosing types up to the file; skip anonymous/local classes
        local names, cls, p = {}, nil, node:parent()
        while p do
          local pt = p:type()
          if pt == "block" or pt == "object_creation_expression" then
            return
          end
          if java_types[pt] then
            cls = cls or p
            table.insert(names, 1, text(p:field("name")[1]))
          end
          p = p:parent()
        end
        if cls then
          local first, _, last = cls:range()
          table.insert(mains, { class = pkg .. table.concat(names, "$"), first = first, last = last })
        end
      end
      return
    end
    for child in node:iter_children() do
      visit(child)
    end
  end
  visit(root)
  return mains
end

-- Main class to run from a file ==> like IntelliJ: the class under the cursor
-- (innermost), else the only one. Returns class, or nil + all mains (0 or >1).
local function detect_main_class(file, row)
  local mains = java_mains(file)
  if row then
    local best
    for _, m in ipairs(mains) do
      if row >= m.first and row <= m.last and (not best or m.first >= best.first) then
        best = m
      end
    end
    if best then
      return best.class
    end
  end
  if #mains == 1 then
    return mains[1].class
  end
  return nil, mains
end

local function check_gradle_application_plugin(project_root)
  local gradle_files = { project_root .. "/build.gradle", project_root .. "/build.gradle.kts" }
  for _, gradle_file in ipairs(gradle_files) do
    if vim.fn.filereadable(gradle_file) == 1 then
      local content = table.concat(vim.fn.readfile(gradle_file), "\n")
      if string.find(content, "application") or string.find(content, "java%-application") then
        return true
      end
    end
  end
  return false
end

-- Major version of the `java` on PATH (8, 17, 25...) ==> nil if there is none
local function java_major()
  if vim.fn.executable("java") == 0 then
    return nil
  end
  local out = vim.fn.systemlist({ "java", "-version" })
  local v = out[1] and out[1]:match('version "([^"]+)"')
  return v and tonumber(v:match("^1%.(%d+)") or v:match("^(%d+)")) or nil
end

-- Main class of the project when the current file has no main() ==> returns
-- class [, file] or nil + candidates. Order: pom/gradle config, then the only
-- class with main() under src/main/java (or next to the file for plain Java).
local function find_project_main(p_type, root, dir)
  if p_type ~= "plain" then
    local builds = p_type == "maven" and { "pom.xml" } or { "build.gradle", "build.gradle.kts" }
    for _, name in ipairs(builds) do
      local path = root .. "/" .. name
      if vim.fn.filereadable(path) == 1 then
        local content = table.concat(vim.fn.readfile(path), "\n")
        local cfg = content:match("<main%.class>%s*([%w%._$]+)%s*</main%.class>")
          or content:match("<mainClass>%s*([%w%._$]+)%s*</mainClass>")
          or content:match("mainClass%a*[%s=%.%(a-z]*[\"']([%w%._$]+)[\"']")
        if cfg then
          return cfg
        end
      end
    end
  end
  local files = p_type == "plain" and vim.fn.glob(dir .. "/*.java", false, true)
    or vim.fn.globpath(root .. "/src/main/java", "**/*.java", false, true)
  local candidates = {}
  for _, f in ipairs(files) do
    for _, m in ipairs(java_mains(f)) do
      table.insert(candidates, { class = m.class, file = f })
    end
  end
  if #candidates == 1 then
    return candidates[1].class, candidates[1].file
  end
  return nil, nil, candidates
end

-- Prefix that points Maven/Gradle at the JDK the project asks for ==> the same
-- one jdtls picks (see util/jdks.lua), not whatever `java` the terminal has.
-- Empty when the project does not say or no suitable JDK is installed.
-- Returns prefix, major of the JDK that will run (the terminal's when no prefix).
local function jdk_prefix(p_type, root)
  local jdks = require("util.jdks")
  local want = jdks.target_release(p_type, root)
  if not want then
    return "", java_major()
  end
  local path, major = jdks.for_target(want)
  if not path then
    vim.notify(
      string.format("No JDK >= %d installed, using the terminal's java", want),
      vim.log.levels.WARN,
      { title = "Run System" }
    )
    return "", java_major()
  end
  return string.format('export JAVA_HOME=%s && export PATH="$JAVA_HOME/bin:$PATH" && ', vim.fn.shellescape(path)), major
end

-- Shell command to run a Java file ==> Maven | Gradle | plain. Returns
-- cmd, kind ("Maven" | "Gradle" | "Plain"), jdk (major it runs on, or nil), or
-- nil + reason when there is nothing to run, or nil + list of classes to pick
-- from. `args_str`, `row` (cursor, 0-based) and `main` (picked class) are optional.
local function java_run_cmd(file, dir, args_str, row, main)
  local sh = vim.fn.shellescape
  local has_args = args_str and args_str ~= ""
  local p_type, p_root = detect_java_project_type(dir)
  local main_file, in_file = file, nil
  if not main then
    main, in_file = detect_main_class(file, row)
  end
  if not main and #in_file > 1 then
    return nil, vim.tbl_map(function(m)
      return m.class
    end, in_file)
  end
  if not main then
    local candidates
    main, main_file, candidates = find_project_main(p_type, p_root, dir)
    if not main then
      return nil,
        (candidates and #candidates > 1) and "No main() here and several in the project: open the one to run"
          or "No main() in this file and no project main class found"
    end
  end

  local arg_s = has_args and (" " .. args_str) or ""
  if p_type == "maven" then
    -- exec:java uses the project classpath (dependencies included) and needs no plugin in the pom
    local prefix, jdk = jdk_prefix(p_type, p_root)
    return string.format(
      "%scd %s && mvn -q compile exec:java -Dexec.mainClass=%s%s",
      prefix,
      sh(p_root),
      sh(main),
      has_args and (" -Dexec.args=" .. sh(args_str)) or ""
    ),
      "Maven",
      jdk
  elseif p_type == "gradle" then
    local gradle = vim.fn.executable(p_root .. "/gradlew") == 1 and "./gradlew" or "gradle"
    local prefix, jdk = jdk_prefix(p_type, p_root)
    if check_gradle_application_plugin(p_root) then
      return string.format(
        "%scd %s && %s -q run%s",
        prefix,
        sh(p_root),
        gradle,
        has_args and (" --args=" .. sh(args_str)) or ""
      ),
        "Gradle",
        jdk
    end
    return string.format(
      "%scd %s && %s -q classes && java -cp build/classes/java/main %s%s",
      prefix,
      sh(p_root),
      gradle,
      sh(main),
      arg_s
    ),
      "Gradle",
      jdk
  end

  -- Plain Java. JDK 22+ runs several source files directly (no .class files),
  -- but starts the file's first class: only safe when main lives in the class
  -- named like the file. Otherwise compile into a temp dir, with the file's
  -- folder as sourcepath.
  local major = java_major()
  local in_file_class = main:match("[%w_$]+$") == vim.fn.fnamemodify(main_file, ":t:r")
  if major and major >= 22 and in_file_class then
    return string.format("java %s%s", sh(main_file), arg_s), "Plain", major
  end
  return string.format(
    'out=$(mktemp -d) && javac -d "$out" -sourcepath %s %s && java -cp "$out" %s%s',
    sh(vim.fn.fnamemodify(main_file, ":h")),
    sh(main_file),
    sh(main),
    arg_s
  ),
    "Plain",
    major
end

-- Parse @args metadata from file header ==> Supports 'name:type'
local function parse_args_metadata(file)
  if vim.fn.filereadable(file) == 0 then
    return nil
  end
  local lines = vim.fn.readfile(file, "", 50)
  for _, line in ipairs(lines) do
    local match = line:match("@args%s+(.+)")
    if match then
      local args = {}
      for token in match:gmatch("%S+") do
        local name, arg_type = token:match("([^:]+):?([^:]*)")
        table.insert(args, { name = name, type = (arg_type ~= "" and arg_type or "string") })
      end
      return args
    end
  end
  return nil
end

-- Banner printed before the command ==>  Executing "file.ext" [args: [..]]
local function with_banner(cmd, name, args_str)
  local shown = (args_str and args_str ~= "") and (" args: [" .. args_str .. "]") or ""
  local msg = string.format(' Executing "%s"%s', name, shown)
  return string.format("echo %s && echo '' && %s", vim.fn.shellescape(msg), cmd)
end

-- USER PREFERENCE ==> node | deno | bun
local js_runtime = "node"

-- Shell command to run a file ==> by extension. Returns cmd, kind, jdk (Java
-- only: "Maven" | "Gradle" | "Plain" and its major), or nil + reason + hint. `args_str` is
-- optional and reaches the program as typed (not escaped).
local function build_cmd(file, args_str, row, main)
  local q = vim.fn.shellescape
  local ext, name, dir =
    vim.fn.fnamemodify(file, ":e"), vim.fn.fnamemodify(file, ":t:r"), vim.fn.fnamemodify(file, ":p:h")
  local has_args = args_str and args_str ~= ""
  local args = has_args and (" " .. args_str) or ""

  local runners = {
    py = function()
      return string.format("cd %s && python3 %s%s", q(dir), q(file), args)
    end,
    rs = function()
      local is_cargo, root = detect_cargo_project(dir)
      if is_cargo then
        return string.format("cd %s && cargo run%s", q(root), has_args and (" -- " .. args_str) or "")
      end
      local bin = dir .. "/" .. name
      return string.format("rustc %s -o %s && %s%s", q(file), q(bin), q(bin), args)
    end,
    go = function()
      return string.format("go run %s%s", q(file), args)
    end,
    lua = function()
      return string.format("cd %s && lua %s%s", q(dir), q(file), args)
    end,
    sh = function()
      return string.format("cd %s && bash %s%s", q(dir), q(file), args)
    end,
    java = function()
      return java_run_cmd(file, dir, args_str, row, main)
    end,
  }

  -- JS/TS FAMILY HANDLER ==> node (tsx) | deno | bun
  for _, jext in ipairs({ "js", "mjs", "cjs", "ts" }) do
    runners[jext] = function()
      if js_runtime == "deno" then
        return string.format("cd %s && deno run -A %s%s", q(dir), q(file), args)
      elseif js_runtime == "bun" then
        return string.format("cd %s && bun run %s%s", q(dir), q(file), args)
      end
      return string.format("cd %s && %s %s%s", q(dir), jext == "ts" and "npx tsx" or "node", q(file), args)
    end
  end

  local runner = runners[ext]
  if not runner then
    local supported = vim.tbl_keys(runners)
    table.sort(supported)
    return nil,
      "Unsupported file type: ." .. (ext ~= "" and ext or "none"),
      "Supported: " .. table.concat(supported, ", ")
  end
  return runner()
end

-- Current buffer's file, saved first ==> nil when it is not on disk
local function current_file()
  if vim.bo.modified then
    vim.cmd(":w")
  end
  local file = vim.fn.expand("%:p")
  return vim.fn.filereadable(file) == 1 and file or nil
end

-- Run a file in a floating terminal ==> shared by <leader>rr (no args_str) and
-- <leader>ra. The previous run is wiped first so terminals do not pile up.
-- Several Java mains and the cursor in none ==> pick one (`main` on the retry).
local function run_file(file, args_str, main)
  local ext, name = vim.fn.fnamemodify(file, ":e"), vim.fn.fnamemodify(file, ":t:r")
  local row = vim.api.nvim_buf_get_name(0) == file and (vim.api.nvim_win_get_cursor(0)[1] - 1) or nil
  local cmd, extra, third = build_cmd(file, args_str, row, main)
  if not cmd and type(extra) == "table" then
    vim.ui.select(extra, { prompt = "Main class" }, function(choice)
      if choice then
        run_file(file, args_str, choice)
      end
    end)
    return
  end
  if not cmd then
    vim.notify(extra, vim.log.levels.WARN, { title = "Run System" })
    if third then
      vim.notify(third, vim.log.levels.INFO, { title = "Run System" })
    end
    return
  end
  local kind, jdk = extra, third

  local prev = _G.Run
  if prev and prev.buf and vim.api.nvim_buf_is_valid(prev.buf) then
    local buf = prev.buf
    pcall(prev.close, prev)
    pcall(vim.api.nvim_buf_delete, buf, { force = true }) -- also kills a job still running
  end

  _G.Run = Snacks.terminal.open(with_banner(cmd, name .. "." .. ext, args_str), {
    win = {
      position = "float",
      width = 0.9,
      height = 0.8,
      border = "rounded",
      title = " "
        .. ext:upper()
        .. (jdk and (" " .. jdk) or "")
        .. (kind and (" · " .. kind) or "")
        .. (args_str ~= nil and " Run + Args" or " Run"),
      title_pos = "center",
      backdrop = false,
    },
    interactive = true,
    auto_close = false,
  })
end

-- <leader>rr ==> run the current file
function M.run()
  local file = current_file()
  if file then
    run_file(file)
  end
end

-- <leader>ra ==> ask for args (@args header or free text), then run
function M.run_with_args()
  local file = current_file()
  if not file then
    return
  end

  local function execute_with_args(args_str)
    run_file(file, args_str)
  end

  -- Trigger CLI Interactive Prompts
  local expected_args = parse_args_metadata(file)

  if expected_args and #expected_args > 0 then
    local collected = {}
    local function ask_next(i)
      if i > #expected_args then
        execute_with_args(table.concat(collected, " "))
        return
      end

      local arg = expected_args[i]
      -- FORMAT: Capitalize name -> Name [type]
      local title_name = arg.name:gsub("^%l", string.upper)
      local prompt_str = string.format(" %s [%s] ", title_name, arg.type)

      vim.ui.input({ prompt = prompt_str }, function(input)
        if not input then
          return
        end -- User aborted (Esc)
        table.insert(collected, input)
        ask_next(i + 1)
      end)
    end
    ask_next(1)
  else
    -- Standard fallback
    vim.ui.input({ prompt = " CLI Args " }, function(args)
      if not args or args == "" then
        return
      end
      execute_with_args(args)
    end)
  end
end

return M
