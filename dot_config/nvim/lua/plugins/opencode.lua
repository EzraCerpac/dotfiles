-- opencode.nvim integration
-- Installs the plugin and provides keymaps under <leader>c (instead of the README's <leader>o)
-- Dependency: folke/snacks.nvim

return {
  "NickvanDyke/opencode.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  ---@type opencode.Config
  opts = {
    -- You can add custom prompts or contexts here later, e.g.:
    -- prompts = { },
    -- contexts = { },
  },
  -- stylua: ignore
  keys = {
    { "<leader>Ot", function() require("opencode").toggle() end, desc = "Toggle embedded opencode" },
    { "<leader>Oa", function() require("opencode").ask("@cursor: ") end, desc = "Ask opencode", mode = "n" },
    { "<leader>Oa", function() require("opencode").ask("@selection: ") end, desc = "Ask opencode about selection", mode = "v" },
    { "<leader>Op", function() require("opencode").select_prompt() end, desc = "Select prompt", mode = { "n", "v" } },
    { "<leader>On", function() require("opencode").command("session_new") end, desc = "New session" },
    { "<leader>Oy", function() require("opencode").command("messages_copy") end, desc = "Copy last message" },
    { "<S-C-u>",    function() require("opencode").command("messages_half_page_up") end,   desc = "Scroll messages up" },
    { "<S-C-d>",    function() require("opencode").command("messages_half_page_down") end, desc = "Scroll messages down" },
  },
}
