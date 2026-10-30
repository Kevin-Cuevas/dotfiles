-- Tests de JS/TS en neotest (extra test.core) ==> vitest y jest juntos. Los
-- adapters no son binarios (Mason no los tiene) ni hay un extra de LazyVim
-- para ellos: son plugins. Cada uno solo reclama archivos de proyectos que lo
-- tienen en package.json, así que no se pisan entre sí.
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
        ["neotest-jest"] = {},
      },
    },
  },
}
