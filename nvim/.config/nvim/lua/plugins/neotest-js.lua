-- Tests de JS/TS en neotest (extra test.core) ==> vitest y jest juntos. Los
-- adapters no son binarios (Mason no los tiene) ni hay un extra de LazyVim
-- para ellos: son plugins. Cada uno solo reclama archivos de proyectos que lo
-- tienen en package.json, así que no se pisan entre sí.

-- neotest-jest busca jest.config.{js,ts} con vim.fn.glob al armar el comando,
-- desde un callback de libuv ==> E5560 ("must not be called in a fast event
-- context") y el test nunca corre. La misma búsqueda con vim.fs.root (solo
-- libuv) sí se puede ahí. Si no hay config devuelve la ruta por defecto del
-- adapter, que solo la pasa como --config cuando existe.
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
