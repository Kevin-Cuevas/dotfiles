-- File runner for <leader>rr / <leader>ra (keys in plugins/terminal.lua) ==>
-- builds the shell command per extension and opens a floating Snacks terminal.
-- package.json menu in util/runner_node.lua, processes in util/runner_procs.lua.
local M = {}

local node = require("util.runner_node")
local procs = require("util.runner_procs")
local args_meta = require("util.runner_args")

-- Memory between sessions ==> last args per item, so <leader>ra pre-fills them.
-- JSON in stdpath("state"): machine state, not dotfiles (like lazy-lock.json).
local memory = { path = vim.fn.stdpath("state") .. "/runner.json" }

function memory.load()
  if not memory.data then
    local ok, data = false, nil
    if vim.fn.filereadable(memory.path) == 1 then
      ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(memory.path), "\n"))
    end
    memory.data = (ok and type(data) == "table") and data or {}
  end
  return memory.data
end

function memory.get(root, field, key)
  local p = memory.load()[root]
  if not p then
    return nil
  end
  if key then
    return (p[field] or {})[key]
  end
  return p[field]
end

function memory.set(root, field, key, value)
  local data = memory.load()
  data[root] = data[root] or {}
  if key then
    data[root][field] = data[root][field] or {}
    data[root][field][key] = value
  else
    data[root][field] = value
  end
  pcall(vim.fn.writefile, { vim.json.encode(data) }, memory.path)
end

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
-- nil + reason when there is nothing to run, or nil + picker of classes to pick
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
    return nil,
      {
        prompt = "Main class",
        items = vim.tbl_map(function(m)
          return m.class
        end, in_file),
      }
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

-- Banner printed before the command ==>  Executing "file.ext" [args: [..]].
-- `args_shown` is what to print: the raw text, or `name=value` pairs for @args.
local function with_banner(cmd, name, args_shown)
  local shown = (args_shown and args_shown ~= "") and (" args: [" .. args_shown .. "]") or ""
  local msg = string.format(' Executing "%s"%s', name, shown)
  return string.format("echo %s && echo '' && %s", vim.fn.shellescape(msg), cmd)
end

-- USER PREFERENCE ==> node | deno | bun
local js_runtime = "node"

