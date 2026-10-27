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
      opts.settings.java.configuration = { runtimes = require("util.jdks").discover() }
      -- debug: resolveJavaExecutable de una en una (ver lua/util/jdtls_serial.lua)
      require("util.jdtls_serial").apply()
    end,
  },

  -- pom.xml: autocompletado y validación (también formatea)
  { "mason-org/mason.nvim", opts = { ensure_installed = { "lemminx" } } },
  { "neovim/nvim-lspconfig", opts = { servers = { lemminx = {} } } },

  -- nombre del archivo en `public class |` (ver lua/util/blink_java_class.lua)
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      table.insert(opts.sources.default, "java_class")
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.java_class = {
        name = "JavaClass",
        module = "util.blink_java_class",
        score_offset = 100,
      }
    end,
  },
}
