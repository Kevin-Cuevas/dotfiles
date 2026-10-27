return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    -- Nombre de la máquina (hostname)
    local name = vim.uv.os_gethostname() or "HOST"

    -- Detectar si es Termux (usuarios que empiezan con u0_a)
    if (vim.uv.os_get_passwd().username or ""):match("^u0_a%d+$") then
      name = "TERMUX"
    end

    -- Banner ANSI Shadow, fuente en figlet/ (texto plano si no hay toilet)
    local header = name
    if vim.fn.executable("toilet") == 1 then
      local fonts = vim.fn.stdpath("config") .. "/figlet"
      local out = vim.system({ "toilet", "-d", fonts, "-f", "ansi_shadow", name }, { text = true }):wait()
      if out.code == 0 and out.stdout ~= "" then
        header = vim.trim(out.stdout)
      end
    end

    opts.dashboard = opts.dashboard or {}
    opts.dashboard.enabled = true
    opts.dashboard.preset = opts.dashboard.preset or {}
    opts.dashboard.preset.header = header
  end,
}
