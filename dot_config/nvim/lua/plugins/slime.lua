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

    -- Set up keymaps (must use remap=true for <Plug> mappings)
    vim.keymap.set("n", "gz", "<Plug>SlimeMotionSend", { remap = true, silent = false, desc = "Slime send (motion)" })
    vim.keymap.set("n", "gzz", "<Plug>SlimeLineSend", { remap = true, silent = false, desc = "Slime send line" })
    vim.keymap.set("x", "gz", "<Plug>SlimeRegionSend", { remap = true, silent = false, desc = "Slime send selection" })
    vim.keymap.set("n", "gzp", "<Plug>SlimeParagraphSend", { remap = true, silent = false, desc = "Slime send paragraph" })
    vim.keymap.set("n", "gzc", "<Plug>SlimeConfig", { remap = true, silent = false, desc = "Slime config" })

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
