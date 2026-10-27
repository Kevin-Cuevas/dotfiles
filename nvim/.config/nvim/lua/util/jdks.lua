-- JDKs instalados (SDKMAN y Debian) y qué JDK pide un proyecto. Lo usan
-- plugins/java.lua (runtimes de jdtls) y util/runner.lua (rr/ra),
-- para que el editor y F5 compilen con el mismo JDK.
local M = {}

-- Mayor => ruta de cada JDK con javac. Se resuelven symlinks para no duplicar
-- (current, default-java, java-1.25.0-...). SDKMAN va primero, así que si hay
-- la misma versión mayor en los dos sitios gana la de SDKMAN.
local function installed()
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
  return by_major
end

-- Runtimes con el formato que espera jdtls (java.configuration.runtimes)
function M.discover()
  local runtimes = {}
  for major, path in pairs(installed()) do
    local name = major == "8" and "JavaSE-1.8" or ("JavaSE-" .. major)
    table.insert(runtimes, { name = name, path = path })
  end
  table.sort(runtimes, function(a, b)
    return a.name < b.name
  end)
  return runtimes
end

-- "1.8" | "8" | "17" ==> 8 | 8 | 17
local function to_major(v)
  return tonumber(v:match("^1%.(%d+)") or v:match("^(%d+)"))
end

-- Primero lo que fija el nivel del compilador, después lo que lo sugiere.
-- Gradle: mejor esfuerzo, sin probar contra un proyecto real.
local patterns = {
  maven = {
    "<maven%.compiler%.release>%s*([%d%.]+)%s*<",
    "<release>%s*([%d%.]+)%s*</release>",
    "<maven%.compiler%.target>%s*([%d%.]+)%s*<",
    "<maven%.compiler%.source>%s*([%d%.]+)%s*<",
    "<java%.version>%s*([%d%.]+)%s*<",
    "<target>%s*([%d%.]+)%s*</target>",
    "<source>%s*([%d%.]+)%s*</source>",
  },
  gradle = {
    "JavaLanguageVersion%.of%(%s*(%d+)%s*%)",
    "jvmToolchain%(%s*(%d+)%s*%)",
    "JavaVersion%.VERSION_(1_%d+)",
    "JavaVersion%.VERSION_(%d+)",
    "sourceCompatibility%s*=%s*['\"]([%d%.]+)['\"]",
  },
}

-- Versión de Java que pide el proyecto ==> número o nil. Si el módulo no la
-- fija se sigue hacia el pom/gradle padre, solo mientras exista en la carpeta de arriba.
function M.target_release(p_type, root)
  local files = p_type == "maven" and { "pom.xml" } or { "build.gradle", "build.gradle.kts" }
  local function has_build(dir)
    for _, f in ipairs(files) do
      if vim.fn.filereadable(dir .. "/" .. f) == 1 then
        return dir .. "/" .. f
      end
    end
  end

  local dir = root
  for _ = 1, 4 do
    local path = has_build(dir)
    if not path then
      return nil
    end
    local content = table.concat(vim.fn.readfile(path), "\n")
    for _, pat in ipairs(patterns[p_type] or {}) do
      local v = content:match(pat)
      if v then
        return to_major(v:gsub("_", "."))
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

-- JDK instalado para un nivel de Java ==> ruta, mayor. El exacto si existe;
-- si no, el menor que sea mayor (un 17 corre bien en un 25). nil si no hay.
function M.for_target(major)
  local best_major, best_path
  for m, path in pairs(installed()) do
    m = tonumber(m)
    if m >= major and (not best_major or m < best_major) then
      best_major, best_path = m, path
    end
  end
  return best_path, best_major
end

return M
