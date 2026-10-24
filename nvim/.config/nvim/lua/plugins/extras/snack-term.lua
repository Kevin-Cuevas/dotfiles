-- # ==========================================================
-- # HELPERS
-- # ==========================================================

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

-- Extract Java main class ==> check @Test or main()
local function detect_main_class(file)
  local content = vim.fn.readfile(file)
  local package_name, class_name, has_main = "", "", false
  for _, line in ipairs(content) do
    local pkg = string.match(line, "^%s*package%s+([%w%.]+)")
    if pkg then
      package_name = pkg
    end
    local cls = string.match(line, "^%s*public%s+class%s+(%w+)")
    if cls then
      class_name = cls
    end
    if string.match(line, "public%s+static%s+void%s+main") then
      has_main = true
    end
  end
  if has_main and class_name ~= "" then
    return package_name ~= "" and (package_name .. "." .. class_name) or class_name
  end
  return nil
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
    local class = detect_main_class(f)
    if class then
      table.insert(candidates, { class = class, file = f })
    end
  end
  if #candidates == 1 then
    return candidates[1].class, candidates[1].file
  end
  return nil, nil, candidates
end

-- Prefix that points Maven/Gradle at the JDK the project asks for ==> the same
-- one jdtls picks (see config/jdks.lua), not whatever `java` the terminal has.
-- Empty when the project does not say or no suitable JDK is installed.
-- Returns prefix, major of the JDK that will run (the terminal's when no prefix).
local function jdk_prefix(p_type, root)
  local jdks = require("config.jdks")
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
-- nil + reason when there is nothing to run. `args_str` is optional.
local function java_run_cmd(file, dir, args_str)
  local sh = vim.fn.shellescape
  local has_args = args_str and args_str ~= ""
  local p_type, p_root = detect_java_project_type(dir)
  local main, main_file = detect_main_class(file), file
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
      main,
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
      main,
      arg_s
    ),
      "Gradle",
      jdk
  end

  -- Plain Java. JDK 22+ runs several source files directly (no .class files);
  -- older JDKs compile into a temp dir, with the file's folder as sourcepath.
  local major = java_major()
  if major and major >= 22 then
    return string.format("java %s%s", sh(main_file), arg_s), "Plain", major
  end
  return string.format(
    'out=$(mktemp -d) && javac -d "$out" -sourcepath %s %s && java -cp "$out" %s%s',
    sh(vim.fn.fnamemodify(main_file, ":h")),
    sh(main_file),
    main,
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
local function build_cmd(file, args_str)
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
      return java_run_cmd(file, dir, args_str)
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
local function run_file(file, args_str)
  local ext, name = vim.fn.fnamemodify(file, ":e"), vim.fn.fnamemodify(file, ":t:r")
  local cmd, extra, third = build_cmd(file, args_str)
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

-- # ==========================================================
-- # SNACKS TERMINAL CONFIG
-- # ==========================================================

-- CTRL+/ terminal ==> bottom split like the LazyVim original. A split can't have
-- a real float border/title, so its "header" is the winbar: we replace the
-- default "1: term://.../zsh" with "󰆍 Terminal". Edit it here:
--   left  -> "  󰆍 Terminal"      right -> "%=󰆍 Terminal"      center -> "%=󰆍 Terminal%="
local function bottom_terminal()
  Snacks.terminal.toggle(nil, {
    count = 1,
    cwd = LazyVim.root(),
    win = {
      style = "terminal",
      position = "bottom",
      height = 0.4,
      wo = { winbar = "%=󰆍 Terminal%=" },
    },
    interactive = true,
    auto_close = true,
  })
end

return {
  {
    "folke/snacks.nvim",
    keys = {
      -- CTRL+/ TERMINAL ==> bottom split (overrides the LazyVim default only to
      -- give it a clean winbar; still a split, not a float).
      { "<C-/>", bottom_terminal, mode = { "n", "t" }, desc = "Terminal (bottom)" },
      { "<C-_>", bottom_terminal, mode = { "n", "t" }, desc = "which_key_ignore" },

      -- SMART TOGGLE ==> Prioritize active run buffer over scratch
      {
        "<C-\\>",
        function()
          if _G.Run and _G.Run.buf and vim.api.nvim_buf_is_valid(_G.Run.buf) then
            _G.Run:toggle()
          else
            Snacks.terminal.toggle(nil, {
              count = 2,
              win = {
                style = "float",
                width = 0.9,
                height = 0.8,
                border = "rounded",
                title = "󰆍 Terminal ",
                title_pos = "center",
                wo = { winblend = 0, winhighlight = "Normal:Normal,FloatBorder:FloatBorder" },
                backdrop = false,
              },
              interactive = true,
              auto_close = true,
            })
          end
        end,
        mode = { "n", "t" },
        desc = "Smart terminal toggle",
      },

      -- SPAWN VERTICAL ==> <leader> + t + v
      {
        "<leader>tv",
        function()
          Snacks.terminal.open(nil, {
            count = 3,
            win = {
              position = "right",
              width = 0.4,
              border = "rounded",
              title = "󰆍 Vertical Term ",
              title_pos = "center",
            },
            interactive = true,
            auto_close = false,
          })
        end,
        desc = "Vertical terminal",
      },

      -- RUN GROUP ==> <leader> + r (name shown in which-key)
      { "<leader>r", "", desc = "+run" },

      -- RUN COMMAND ==> <leader> + r + r  (alias: F5)
      {
        "<leader>rr",
        function()
          local file = current_file()
          if file then
            run_file(file)
          end
        end,
        desc = "Execute file",
      },
      { "<F5>", "<leader>rr", remap = true, desc = "Execute file" },

      -- ARGS RUNNER ==> <leader> + r + a  (alias: F6)
      {
        "<leader>ra",
        function()
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
        end,
        desc = "Run with args",
      },
      { "<F6>", "<leader>ra", remap = true, desc = "Run with args" },
    },
  },
}
