-- Processes launched by util/runner.lua ==> one floating terminal per slot, so a
-- dev server keeps running while tests or a script run in another one.
--   slot "run"                 every non-Node run (Java, Python...): replaces itself
--   slot "<root>|script:dev"   a package.json script of a project
--   slot "<root>|file:x.js"    a JS/TS file of a project
-- Launching a slot that is alive restarts it. _G.Run is the last one shown, the
-- one <C-\> toggles (plugins/terminal.lua).
local M = {}

---@type table<string, { term: snacks.win, cmd: string, win: table, label: string, project: string, started: integer }>
local procs = {}

local function job_of(p)
  local buf = p.term and p.term.buf
  return buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].terminal_job_id or nil
end

-- Still running? ==> false once the program exits (the float stays open with
-- its output) or the buffer is wiped (:bd)
function M.alive(slot)
  local job = procs[slot] and job_of(procs[slot])
  return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
end

-- Kill and forget a slot. Waits for the job to exit (up to 2 s) so a restart
-- does not race the old server for its port (EADDRINUSE).
function M.kill(slot)
  local p = procs[slot]
  if not p then
    return
  end
  local job = job_of(p)
  if job then
    vim.fn.jobstop(job)
    vim.fn.jobwait({ job }, 2000)
  end
  if p.term.buf and vim.api.nvim_buf_is_valid(p.term.buf) then
    pcall(p.term.close, p.term)
    pcall(vim.api.nvim_buf_delete, p.term.buf, { force = true })
  end
  procs[slot] = nil
  if _G.Run == p.term then
    _G.Run = nil
  end
end

-- Only one Run float on screen ==> hide the others (they keep running)
local function hide_others(slot)
  for s, p in pairs(procs) do
    if s ~= slot and p.term:win_valid() then
      p.term:hide()
    end
  end
end

-- Launch `spec.cmd` in its slot ==> spec = { cmd, win (Snacks win opts), label,
-- project }. Restarts the slot when it already has a process.
function M.start(slot, spec)
  M.kill(slot)
  hide_others(slot)
  local term = Snacks.terminal.open(spec.cmd, { win = spec.win, interactive = true, auto_close = false })
  procs[slot] = vim.tbl_extend("force", spec, { term = term, started = os.time() })
  _G.Run = term
end

function M.show(slot)
  local p = procs[slot]
  if not p or not (p.term.buf and vim.api.nvim_buf_is_valid(p.term.buf)) then
    return
  end
  hide_others(slot)
  p.term:show()
  _G.Run = p.term
end

function M.restart(slot)
  local p = procs[slot]
  if p then
    M.start(slot, { cmd = p.cmd, win = p.win, label = p.label, project = p.project })
  end
end

local function age(started)
  local s = os.time() - started
  return s < 60 and (s .. "s") or s < 3600 and (math.floor(s / 60) .. "m") or (math.floor(s / 3600) .. "h")
end

-- <leader>rl ==> picker of the processes: <CR> shows it, <C-x> kills it,
-- <C-e> restarts it. Running ones first, then the newest.
function M.list()
  local items = {}
  for slot, p in pairs(procs) do
    if p.term.buf and vim.api.nvim_buf_is_valid(p.term.buf) then
      table.insert(
        items,
        { slot = slot, label = p.label, project = p.project, started = p.started, alive = M.alive(slot) }
      )
    else
      procs[slot] = nil -- wiped by hand (:bd)
    end
  end
  if #items == 0 then
    vim.notify("Nothing launched with the runner", vim.log.levels.INFO, { title = "Run System" })
    return
  end
  table.sort(items, function(a, b)
    if a.alive ~= b.alive then
      return a.alive
    end
    return a.started > b.started
  end)

  local width = 0
  for _, it in ipairs(items) do
    width = math.max(width, vim.fn.strdisplaywidth(it.label))
  end
  -- kill ==> back to the list; restart ==> the restarted float is what to see
  local function act(fn, relist)
    return function(picker, item)
      picker:close()
      if item then
        fn(item.item.slot)
        if relist then
          vim.schedule(M.list)
        end
      end
    end
  end

  vim.ui.select(items, {
    prompt = "Run · processes  (<C-x> kill · <C-e> restart)",
    format_item = function(it, chunks)
      if not chunks then
        return it.label .. " " .. it.project
      end
      return {
        { it.alive and "● " or "○ ", it.alive and "DiagnosticOk" or "Comment" },
        { it.label .. string.rep(" ", width - vim.fn.strdisplaywidth(it.label) + 2) },
        { it.project, "Directory" },
        { "  " .. (it.alive and ("up " .. age(it.started)) or "exited"), "Comment" },
      }
    end,
    snacks = {
      actions = { run_kill = act(M.kill, true), run_restart = act(M.restart, false) },
      win = {
        input = {
          keys = {
            ["<c-x>"] = { "run_kill", mode = { "n", "i" } },
            ["<c-e>"] = { "run_restart", mode = { "n", "i" } },
          },
        },
      },
    },
  }, function(it)
    if it then
      M.show(it.slot)
    end
  end)
end

return M
