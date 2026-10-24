-- Descubre los JDKs instalados (SDKMAN y Debian) y devuelve la lista de
-- runtimes que espera jdtls. Se resuelven symlinks para no duplicar
-- (current, default-java, java-1.25.0-...). SDKMAN va primero, así que
-- si hay la misma versión mayor en los dos sitios gana la de SDKMAN.
local function discover_jdks()
  local roots = {
    vim.fn.expand("~") .. "/.sdkman/candidates/java/*",
    "/usr/lib/jvm/*",
  }
  local by_major, seen = {}, {}
  for _, glob in ipairs(roots) do
    for _, dir in ipairs(vim.fn.glob(glob, false, true)) do
      local real = vim.uv.fs_realpath(dir)
      -- exige javac: un JRE solo no sirve para compilar
      if real and not seen[real] and vim.fn.executable(real .. "/bin/javac") == 1 then
        seen[real] = true
        local ok, lines = pcall(vim.fn.readfile, real .. "/release")
        local v = ok and table.concat(lines, "\n"):match('JAVA_VERSION="([^"]+)"')
        local major = v and (v:match("^1%.(%d+)") or v:match("^(%d+)"))
        if major and not by_major[major] then
          by_major[major] = real
        end
      end
    end
  end
  local runtimes = {}
  for major, path in pairs(by_major) do
    local name = major == "8" and "JavaSE-1.8" or ("JavaSE-" .. major)
    table.insert(runtimes, { name = name, path = path })
  end
  table.sort(runtimes, function(a, b)
    return a.name < b.name
  end)
  return runtimes
end

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- jdtls corre siempre con el JDK del sistema, aunque nvim se abra tras `sdk use`
      local sys_java = "/usr/lib/jvm/default-java/bin/java"
      if vim.fn.executable(sys_java) == 1 then
        table.insert(opts.cmd, "--java-executable=" .. sys_java)
      end
      -- JDKs contra los que se compilan tus proyectos
      opts.settings.java.configuration = { runtimes = discover_jdks() }
    end,
  },

  -- pom.xml: autocompletado y validación (también formatea)
  { "mason-org/mason.nvim", opts = { ensure_installed = { "lemminx" } } },
  { "neovim/nvim-lspconfig", opts = { servers = { lemminx = {} } } },
}
