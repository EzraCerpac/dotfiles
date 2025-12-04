return {
  "jpalardy/vim-slime",
  init = function()
    vim.g.slime_target = "neovim"
    vim.g.slime_no_mappings = true
    vim.g.slime_suggest_default = true
    vim.g.slime_menu_config = true -- use menu to pick terminal
    vim.g.slime_bracketed_paste = 1
  end,
  config = function()
    -- Scan all existing buffers to find terminals that were created before slime loaded
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
        if buftype == "terminal" then
          vim.fn["slime#targets#neovim#SlimeAddChannel"](buf)
        end
      end
    end
  end,
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
