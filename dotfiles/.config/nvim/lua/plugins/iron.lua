return {
  "Vigemus/iron.nvim",
  config = function()
    local iron = require("iron.core")
    local view = require("iron.view")

    iron.setup({
      config = {
        -- Whether a repl should be discarded or not
        scratch_repl = true,
        -- REPL definitions for different languages
        repl_definition = {
          julia = {
            command = { "julia", "--banner=no", "--project=." },
            -- Use bracketed paste for multi-line code
            format = require("iron.fts.common").bracketed_paste,
          },
          python = {
            command = { "uv", "run", "python" },
            format = require("iron.fts.common").bracketed_paste_python,
            env = { PYTHON_BASIC_REPL = "1" }, -- needed for Python 3.13+
          },
        },
        -- REPL opens in a vertical split on the right (40% of screen width)
        repl_open_cmd = view.split.vertical.botright("40%"),
      },
      -- Don't set keymaps in iron.setup, we'll set them manually with descriptions
      keymaps = {},
      -- Highlight sent text
      highlight = {
        italic = true,
      },
      ignore_blank_lines = true, -- ignore blank lines when sending visual selections
    })

    -- Register which-key group
    local wk_ok, wk = pcall(require, "which-key")
    if wk_ok then
      wk.add({
        { "<leader>r", group = "REPL" },
        { "<leader>rm", group = "Mark" },
      })
    end

    -- Set up all keymaps manually with proper descriptions
    -- REPL management
    vim.keymap.set("n", "<leader>rr", "<cmd>IronRepl<cr>", { desc = "Toggle" })
    vim.keymap.set("n", "<leader>rR", "<cmd>IronRestart<cr>", { desc = "Restart" })
    vim.keymap.set("n", "<leader>rF", "<cmd>IronFocus<cr>", { desc = "Focus" })
    vim.keymap.set("n", "<leader>rh", "<cmd>IronHide<cr>", { desc = "Hide" })
    vim.keymap.set("n", "<leader>rq", function() require("iron.core").close_repl() end, { desc = "Quit" })
    vim.keymap.set("n", "<leader>rc", function() require("iron.core").send(nil, { "\x0c" }) end, { desc = "Clear" })
    vim.keymap.set("n", "<leader>r<space>", function() require("iron.core").send(nil, { "\x03" }) end, { desc = "Interrupt" })
    
    -- Send code
    vim.keymap.set("n", "<leader>rl", function() require("iron.core").send_line() end, { desc = "Line" })
    vim.keymap.set("n", "<leader>rs", function() require("iron.core").send_motion("") end, { desc = "Motion", expr = true })
    vim.keymap.set("v", "<leader>rs", function() require("iron.core").visual_send() end, { desc = "Selection" })
    vim.keymap.set("n", "<leader>rp", function() require("iron.core").send_motion("ap") end, { desc = "Paragraph" })
    vim.keymap.set("n", "<leader>rf", function() require("iron.core").send_file() end, { desc = "File" })
    vim.keymap.set("n", "<leader>ru", function() require("iron.core").send_until_cursor() end, { desc = "Until Cursor" })
    vim.keymap.set("n", "<leader>r<cr>", function() require("iron.core").send(nil, { "\r" }) end, { desc = "Send CR" })
    
    -- Mark management
    vim.keymap.set("n", "<leader>rms", function() require("iron.core").send_mark() end, { desc = "Send" })
    vim.keymap.set("n", "<leader>rmc", function() require("iron.core").mark_motion("") end, { desc = "Create", expr = true })
    vim.keymap.set("v", "<leader>rmc", function() require("iron.core").mark_visual() end, { desc = "Create" })
    vim.keymap.set("n", "<leader>rmd", function() require("iron.core").remove_mark() end, { desc = "Delete" })
  end,
  -- Lazy load on filetype or command
  ft = { "julia", "python" },
  cmd = { "IronRepl", "IronFocus", "IronHide", "IronRestart", "IronAttach" },
}
