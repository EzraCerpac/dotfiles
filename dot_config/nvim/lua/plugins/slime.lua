return {
  "jpalardy/vim-slime",
  init = function()
    -- Must be set before plugin loads
    vim.g.slime_target = "neovim"
    vim.g.slime_no_mappings = true
  end,
  config = function()
    vim.g.slime_suggest_default = true
    vim.g.slime_menu_config = false -- disable menu, use auto-config instead
    vim.g.slime_bracketed_paste = 1

    -- Auto-find terminal job ID (solves lazy-load timing issue with overseer terminals)
    vim.g.slime_get_jobid = function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
          if buftype == "terminal" then
            local chan = vim.api.nvim_get_option_value("channel", { buf = bufnr })
            if chan and chan > 0 then
              return chan
            end
          end
        end
      end
      return nil
    end

    -- Helper: start a REPL in a split using native :terminal
    local function start_repl(cmd, name)
      -- Open a vertical split on the right
      vim.cmd("vsplit")
      vim.cmd("wincmd L")
      -- Start terminal with the command
      vim.fn.termopen(cmd, { detach = false })
      -- Name the buffer for easier identification
      vim.api.nvim_buf_set_name(0, name or cmd)
      -- Go back to previous window
      vim.cmd("wincmd p")
    end

    -- Set up keymaps (must use remap=true for <Plug> mappings)
    vim.keymap.set("n", "gz", "<Plug>SlimeMotionSend", { remap = true, silent = false, desc = "Slime send (motion)" })
    vim.keymap.set("n", "gzz", "<Plug>SlimeLineSend", { remap = true, silent = false, desc = "Slime send line" })
    vim.keymap.set("x", "gz", "<Plug>SlimeRegionSend", { remap = true, silent = false, desc = "Slime send selection" })
    vim.keymap.set("n", "gzp", "<Plug>SlimeParagraphSend", { remap = true, silent = false, desc = "Slime send paragraph" })
    vim.keymap.set("n", "gzc", "<Plug>SlimeConfig", { remap = true, silent = false, desc = "Slime config" })

    -- Start Julia REPL
    vim.keymap.set("n", "gzj", function()
      start_repl("julia --banner=no --project=.", "Julia REPL")
    end, { desc = "Start Julia REPL" })

    -- Start Python REPL (uv)
    vim.keymap.set("n", "gzP", function()
      start_repl("uv run python", "Python REPL")
    end, { desc = "Start Python REPL (uv)" })

    -- Send whole file
    vim.keymap.set("n", "gzf", function()
      local file = vim.fn.expand("%:p")
      local ft = vim.bo.filetype
      local cmd
      if ft == "julia" then
        cmd = string.format('include("%s")\n', file)
      elseif ft == "python" then
        cmd = string.format('exec(open("%s").read())\n', file)
      else
        vim.notify("gzf: unsupported filetype " .. ft, vim.log.levels.WARN)
        return
      end
      vim.fn["slime#send"](cmd)
    end, { desc = "Slime send file (include/exec)" })
  end,
  -- Load on first keypress or command
  keys = { "gz" },
  cmd = { "SlimeConfig", "SlimeSend", "SlimeSend1" },
}
