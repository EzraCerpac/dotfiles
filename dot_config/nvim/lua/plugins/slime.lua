return {
  "jpalardy/vim-slime",
  init = function()
    vim.g.slime_target = "neovim"
    vim.g.slime_no_mappings = true
    vim.g.slime_suggest_default = true
    vim.g.slime_menu_config = true -- use menu to pick terminal
    vim.g.slime_bracketed_paste = 1

    -- Auto-find terminal job ID when slime needs it (solves lazy-load timing issue)
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
  end,
  config = function() end,
  keys = {
    { "gz", "<Plug>SlimeMotionSend", desc = "Slime send (motion)", mode = "n" },
    { "gzz", "<Plug>SlimeLineSend", desc = "Slime send line", mode = "n" },
    { "gz", "<Plug>SlimeRegionSend", desc = "Slime send selection", mode = "x" },
    { "gzp", "<Plug>SlimeParagraphSend", desc = "Slime send paragraph", mode = "n" },
    { "gzc", "<Plug>SlimeConfig", desc = "Slime config", mode = "n" },
    {
      "gzf",
      function()
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
      end,
      desc = "Slime send file (include/exec)",
      mode = "n",
    },
  },
}
