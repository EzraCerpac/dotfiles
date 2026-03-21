return {
  "iamcco/markdown-preview.nvim",
  cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  ft = { "markdown" },
  build = function(plugin)
    vim.fn["mkdp#util#install_sync"](true)

    local app_dir = plugin.dir .. "/app"
    if vim.fn.isdirectory(app_dir .. "/node_modules/tslib") == 1 then
      return
    end

    local install_cmd = nil
    if vim.fn.executable("corepack") == 1 then
      install_cmd = { "corepack", "yarn", "install", "--frozen-lockfile" }
    elseif vim.fn.executable("yarn") == 1 then
      install_cmd = { "yarn", "install", "--frozen-lockfile" }
    end

    if not install_cmd then
      vim.notify("markdown-preview.nvim: missing Node dependencies and no yarn/corepack found", vim.log.levels.WARN)
      return
    end

    local result = vim.system(install_cmd, { cwd = app_dir, text = true }):wait()
    if result.code ~= 0 then
      vim.notify("markdown-preview.nvim yarn install failed: " .. (result.stderr or ""), vim.log.levels.WARN)
    end
  end,
  keys = {
    { "<localLeader>m", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Markdown Preview", ft = "markdown" },
  },
}
