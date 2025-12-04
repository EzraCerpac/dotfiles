return {
  "jpalardy/vim-slime",
  ft = { "julia", "python" },
  init = function()
    vim.g.slime_target = "neovim"
    vim.g.slime_no_mappings = true
  end,
  config = function()
    vim.g.slime_suggest_default = true
    vim.g.slime_menu_config = false
    vim.g.slime_bracketed_paste = 1

    -- gz prefix for slime (vim-style mappings)
    vim.keymap.set("n", "gz", "<Plug>SlimeMotionSend", { desc = "Slime send (motion)" })
    vim.keymap.set("n", "gzz", "<Plug>SlimeLineSend", { desc = "Slime send line" })
    vim.keymap.set("x", "gz", "<Plug>SlimeRegionSend", { desc = "Slime send selection" })
    vim.keymap.set("n", "gzp", "<Plug>SlimeParagraphSend", { desc = "Slime send paragraph" })
    vim.keymap.set("n", "gzc", "<Plug>SlimeConfig", { desc = "Slime config" })

    -- Send entire file via include() for Julia, exec() for Python
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
}
