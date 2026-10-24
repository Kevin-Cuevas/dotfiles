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

-- Shell command to run a Java file ==> Maven | Gradle | plain. Returns nil +
-- reason when there is nothing to run. `args_str` is optional.
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

  if p_type == "maven" then
    -- exec:java uses the project classpath (dependencies included) and needs no plugin in the pom
    return string.format(
      "cd %s && mvn -q compile exec:java -Dexec.mainClass=%s%s",
      sh(p_root),
      main,
      has_args and (" -Dexec.args=" .. sh(args_str)) or ""
    )
  elseif p_type == "gradle" then
    local gradle = vim.fn.executable(p_root .. "/gradlew") == 1 and "./gradlew" or "gradle"
    if check_gradle_application_plugin(p_root) then
      return string.format("cd %s && %s -q run%s", sh(p_root), gradle, has_args and (" --args=" .. sh(args_str)) or "")
    end
    return string.format(
      "cd %s && %s -q classes && java -cp build/classes/java/main %s%s",
      sh(p_root),
      gradle,
      main,
      has_args and (" " .. args_str) or ""
    )
  end

  -- Plain Java. JDK 22+ runs several source files directly (no .class files);
  -- older JDKs compile into a temp dir, with the file's folder as sourcepath.
  local major = java_major()
  if major and major >= 22 then
    return string.format("java %s%s", sh(main_file), has_args and (" " .. args_str) or "")
  end
  return string.format(
    'out=$(mktemp -d) && javac -d "$out" -sourcepath %s %s && java -cp "$out" %s%s',
    sh(vim.fn.fnamemodify(main_file, ":h")),
    sh(main_file),
    main,
    has_args and (" " .. args_str) or ""
  )
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
          if vim.bo.modified then
            vim.cmd(":w")
          end
          local file, ext, filename, dir =
            vim.fn.expand("%:p"), vim.fn.expand("%:e"), vim.fn.expand("%:t:r"), vim.fn.expand("%:h")
          if vim.fn.filereadable(file) == 0 then
            return
          end

          -- USER PREFERENCE ==> node | deno | bun
          local js_runtime = "node"

          local cmd_map = {
            py = string.format("cd %s && python3 %s", dir, file),
            rs = function()
              local is_cargo, p_root = detect_cargo_project(dir)
              return is_cargo and string.format("cd %s && cargo run", p_root)
                or string.format("rustc %s -o %s/%s && %s/%s", file, dir, filename, dir, filename)
            end,
            go = "go run " .. file,
            lua = string.format("cd %s && lua %s", dir, file),
            sh = string.format("cd %s && bash %s", dir, file),
            java = function()
              return java_run_cmd(file, dir)
            end,
          }

          -- JS/TS FAMILY HANDLER ==> node (tsx) | deno | bun
          local js_family = { "js", "mjs", "cjs", "ts" }
          for _, jext in ipairs(js_family) do
            cmd_map[jext] = function()
              if js_runtime == "deno" then
                return string.format("cd %s && deno run -A %s", dir, file)
              elseif js_runtime == "bun" then
                return string.format("cd %s && bun run %s", dir, file)
              else
                local bin = (jext == "ts") and "npx tsx" or "node"
                return string.format("cd %s && %s %s", dir, bin, file)
              end
            end
          end

          local cmd, reason = cmd_map[ext], nil
          if type(cmd) == "function" then
            cmd, reason = cmd()
          end

          if not cmd and reason then
            vim.notify(reason, vim.log.levels.WARN, { title = "Run System" })
            return
          end

          if not cmd then
            local supported_exts = table.concat(vim.tbl_keys(cmd_map), ", ")
            vim.notify(
              "Unsupported file type: ." .. (ext ~= "" and ext or "none"),
              vim.log.levels.WARN,
              { title = "Run System" }
            )
            vim.notify("Supported: " .. supported_exts, vim.log.levels.INFO, { title = "Run System" })
            return
          end

          _G.Run = Snacks.terminal.open(cmd, {
            win = {
              position = "float",
              width = 0.9,
              height = 0.8,
              border = "rounded",
              title = " " .. ext:upper() .. " Run",
              title_pos = "center",
              backdrop = false,
            },
            interactive = true,
            auto_close = false,
          })
        end,
        desc = "Execute file",
      },
      { "<F5>", "<leader>rr", remap = true, desc = "Execute file" },

      -- ARGS RUNNER ==> <leader> + r + a  (alias: F6)
      {
        "<leader>ra",
        function()
          if vim.bo.modified then
            vim.cmd(":w")
          end
          local file, ext, filename, dir =
            vim.fn.expand("%:p"), vim.fn.expand("%:e"), vim.fn.expand("%:t:r"), vim.fn.expand("%:h")
          if vim.fn.filereadable(file) == 0 then
            return
          end

          local function execute_with_args(args_str)
            local js_runtime = "node"
            local cmd_map = {
              py = string.format("cd %s && python3 %s %s", dir, file, args_str),
              rs = function()
                local is_cargo, p_root = detect_cargo_project(dir)
                return is_cargo and string.format("cd %s && cargo run -- %s", p_root, args_str)
                  or string.format("rustc %s -o %s/%s && %s/%s %s", file, dir, filename, dir, filename, args_str)
              end,
              go = string.format("go run %s %s", file, args_str),
              lua = string.format("cd %s && lua %s %s", dir, file, args_str),
              sh = string.format("cd %s && bash %s %s", dir, file, args_str),
              java = function()
                return java_run_cmd(file, dir, args_str)
              end,
            }

            local js_family = { "js", "mjs", "cjs", "ts" }
            for _, jext in ipairs(js_family) do
              cmd_map[jext] = function()
                if js_runtime == "deno" then
                  return string.format("cd %s && deno run -A %s %s", dir, file, args_str)
                elseif js_runtime == "bun" then
                  return string.format("cd %s && bun run %s %s", dir, file, args_str)
                else
                  local bin = (jext == "ts") and "npx tsx" or "node"
                  return string.format("cd %s && %s %s %s", dir, bin, file, args_str)
                end
              end
            end

            local cmd, reason = cmd_map[ext], nil
            if type(cmd) == "function" then
              cmd, reason = cmd()
            end

            if not cmd and reason then
              vim.notify(reason, vim.log.levels.WARN, { title = "Run System" })
              return
            end

            if not cmd then
              vim.notify("Unsupported file type: ." .. (ext ~= "" and ext or "none"), vim.log.levels.WARN)
              return
            end

            local start_msg =
              string.format("echo ' Executing \"%s\" args: [%s]' && echo ''", filename .. "." .. ext, args_str)
            _G.Run = Snacks.terminal.open(start_msg .. " && " .. cmd, {
              win = {
                position = "float",
                width = 0.9,
                height = 0.8,
                border = "rounded",
                title = " " .. ext:upper() .. " Run + Args",
                title_pos = "center",
                backdrop = false,
              },
              interactive = true,
              auto_close = false,
            })
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

      -- COMPILER ==> <leader> + t + c
      {
        "<leader>tc",
        function()
          _G.Run = Snacks.terminal.open("echo ' Building target...' && sleep 1", {
            win = {
              position = "float",
              width = 0.8,
              height = 0.6,
              border = "rounded",
              title = " Compile",
              backdrop = false,
            },
            interactive = true,
            auto_close = false,
          })
        end,
        desc = "Build project",
      },

      -- TESTER ==> <leader> + t + t
      {
        "<leader>tt",
        function()
          _G.Run = Snacks.terminal.open("echo '󰙨 Running test suite...'", {
            win = {
              position = "float",
              width = 0.9,
              height = 0.8,
              border = "rounded",
              title = "󰙨 Tests",
              backdrop = false,
            },
            interactive = true,
            auto_close = false,
          })
        end,
        desc = "Test suite",
      },
    },
  },
}
