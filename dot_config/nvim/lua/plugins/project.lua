local manual_override = vim.g.project_manual_mode_override
return {
  -- https://github.com/ahmedkhalf/project.nvim
  "ahmedkhalf/project.nvim",
  config = function()
    require("project_nvim").setup({
      manual_mode = (manual_override == true) or (manual_override == 1) or false,
    })
  end,
}
