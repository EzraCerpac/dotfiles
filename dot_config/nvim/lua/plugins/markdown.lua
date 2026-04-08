return {
  "iamcco/markdown-preview.nvim",
  cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  ft = { "markdown" },
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  config = function(plugin)
    local app_dir = plugin.dir .. "/app"
    local has_prebuilt = vim.fn.glob(app_dir .. "/bin/markdown-preview-*") ~= ""
    local has_node_runtime = vim.fn.isdirectory(app_dir .. "/node_modules/tslib") == 1

    if not has_prebuilt and not has_node_runtime then
      vim.fn["mkdp#util#install_sync"](true)
    end
  end,
  keys = {
    { "<localLeader>m", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Markdown Preview", ft = "markdown" },
  },
}
