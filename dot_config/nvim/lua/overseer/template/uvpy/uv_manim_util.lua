local M = {}

-- Quality presets for Manim
M.quality_presets = {
  preview_low = "-pql",
  preview_medium = "-pqm", 
  preview_high = "-pqh",
  low = "-ql",
  medium = "-qm", 
  high = "-qh",
  fourk = "-qk"
}

-- Default quality (fast preview)
M.default_quality = "preview_low"

-- Find all Scene classes in current buffer
function M.find_scene_classes()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local scenes = {}
  
  for i, line in ipairs(lines) do
    -- Look for class definitions that inherit from Scene
    local class_name = line:match("^%s*class%s+(%w+)%s*%(%s*Scene%s*%)")
    if class_name then
      table.insert(scenes, {
        name = class_name,
        line = i,
        text = line:match("^%s*(.*)")
      })
    end
  end
  
  return scenes
end

-- Find Scene class under cursor
function M.get_scene_under_cursor()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local scenes = M.find_scene_classes()
  
  -- Find the last scene class definition before cursor
  local current_scene = nil
  for _, scene in ipairs(scenes) do
    if scene.line <= cursor_line then
      current_scene = scene
    else
      break
    end
  end
  
  return current_scene
end

-- Validate that file contains Manim imports
function M.validate_manim_file()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local has_manim_import = false
  
  for _, line in ipairs(lines) do
    if line:match("import%s+manim") or line:match("from%s+manim%s+import") then
      has_manim_import = true
      break
    end
  end
  
  return has_manim_import
end

-- Get quality flag from preset name
function M.get_quality_flag(preset)
  return M.quality_presets[preset] or M.default_quality
end

-- Build Manim command arguments
function M.build_manim_args(file, scene_name, quality_preset, extra_args)
  local quality_flag = M.get_quality_flag(quality_preset or M.default_quality)
  local args = { quality_flag, file, scene_name }
  
  -- Add extra args if provided
  if extra_args and extra_args ~= "" then
    local util = require("overseer.template.uvpy.util")
    local extra = util.split_args(extra_args)
    for _, arg in ipairs(extra) do
      table.insert(args, arg)
    end
  end
  
  return args
end

-- Show notification with Manim-specific styling
function M.notify(message, level)
  level = level or vim.log.levels.INFO
  vim.notify("[Manim] " .. message, level, { title = "Manim" })
end

-- Pick scene using telescope if available, otherwise vim.ui.select
function M.pick_scene(scenes, on_select)
  if not scenes or #scenes == 0 then
    M.notify("No Scene classes found", vim.log.levels.WARN)
    return
  end
  
  local choices = {}
  for _, scene in ipairs(scenes) do
    table.insert(choices, {
      name = scene.name,
      line = scene.line,
      display = string.format("%s (line %d)", scene.name, scene.line)
    })
  end
  
  -- Try telescope first
  local ok, pickers = pcall(require, 'telescope.pickers')
  local ok_finders, finders = pcall(require, 'telescope.finders')
  local ok_actions, actions = pcall(require, 'telescope.actions')
  local ok_config, config = pcall(require, 'telescope.config')
  
  if ok and ok_finders and ok_actions and ok_config then
    pickers.new({}, {
      prompt_title = "Manim Scenes",
      finder = finders.new_table({
        results = choices,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.name
          }
        end
      }),
      sorter = config.values.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = actions.get_selected_entry()
          on_select(selection.value)
        end)
        return true
      end
    }):find()
  else
    -- Fallback to vim.ui.select
    vim.ui.select(choices, {
      prompt = "Select Scene:",
      format_item = function(item) return item.display end
    }, function(choice)
      if choice then
        on_select(choice)
      end
    end)
  end
end

return M