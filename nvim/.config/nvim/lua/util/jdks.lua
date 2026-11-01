-- Installed JDKs (SDKMAN and Debian) and which JDK a project asks for. Used by
-- plugins/java.lua (jdtls runtimes) and util/runner.lua (rr/ra), so the
-- editor and F5 compile with the same JDK.
local M = {}

-- Major => path of each JDK with javac. Symlinks are resolved to avoid
-- duplicates (current, default-java, java-1.25.0-...). SDKMAN goes first, so
-- if the same major version is in both places, SDKMAN's wins.
local function installed()
  local roots = {
    vim.fn.expand("~") .. "/.sdkman/candidates/java/*",
    "/usr/lib/jvm/*",
  }
  local by_major, seen = {}, {}
  for _, glob in ipairs(roots) do
    for _, dir in ipairs(vim.fn.glob(glob, false, true)) do
      local real = vim.uv.fs_realpath(dir)
      -- requires javac: a bare JRE can't compile
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

-- Runtimes in the format jdtls expects (java.configuration.runtimes)
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

-- First what pins the compiler level, then what suggests it.
-- Gradle: best effort, not tested against a real project.
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

-- Java version the project asks for ==> number or nil. If the module doesn't
-- pin it, it follows up to the parent pom/gradle, only while one exists in the
-- folder above.
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

-- Installed JDK for a Java level ==> path, major. The exact one if it exists;
-- otherwise the smallest one above it (a 17 runs fine on a 25). nil if none.
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
