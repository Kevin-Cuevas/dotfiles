-- Minimum Java to run jdtls (1.63+: JavaSE-25)
local JDTLS_MIN_JAVA = 25

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- fixed path, not default-java (21 on Debian 13) nor `sdk use`
      local jdk = require("util.jdks").for_target(JDTLS_MIN_JAVA)
      if jdk then
        table.insert(opts.cmd, "--java-executable=" .. jdk .. "/bin/java")
      else
        vim.notify(
          ("jdtls needs JDK %d+: sdk install java <%d+>-tem (or bootstrap, option 12)"):format(
            JDTLS_MIN_JAVA,
            JDTLS_MIN_JAVA
          ),
          vim.log.levels.WARN,
          { title = "jdtls" }
        )
      end
      -- JDKs your projects are compiled against
      opts.settings.java.configuration = { runtimes = require("util.jdks").discover() }
      -- debug: resolveJavaExecutable one at a time (see lua/util/jdtls_serial.lua)
      require("util.jdtls_serial").apply()
    end,
  },

  -- pom.xml: completion and validation (also formats)
  { "mason-org/mason.nvim", opts = { ensure_installed = { "lemminx" } } },
  { "neovim/nvim-lspconfig", opts = { servers = { lemminx = {} } } },

  -- file name on `public class |` (see lua/util/blink_java_class.lua)
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
