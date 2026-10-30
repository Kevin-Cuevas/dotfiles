-- Node side of util/runner.lua ==> package.json detection and the scripts menu:
-- which items it shows, in what order, and how they look. Building the shell
-- commands stays in runner.lua, next to the other languages.
local M = {}

-- Detect Node project ==> nearest package.json. Returns root + its decoded table
-- ({} when it does not parse), or nil when there is none.
function M.detect(dir)
  local current_dir = dir
  while current_dir ~= "/" and current_dir ~= "" do
    local path = current_dir .. "/package.json"
    if vim.fn.filereadable(path) == 1 then
      local ok, pkg = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
      return current_dir, (ok and type(pkg) == "table") and pkg or {}
    end
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end
  return nil
end

local lockfiles = {
  { "pnpm-lock.yaml", "pnpm" },
  { "yarn.lock", "yarn" },
  { "bun.lock", "bun" },
  { "bun.lockb", "bun" },
  { "package-lock.json", "npm" },
}

-- Package manager of a Node project ==> "packageManager" of package.json, else
-- the nearest lockfile (going up: in workspaces it lives at the repo root), else
-- npm. npm too when the one found is not installed.
function M.package_manager(root, pkg)
  local pm = type(pkg.packageManager) == "string" and pkg.packageManager:match("^(%a+)@") or nil
  local current_dir = root
  while not pm and current_dir ~= "/" and current_dir ~= "" do
    for _, lock in ipairs(lockfiles) do
      if vim.fn.filereadable(current_dir .. "/" .. lock[1]) == 1 then
        pm = lock[2]
        break
      end
    end
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end
  return (pm and vim.fn.executable(pm) == 1) and pm or "npm"
end

-- Menu groups, in display order ==> the current file first, then a script lands
-- in the first group whose pattern matches its name. Only Nord-safe highlight
-- groups (no orange/yellow/purple in the light theme): Function/Type/Directory
-- are frost.
local groups = {
  { id = "file", icon = "󰈙", hl = "Directory" },
  { id = "server", icon = "󰒋", hl = "Function", match = { "^dev", "^start", "^serve", "^watch", "^preview" } },
  { id = "build", icon = "󰏗", hl = "Type", match = { "^build", "^compile", "^bundle" } },
  { id = "other", icon = "󰆍", hl = "Comment" },
}

-- Scripts left out of the menu ==> they already have a better place: tests in
-- neotest (<leader>tt file, <leader>tr nearest) and lint/format in the LSP
-- (eslint diagnostics, prettier on save).
local skipped = { "^test", "^e2e", "^spec", "^coverage", "^lint", "^format", "^fmt", "^prettier", "^typecheck" }
local group_rank = {}
for i, g in ipairs(groups) do
  group_rank[g.id] = i
end

-- Inside the server group, the usual way to start comes first
local server_order = { dev = 1, start = 2, serve = 3, watch = 4, preview = 5 }

-- npm runs these by itself (install/publish hooks): noise in a run menu
local lifecycle = {
  prepare = true,
  prepublish = true,
  prepublishOnly = true,
  prepack = true,
  postpack = true,
  preinstall = true,
  install = true,
  postinstall = true,
}

