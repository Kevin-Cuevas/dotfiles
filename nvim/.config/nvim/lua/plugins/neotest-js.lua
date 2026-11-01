-- JS/TS tests in neotest (test.core extra) ==> vitest and jest together. The
-- adapters aren't binaries (Mason doesn't have them) and there's no LazyVim
-- extra for them: they're plugins. Each one only claims files from projects
-- that list it in package.json, so they don't step on each other.

-- neotest-jest looks for jest.config.{js,ts} with vim.fn.glob while building
-- the command, from a libuv callback ==> E5560 ("must not be called in a fast
-- event context") and the test never runs. The same lookup with vim.fs.root
-- (libuv only) is allowed there. Without a config it returns the adapter's
-- default path, which it only passes as --config when it exists.
local jest_configs = { "jest.config.ts", "jest.config.js", "jest.config.mjs", "jest.config.cjs" }

local function jest_config(file)
  local root = vim.fs.root(file, jest_configs)
  for _, name in ipairs(root and jest_configs or {}) do
    if vim.uv.fs_stat(root .. "/" .. name) then
      return root .. "/" .. name
    end
  end
  return "jest.config.js"
end

return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "marilari88/neotest-vitest",
      "nvim-neotest/neotest-jest",
    },
    opts = {
      adapters = {
        ["neotest-vitest"] = {},
        ["neotest-jest"] = { jestConfigFile = jest_config },
      },
    },
  },
}
