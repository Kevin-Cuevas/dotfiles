-- CTRL+/ terminal ==> bottom split like the LazyVim original. A split can't have
-- a real float border/title, so its "header" is the winbar: we replace the
-- default "1: term://.../zsh" with "󰆍 Terminal". Edit it here:
--   left  -> "  󰆍 Terminal"      right -> "%=󰆍 Terminal"      center -> "%=󰆍 Terminal%="
local function bottom_terminal()
  Snacks.terminal.toggle(nil, {
    count = 1,
    cwd = LazyVim.root(),
    win = {
      style = "terminal",
      position = "bottom",
      height = 0.4,
      wo = { winbar = "%=󰆍 Terminal%=" },
    },
    interactive = true,
    auto_close = true,
  })
end

return {
  {
    "folke/snacks.nvim",
    keys = {
      -- CTRL+/ TERMINAL ==> bottom split (overrides the LazyVim default only to
      -- give it a clean winbar; still a split, not a float).
      { "<C-/>", bottom_terminal, mode = { "n", "t" }, desc = "Terminal (bottom)" },
      { "<C-_>", bottom_terminal, mode = { "n", "t" }, desc = "which_key_ignore" },

      -- SMART TOGGLE ==> Prioritize active run buffer over scratch
      {
        "<C-\\>",
        function()
          if _G.Run and _G.Run.buf and vim.api.nvim_buf_is_valid(_G.Run.buf) then
            _G.Run:toggle()
          else
            Snacks.terminal.toggle(nil, {
              count = 2,
              win = {
                style = "float",
                width = 0.9,
                height = 0.8,
                border = "rounded",
                title = "󰆍 Terminal ",
                title_pos = "center",
                wo = { winblend = 0, winhighlight = "Normal:Normal,FloatBorder:FloatBorder" },
                backdrop = false,
              },
              interactive = true,
              auto_close = true,
            })
          end
        end,
        mode = { "n", "t" },
        desc = "Smart terminal toggle",
      },

      -- RUN GROUP ==> <leader> + r (name shown in which-key)
      { "<leader>r", "", desc = "+run" },

      -- RUN COMMAND ==> <leader> + r + r  (alias: F5), see util/runner.lua
      {
        "<leader>rr",
        function()
          require("util.runner").run()
        end,
        desc = "Execute file",
      },
      { "<F5>", "<leader>rr", remap = true, desc = "Execute file" },

      -- ARGS RUNNER ==> <leader> + r + a  (alias: F6)
      {
        "<leader>ra",
        function()
          require("util.runner").run_with_args()
        end,
        desc = "Run with args",
      },
      { "<F6>", "<leader>ra", remap = true, desc = "Run with args" },

      -- PROCESS LIST ==> <leader> + r + l: what the runner launched, to show,
      -- kill (<C-x>) or restart (<C-e>) it, see util/runner_procs.lua
      {
        "<leader>rl",
        function()
          require("util.runner").processes()
        end,
        desc = "Run processes",
      },
    },
  },
}
