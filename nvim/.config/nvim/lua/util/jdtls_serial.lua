-- nvim-jdtls pide `vscode.java.resolveJavaExecutable` en paralelo, una por clase
-- con main, al abrir un .java (escaneo de LazyVim) y al pulsar F5. Recién
-- arrancado, jdtls (java-debug) responde nil a algunas de las simultáneas:
-- sale "Could not resolve java executable for ..." y, como esa clase nunca
-- termina, no se registra ninguna configuración de debug. Pasa más cuantas
-- más clases con main hay. Aquí se piden de una en una.
--
-- Reemplaza jdtls.util.with_java_executable: hay que aplicarlo antes del
-- primer require("jdtls"), porque jdtls.lua y jdtls/dap.lua la copian al cargar.
local M = {}

function M.apply()
  local util = require("jdtls.util")
  local queue, busy = {}, false

  local function run_next()
    local job = table.remove(queue, 1)
    if not job then
      busy = false
      return
    end
    busy = true
    local mainclass, project, fn, bufnr = job[1], job[2], job[3], job[4]
    bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
    local client = vim.lsp.get_clients({ name = "jdtls", bufnr = bufnr })[1]
      or vim.lsp.get_clients({ name = "jdtls" })[1]
    if not client then
      vim.notify("No jdtls client found for bufnr=" .. bufnr, vim.log.levels.INFO)
      return run_next()
    end
    client:request("workspace/executeCommand", {
      command = "vscode.java.resolveJavaExecutable",
      arguments = { mainclass, project },
    }, function(err, java_exec)
      vim.schedule(run_next)
      if err then
        print("Could not resolve java executable: " .. err.message)
      elseif java_exec then
        fn(java_exec)
      else
        print(string.format("Could not resolve java executable for %s %s", mainclass, project))
      end
    end, bufnr)
  end

  util.with_java_executable = function(mainclass, project, fn, bufnr)
    table.insert(queue, { mainclass, project, fn, bufnr })
    if not busy then
      run_next()
    end
  end
end

return M
