return {
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerToggle", "OverseerRun", "OverseerBuild" },
    opts = function(_, opts)
      -- Merge with any existing opts from other specs/dependencies
      opts = opts or {}

      -- Ensure our template bundle is loaded alongside builtins
      local templates = opts.templates or {}
      local has_builtin = false
      for _, t in ipairs(templates) do
        if t == "builtin" then
          has_builtin = true
        end
      end
      if not has_builtin then
        table.insert(templates, 1, "builtin")
      end
      -- Add our Python namespace once
      local has_uvpy = false
      for _, t in ipairs(templates) do
        if t == "uvpy" then
          has_uvpy = true
        end
      end
      if not has_uvpy then
        table.insert(templates, "uvpy")
      end
      -- Add our Julia namespace once
      local has_julia = false
      for _, t in ipairs(templates) do
        if t == "julia" then
          has_julia = true
        end
      end
      if not has_julia then
        table.insert(templates, "julia")
      end
      opts.templates = templates

      -- A small alias we can attach to tasks
      local aliases = opts.component_aliases or {}
      aliases.uvpy_default = aliases.uvpy_default
        or { "default", { "on_complete_notify", statuses = { "SUCCESS", "FAILURE" } }, { "uvpy.env" } }
      opts.component_aliases = aliases

      -- Custom action: prompt for args and rerun (works with our uvpy tasks)
      local actions = opts.actions or {}
      actions["uvpy: set args and rerun"] = {
        desc = "Prompt for CLI args, then restart the task",
        condition = function(task)
          return task.metadata and task.metadata.uvpy ~= nil and task.get_definition ~= nil
        end,
        run = function(task)
          local util = require("overseer.template.uvpy.util")
          local defn = task:get_definition()
          if not defn then
            return
          end
          local base = task.metadata.uvpy.base_args or {}
          local cur_tail = util.args_tail(defn.args or {}, base)
          local default_txt = util.join_args(cur_tail)
          vim.ui.input({ prompt = "Args: ", default = default_txt }, function(input)
            if input == nil then
              return
            end
            local new_args = util.extend_args(base, util.split_args(input))
            defn.args = new_args
            task:reset(defn)
            task:start()
          end)
        end,
      }
      opts.actions = actions

      return opts
    end,
    config = function(_, opts)
      local overseer = require("overseer")
      overseer.setup(opts)
      -- Add a universal hook so any task created via a template opens the task list on start.
      -- This catches :OverseerRun and our keymaps alike.
      if overseer.add_template_hook then
        overseer.add_template_hook({ module = "^uvpy%.[a-z_]+$" }, function(task_defn, util)
          util.add_component(task_defn, { "uvpy.open_list", enter = false })
        end)
      end
    end,
    init = function()
      -- Ensure overseer is loaded for Python and Julia buffers so templates are available
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "python", "julia" },
        callback = function()
          pcall(function()
            require("lazy").load({ plugins = { "overseer.nvim" } })
          end)
        end,
      })
    end,
    -- stylua: ignore
    keys = {
      {
        "<leader>opr",
        function()
          require("lazy").load({ plugins = { "overseer.nvim" } })
          local ok, overseer = pcall(require, "overseer")
          if not ok then return end
          overseer.run_template({ name = "Python: Run Current File (uv)", params = { args = "" } }, function(task)
            if task then overseer.open({ enter = false }) end
          end)
        end,
        desc = "Run current Python (uv)",
      },
      {
        "<leader>opR",
        function()
          require("lazy").load({ plugins = { "overseer.nvim" } })
          local ok, overseer = pcall(require, "overseer")
          if not ok then return end
          vim.ui.input({ prompt = "Args for current file: " }, function(input)
            if input == nil then return end
            overseer.run_template({ name = "Python: Run Current File (uv)", params = { args = input } }, function(task)
              if task then overseer.open({ enter = false }) end
            end)
          end)
        end,
        desc = "Run current Python (prompt args)",
      },
      {
        "<leader>opm",
        function()
          require("lazy").load({ plugins = { "overseer.nvim" } })
          local util = require("overseer.template.uvpy.util")
          local root = util.project_root()
          local cache = vim.g.uvpy_main_cache or {}
          local main = cache[root]
          if not main then
            local candidates = { root .. "/main.py", root .. "/app.py", vim.fn.expand("%:p") }
            for _, p in ipairs(candidates) do if vim.uv.fs_stat(p) then main = p break end end
            main = main or vim.fn.expand("%:p")
            cache[root] = main
            vim.g.uvpy_main_cache = cache
          end
          local ok, overseer = pcall(require, "overseer")
          if not ok then return end
          overseer.run_template({ name = "Python: Run Main File (uv)", params = { main = main, args = "" } }, function(task)
            if task then overseer.open({ enter = false }) end
          end)
        end,
        desc = "Run main Python (uv)",
      },
      {
        "<leader>opM",
        function()
          require("lazy").load({ plugins = { "overseer.nvim" } })
          local util = require("overseer.template.uvpy.util")
          local pick = require("overseer.template.uvpy.pickers")
          local ok, overseer = pcall(require, "overseer")
          if not ok then return end
          pick.pick_main({}, function(main)
            local root = util.project_root()
            local cache = vim.g.uvpy_main_cache or {}
            cache[root] = main
            vim.g.uvpy_main_cache = cache
            vim.ui.input({ prompt = "Args for main: ", default = "" }, function(args)
              if args == nil then return end
              overseer.run_template({ name = "Python: Run Main File (uv)", params = { main = main, args = args } }, function(task)
                if task then overseer.open({ enter = false }) end
              end)
            end)
          end)
        end,
        desc = "Run main Python (prompt)",
      },
      {
        "<leader>opa",
        function()
          require("lazy").load({ plugins = { "overseer.nvim" } })
          vim.cmd([[OverseerQuickAction uvpy:\ set\ args\ and\ rerun]])
        end,
        desc = "Set args + rerun (uvpy)",
      },
      -- REPL keymaps (gzj, gzP) are now in plugins/slime.lua for better vim-slime integration
    },
  },
}