local function group_of(name)
  for _, g in ipairs(groups) do
    for _, pat in ipairs(g.match or {}) do
      if name:match(pat) then
        return g
      end
    end
  end
  return groups[#groups]
end

-- pre<x>/post<x> hooks of an existing <x> run along with it ==> hidden
local function is_hook(name, scripts)
  local base = name:match("^pre(.+)") or name:match("^post(.+)")
  return lifecycle[name] or (base ~= nil and scripts[base] ~= nil)
end

local function is_skipped(name)
  for _, pat in ipairs(skipped) do
    if name:match(pat) then
      return true
    end
  end
  return false
end

function M.is_test_file(file)
  return file:match("%.test%.[cm]?[jt]sx?$") ~= nil
    or file:match("%.spec%.[cm]?[jt]sx?$") ~= nil
    or file:find("/__tests__/", 1, true) ~= nil
end

-- Can the file run alone? ==> a module that only exports things (app.js, a lib)
-- does nothing when run, so the menu hides it. Signs that it does run: a server
-- (.listen), CLI args, a shebang, @args metadata, being package.json "main" or
-- living in scripts/ or bin/. Test files run through their test script/neotest.
function M.file_runs_alone(file, root, pkg)
  if M.is_test_file(file) then
    return false
  end
  local rel = file:sub(#root + 2)
  local main = type(pkg.main) == "string" and pkg.main:gsub("^%./", "") or nil
  if rel == main or rel:match("^scripts/") or rel:match("^bin/") then
    return true
  end
  local src = table.concat(vim.fn.readfile(file, "", 400), "\n")
  if src:match("^#!") or src:find("@args") or src:find("%.listen%(") or src:find("process%.argv") then
    return true
  end
  local exports = src:match("^export%s")
    or src:find("\nexport%s")
    or src:find("module%.exports")
    or src:find("\nexports%.")
  return not exports
end

-- Does the file keep running? ==> a server, a timer or a worker: worth --watch
-- (it restarts on :w). A script that does its job and exits runs plain: with
-- --watch node would stay "waiting for changes" and rerun it on every :w.
local long_running =
  { "%.listen%(", "createServer%(", "setInterval%(", "new Worker%(", "Bun%.serve%(", "Deno%.serve%(" }

function M.is_long_running(file)
  local src = table.concat(vim.fn.readfile(file, "", 400), "\n")
  for _, pat in ipairs(long_running) do
    if src:find(pat) then
      return true
    end
  end
  return false
end

-- Menu items of a project ==> { key, kind ("script" | "file"), name, cmd, group,
-- running }. `key` identifies the item for the args memory and the process
-- list ("script:dev", "file:src/seed.js"). Order: the current file (when it can
-- run alone), then the scripts by group (server, build, other), the same in
-- every file of the project: dev is always in the same place.
-- ctx = { file, jext (nil when the file cannot run with node), file_cmd (what
-- runs the file, e.g. "node" or "node --watch"), running (fun(key): bool) }.
-- A test file never offers itself: node cannot run it, neotest does.
function M.items(root, pkg, ctx)
  local scripts = type(pkg.scripts) == "table" and pkg.scripts or {}
  local rel = ctx.file:sub(#root + 2)
  local items = {}

  for name, cmd in pairs(scripts) do
    if type(cmd) == "string" and not is_hook(name, scripts) and not is_skipped(name) then
      table.insert(items, { key = "script:" .. name, kind = "script", name = name, cmd = cmd, group = group_of(name) })
    end
  end
  if ctx.jext and not M.is_test_file(ctx.file) and (#items == 0 or M.file_runs_alone(ctx.file, root, pkg)) then
    table.insert(items, {
      key = "file:" .. rel,
      kind = "file",
      name = vim.fn.fnamemodify(ctx.file, ":t"),
      cmd = ctx.file_cmd,
      group = groups[group_rank.file],
    })
  end

  for _, it in ipairs(items) do
    it.running = ctx.running(it.key)
  end
  table.sort(items, function(a, b)
    local ga, gb = group_rank[a.group.id], group_rank[b.group.id]
    if ga ~= gb then
      return ga < gb
    end
    local sa, sb = server_order[a.name] or 99, server_order[b.name] or 99
    if sa ~= sb then
      return sa < sb
    end
    return a.name < b.name
  end)
  return items
end

-- The file name in frost and bold ==> derived from Directory, so it follows the
-- light/dark switch
local function set_file_hl()
  local hl = vim.api.nvim_get_hl(0, { name = "Directory", link = false })
  hl.bold = true
  vim.api.nvim_set_hl(0, "RunnerFile", hl)
end
set_file_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_file_hl })

-- "── package.json ───" under the file row ==> a virtual line, so it is not an
-- item: the cursor skips it and it never runs. Long on purpose: the window
-- clips it at its edge.
local separator = {
  { "   ── ", "FloatBorder" },
  { "package.json", "Comment" },
  { " " .. string.rep("─", 200), "FloatBorder" },
}

-- format_item for vim.ui.select ==> with Snacks (`chunks`): aligned columns
-- (icon, name, command dimmed), ● running, and the separator between the file
-- and the package.json scripts. Plain text otherwise (also what the picker
-- fuzzy-matches: name + command).
function M.format(items)
  local width = 0
  for _, it in ipairs(items) do
    width = math.max(width, vim.fn.strdisplaywidth(it.name))
  end
  local split = #items > 1 and items[1].kind == "file"
  return function(it, chunks)
    if not chunks then
      return it.name .. " " .. it.cmd
    end
    local file = it.kind == "file"
    local ret = {
      { it.running and "● " or "  ", "DiagnosticOk" },
      { it.group.icon .. " ", it.group.hl },
      { it.name .. string.rep(" ", width - vim.fn.strdisplaywidth(it.name) + 2), file and "RunnerFile" or nil },
      { it.cmd, "Comment" },
    }
    if it.running then
      table.insert(ret, { "  running · restarts", "DiagnosticOk" })
    end
    if file and split then
      table.insert(ret, { col = 0, virt_lines = { separator } })
    end
    return ret
  end
end

-- Snacks options for the menu ==> its select sizes the list to the number of
-- items; the separator line needs one more row or the last item scrolls out.
function M.picker_opts(items)
  local extra = (#items > 1 and items[1].kind == "file") and 1 or 0
  return {
    layout = {
      config = function(layout)
        for _, box in ipairs(layout.layout) do
          if box.win == "list" and not box.height then
            box.height = math.max(math.min(#items + extra, vim.o.lines * 0.8 - 10), 2)
          end
        end
      end,
    },
  }
end

return M