-- What to run for a file ==> by extension. Returns a spec { cmd, kind (Java:
-- "Maven" | "Gradle" | "Plain"; JS: what runs, e.g. "pnpm run dev"), jdk (Java
-- major), shown (banner name, the file when nil), slot (util/runner_procs.lua),
-- memo + key (where the memory keeps its args) }; or nil + reason + hint; or nil + picker { prompt,
-- items, format } whose choice comes back as `pick`. `args_str` is optional and
-- reaches the program as typed (not escaped).
local function build_cmd(file, args_str, row, pick)
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
      return java_run_cmd(file, dir, args_str, row, pick)
    end,
  }

  -- The file alone ==> in watch mode only when it keeps running (a server: it
  -- restarts on every :w, no need to kill and run it again by hand); a short
  -- script runs once and exits (see util/runner_node.lua). node gets the .env
  -- of `cwd` if there is one; bun loads it by itself.
  local function js_file_cmd(cwd, jext)
    local watch = node.is_long_running(file)
    if js_runtime == "deno" then
      local bin = watch and "deno run -A --watch" or "deno run -A"
      return string.format("cd %s && %s %s%s", q(cwd), bin, q(file), args), bin
    elseif js_runtime == "bun" then
      local bin = watch and "bun --watch run" or "bun run"
      return string.format("cd %s && %s %s%s", q(cwd), bin, q(file), args), bin
    end
    local bin = jext == "ts" and (watch and "npx tsx watch" or "npx tsx") or (watch and "node --watch" or "node")
    local env = vim.fn.filereadable(cwd .. "/.env") == 1 and " --env-file=.env" or ""
    return string.format("cd %s && %s%s %s%s", q(cwd), bin, env, q(file), args), bin
  end

  -- package.json project ==> menu of its scripts (+ the file when `jext` is set
  -- and it can run alone), run from the project root; see util/runner_node.lua.
  -- Every item gets its own process slot. npm is the only one that needs `--`
  -- to hand the args to the script; pnpm/yarn/bun pass them as they are.
  local function node_cmd(jext)
    local root, pkg = node.detect(dir)
    if not root then
      if not jext then
        return nil
      end
      local cmd, bin = js_file_cmd(dir, jext)
      return { cmd = cmd, kind = bin, slot = "file:" .. file, memo = file, key = "file" }
    end
    local function file_spec()
      local cmd, bin = js_file_cmd(root, jext)
      local key = "file:" .. file:sub(#root + 2)
      return { cmd = cmd, kind = bin, slot = root .. "|" .. key, memo = root, key = key }
    end
    if pick and pick.kind == "file" then
      return file_spec()
    end
    local pm = node.package_manager(root, pkg)
    if pick then
      local run = pm .. " run " .. pick.name
      local sep = (has_args and pm == "npm") and " --" or ""
      return {
        cmd = string.format("cd %s && %s run %s%s%s", q(root), pm, q(pick.name), sep, args),
        kind = run,
        shown = run,
        slot = root .. "|" .. pick.key,
        memo = root,
        key = pick.key,
      }
    end
    local _, file_kind = js_file_cmd(root, jext)
    local items = node.items(root, pkg, {
      file = file,
      jext = jext,
      file_cmd = file_kind,
      running = function(key)
        return procs.alive(root .. "|" .. key)
      end,
    })
    if #items == 0 then
      if jext and node.is_test_file(file) then
        return nil, "Test file: neotest runs it", "<leader>tt file · <leader>tr nearest · <leader>ts summary"
      end
      return nil
    end
    if #items == 1 and items[1].kind == "file" then
      return file_spec()
    end
    return nil,
      {
        prompt = pm .. " run · " .. vim.fn.fnamemodify(root, ":t"),
        items = items,
        format = node.format(items),
        snacks = node.picker_opts(items),
      }
  end

  -- JS/TS FAMILY HANDLER ==> node (tsx) | deno | bun
  for _, jext in ipairs({ "js", "mjs", "cjs", "ts" }) do
    runners[jext] = function()
      return node_cmd(jext)
    end
  end

  local runner = runners[ext]
  -- Any other file of a package.json project (html, css, jsx, vue...) ==> only
  -- its scripts: that is how they run (vite, live-server...).
  if not runner then
    local spec, extra = node_cmd(nil)
    if spec or extra then
      return spec, extra
    end
  end
  if not runner then
    local supported = vim.tbl_keys(runners)
    table.sort(supported)
    return nil,
      "Unsupported file type: ." .. (ext ~= "" and ext or "none"),
      "Supported: " .. table.concat(supported, ", ")
  end

  local cmd, kind, jdk = runner()
  if type(cmd) ~= "string" then
    return cmd, kind, jdk -- Node spec, picker or error: already in shape
  end
  -- Every other language shares the "run" slot: a new run replaces the last one
  return { cmd = cmd, kind = kind, jdk = jdk, slot = "run", memo = file, key = "file" }
end

-- Current buffer's file, saved first ==> nil when it is not on disk
local function current_file()
  if vim.bo.modified then
    vim.cmd(":w")
  end
  local file = vim.fn.expand("%:p")
  return vim.fn.filereadable(file) == 1 and file or nil
end

-- Ask the args of what is about to run ==> after the menu, so they belong to the
-- chosen item. When the file itself runs and has an @args header: one prompt
-- (or menu) per arg, validated and shell-escaped, see util/runner_args.lua.
-- Else free text, passed as typed (shell syntax allowed). Both pre-filled with
-- the last answers for that item. <Esc> cancels; empty runs without args.
-- on_args(argv, shown, named): named = { name = value } for @args, else nil.
local function ask_args(file, spec, on_args)
  local declared = spec.key:match("^file") and args_meta.parse(file) or nil
  if declared then
    args_meta.ask(declared, memory.get(spec.memo, "named", spec.key), on_args)
    return
  end
  local target = spec.shown or vim.fn.fnamemodify(file, ":t")
  local last = memory.get(spec.memo, "args", spec.key) or ""
  vim.ui.input({ prompt = " Args · " .. target .. " ", default = last }, function(args)
    if args then
      on_args(vim.trim(args))
    end
  end)
end

-- Run a file in a floating terminal ==> shared by <leader>rr and <leader>ra
-- (opts.ask). opts = { pick, args, args_shown, named, ask }. Something to pick (several Java mains
-- and the cursor in none, package.json scripts) ==> menu, and the choice comes
-- back as opts.pick on the retry; then the args, when asked for.
local function run_file(file, opts)
  local ext, name = vim.fn.fnamemodify(file, ":e"), vim.fn.fnamemodify(file, ":t:r")
  local row = vim.api.nvim_buf_get_name(0) == file and (vim.api.nvim_win_get_cursor(0)[1] - 1) or nil
  local spec, extra, hint = build_cmd(file, opts.args, row, opts.pick)
  if not spec and type(extra) == "table" then
    local select_opts = { prompt = extra.prompt, format_item = extra.format, snacks = extra.snacks }
    vim.ui.select(extra.items, select_opts, function(choice)
      if choice then
        run_file(file, vim.tbl_extend("force", opts, { pick = choice }))
      end
    end)
    return
  end
  if not spec then
    vim.notify(extra, vim.log.levels.WARN, { title = "Run System" })
    if hint then
      vim.notify(hint, vim.log.levels.INFO, { title = "Run System" })
    end
    return
  end
  if opts.ask and not opts.args then
    ask_args(file, spec, function(args, shown, named)
      run_file(file, vim.tbl_extend("force", opts, { args = args, args_shown = shown, named = named }))
    end)
    return
  end

  if opts.named then
    memory.set(spec.memo, "named", spec.key, opts.named)
  elseif opts.args then
    memory.set(spec.memo, "args", spec.key, opts.args)
  end
  local label = spec.shown or (name .. "." .. ext)
  local project = spec.memo == file and vim.fn.fnamemodify(file, ":h") or spec.memo
  procs.start(spec.slot, {
    cmd = with_banner(spec.cmd, label, opts.args_shown or opts.args),
    label = label,
    project = vim.fn.fnamemodify(project, ":t"),
    win = {
      position = "float",
      width = 0.9,
      height = 0.8,
      border = "rounded",
      title = " "
        .. ext:upper()
        .. (spec.jdk and (" " .. spec.jdk) or "")
        .. (spec.kind and (" · " .. spec.kind) or "")
        .. ((opts.args and opts.args ~= "") and " Run + Args" or " Run"),
      title_pos = "center",
      backdrop = false,
    },
  })
end

-- <leader>rr ==> run the current file
function M.run()
  local file = current_file()
  if file then
    run_file(file, {})
  end
end

-- <leader>ra ==> pick what to run (if there is a menu), then its args
function M.run_with_args()
  local file = current_file()
  if file then
    run_file(file, { ask = true })
  end
end

-- <leader>rl ==> processes launched by the runner (show / kill / restart)
M.processes = procs.list

return M
