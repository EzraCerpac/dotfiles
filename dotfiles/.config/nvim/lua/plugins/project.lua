return {
  {
    "ahmedkhalf/project.nvim",
    config = function(_, opts)
      require("project_nvim").setup(opts)

      local history = require("project_nvim.utils.history")
      history.delete_project = function(project)
        for k, v in pairs(history.recent_projects) do
          if v == project.value then
            history.recent_projects[k] = nil
            return
          end
        end
      end

      LazyVim.on_load("telescope.nvim", function()
        require("telescope").load_extension("projects")
      end)

      local project = require("project_nvim.project")

      local function resolve_project_dir()
        local current_dir = vim.fn.expand("%:p:h", true)
        if type(current_dir) == "string" and current_dir ~= "" and vim.fn.isdirectory(current_dir) == 1 then
          return current_dir
        end

        local cwd = vim.uv.cwd()
        if type(cwd) == "string" and cwd ~= "" and vim.fn.isdirectory(cwd) == 1 then
          return cwd
        end
      end

      vim.api.nvim_del_user_command("AddProject")
      vim.api.nvim_create_user_command("AddProject", function()
        local dir = resolve_project_dir()
        if not dir then
          vim.notify("AddProject failed: could not determine a valid project directory", vim.log.levels.ERROR)
          return
        end

        project.set_pwd(vim.fs.normalize(dir), "manual")
      end, { desc = "Add current buffer directory or cwd as a project" })
    end,
  },
}
