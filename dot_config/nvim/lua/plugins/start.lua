return {
  -- https://github.com/nvim-mini/mini.starter
  "nvim-mini/mini.starter",
  version = "*", -- wait till new 0.7.0 release to put it back on semver
  event = "VimEnter",
  opts = function(_, opts)
    local logo = table.concat({
      "                        ██╗   ██╗██╗███╗   ███╗          Z",
      "                        ██║   ██║██║████╗ ████║      Z    ",
      "                        ██║   ██║██║██╔████╔██║   z       ",
      "                        ╚██╗ ██╔╝██║██║╚██╔╝██║ z         ",
      "                         ╚████╔╝ ██║██║ ╚═╝ ██║           ",
      "                          ╚═══╝  ╚═╝╚═╝     ╚═╝           ",
    }, "\n")

    local starter = require("mini.starter")

    local function build_footer(stats)
      local lines = {
        "Enter opens the current item  |  Type to filter  |  Ctrl-c closes",
      }

      if stats then
        local ms = math.floor(stats.startuptime * 100 + 0.5) / 100
        lines[#lines + 1] = "Neovim loaded " .. stats.count .. " plugins in " .. ms .. "ms"
      end

      return table.concat(lines, "\n")
    end

    local function recent_files()
      local items = starter.sections.recent_files(5, true, true)()
      for _, item in ipairs(items) do
        item.section = "Recent Files"
      end
      return items
    end

    local function recent_project_paths(limit)
      local projects = {}
      local seen = {}

      local function add(path)
        if type(path) ~= "string" or path == "" then
          return
        end
        if seen[path] or vim.fn.isdirectory(path) == 0 then
          return
        end
        seen[path] = true
        projects[#projects + 1] = path
      end

      local ok_history, history = pcall(require, "project_nvim.utils.history")
      if ok_history then
        for _, path in ipairs(history.get_recent_projects() or {}) do
          add(path)
        end
      end

      if #projects == 0 then
        local ok_path, path_utils = pcall(require, "project_nvim.utils.path")
        if ok_path and vim.fn.filereadable(path_utils.historyfile) == 1 then
          for _, path in ipairs(vim.fn.readfile(path_utils.historyfile)) do
            add(path)
          end
        end
      end

      for i = 1, math.floor(#projects / 2) do
        local j = #projects - i + 1
        projects[i], projects[j] = projects[j], projects[i]
      end

      return vim.list_slice(projects, 1, limit)
    end

    local function open_project_recent_files(project_path)
      local ok_project, project = pcall(require, "project_nvim.project")
      if ok_project then
        project.set_pwd(project_path, "mini.starter")
      end
      LazyVim.pick("oldfiles", { cwd = project_path })()
    end

    local function recent_projects()
      local items = {}
      for _, project_path in ipairs(recent_project_paths(4)) do
        local name = vim.fn.fnamemodify(project_path, ":t")
        if name == "" then
          name = project_path
        end

        items[#items + 1] = {
          action = function()
            open_project_recent_files(project_path)
          end,
          name = name .. " (" .. vim.fn.fnamemodify(project_path, ":~") .. ")",
          section = "Recent Projects",
        }
      end

      if #items == 0 then
        return {
          {
            name = "No recent projects in project history",
            action = "",
            section = "Recent Projects",
          },
        }
      end

      return items
    end

    local function item(name, action, section)
      return { name = name, action = action, section = section }
    end

    local function collapse_single_item_sections(content)
      local remove = {}
      local line = 1

      while line <= #content do
        local content_line = content[line]
        local section_unit = content_line and content_line[1]

        if #content_line == 1 and section_unit and section_unit.type == "section" then
          local item_count = 0
          local next_line = line + 1

          while next_line <= #content do
            local next_content_line = content[next_line]
            local next_unit = next_content_line and next_content_line[1]

            if #next_content_line == 1 and next_unit and next_unit.type == "section" then
              break
            end

            if next_unit and next_unit.type == "item" then
              item_count = item_count + 1
            end

            next_line = next_line + 1
          end

          if item_count == 1 then
            remove[line] = true
          end

          line = next_line
        else
          line = line + 1
        end
      end

      if next(remove) == nil then
        return content
      end

      local filtered = {}
      for i, content_line in ipairs(content) do
        if not remove[i] then
          filtered[#filtered + 1] = content_line
        end
      end

      return filtered
    end

    opts = opts or {}
    opts.evaluate_single = true
    opts.header = logo
    opts.footer = build_footer()
    opts.items = {
      item("Restore session", [[lua require("persistence").load()]], "Session"),
      recent_files,
      item("Find files", LazyVim.pick(), "Find Files"),
      recent_projects,
      item("Quit", "qa", "Quit"),
    }
    opts.content_hooks = {
      collapse_single_item_sections,
      starter.gen_hook.adding_bullet(":: ", false),
      starter.gen_hook.aligning("center", "center"),
    }

    return opts
  end,
  config = function(_, config)
    if vim.o.filetype == "lazy" then
      vim.cmd.close()
      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniStarterOpened",
        callback = function()
          require("lazy").show()
        end,
      })
    end

    local function set_start_highlights()
      local palette = {
        blue = "#89b4fa",
        green = "#a6e3a1",
        lavender = "#b4befe",
        overlay0 = "#6c7086",
        overlay1 = "#7f849c",
        teal = "#94e2d5",
        yellow = "#f9e2af",
      }

      local ok_palette, catppuccin = pcall(function()
        return require("catppuccin.palettes").get_palette()
      end)
      if ok_palette and catppuccin then
        palette = vim.tbl_extend("force", palette, catppuccin)
      end

      vim.api.nvim_set_hl(0, "MiniStarterHeader", { bold = true, fg = palette.lavender })
      vim.api.nvim_set_hl(0, "MiniStarterSection", { bold = true, fg = palette.blue })
      vim.api.nvim_set_hl(0, "MiniStarterCurrent", { bold = true, fg = palette.yellow })
      vim.api.nvim_set_hl(0, "MiniStarterFooter", { fg = palette.overlay1, italic = true })
      vim.api.nvim_set_hl(0, "MiniStarterItemBullet", { fg = palette.overlay0 })
      vim.api.nvim_set_hl(0, "MiniStarterItemPrefix", { bold = true, fg = palette.green })
    end

    local starter = require("mini.starter")
    starter.setup(config)
    set_start_highlights()

    local hl_group = vim.api.nvim_create_augroup("ezra_mini_starter_highlights", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = hl_group,
      callback = set_start_highlights,
    })

    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyVimStarted",
      callback = function(ev)
        local stats = require("lazy").stats()
        starter.config.footer = table.concat({
          "Enter opens the current item  |  Type to filter  |  Ctrl-c closes",
          "Neovim loaded "
            .. stats.count
            .. " plugins in "
            .. (math.floor(stats.startuptime * 100 + 0.5) / 100)
            .. "ms",
        }, "\n")

        if vim.bo[ev.buf].filetype == "ministarter" then
          pcall(starter.refresh)
        end
      end,
    })
  end,
}
