-- Java mínimo para correr jdtls (1.63+: JavaSE-25)
local JDTLS_MIN_JAVA = 25

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- ruta fija, no default-java (21 en Debian 13) ni `sdk use`
      local jdk = require("util.jdks").for_target(JDTLS_MIN_JAVA)
      if jdk then
        table.insert(opts.cmd, "--java-executable=" .. jdk .. "/bin/java")
      else
        vim.notify(
          ("jdtls necesita JDK %d+: sdk install java <%d+>-tem (o bootstrap, opción 12)"):format(
            JDTLS_MIN_JAVA,
            JDTLS_MIN_JAVA
          ),
          vim.log.levels.WARN,
          { title = "jdtls" }
        )
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
