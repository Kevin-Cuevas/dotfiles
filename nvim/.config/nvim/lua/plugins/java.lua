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
      opts.settings.java.configuration = { runtimes = require("config.jdks").discover() }
    end,
  },

  -- pom.xml: autocompletado y validación (también formatea)
  { "mason-org/mason.nvim", opts = { ensure_installed = { "lemminx" } } },
  { "neovim/nvim-lspconfig", opts = { servers = { lemminx = {} } } },
}
