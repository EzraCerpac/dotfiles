return {
  -- https://github.com/ahmedkhalf/project.nvim
  "ahmedkhalf/project.nvim",
  config = function()
    require("project_nvim").setup({
      manual_mode = vim.g.project_manual_mode_override or false,
    })
  end,
}
