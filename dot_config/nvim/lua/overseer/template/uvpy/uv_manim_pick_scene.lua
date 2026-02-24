local util = require("overseer.template.uvpy.util")
local manim_util = require("overseer.template.uvpy.uv_manim_util")
local overseer = require("overseer")

local function scene_param()
  local scenes = manim_util.find_scene_classes()
  if #scenes <= 1 then
    return nil
  end

  local choices = {}
  for _, scene in ipairs(scenes) do
    table.insert(choices, scene.name)
  end

  return {
    desc = "Scene class to render",
    type = "enum",
    choices = choices,
  }
end

return {
  name = "Manim: Pick Scene to Render",
  desc = "Interactive selection of Scene class to render with uv",
  tags = { overseer.TAG.RUN },
  priority = 50,
  condition = {
    filetype = { "python" },
  },
  params = function()
    local params = {
      quality = {
        desc = "Quality preset for rendering",
        type = "string",
        optional = true,
        default = manim_util.default_quality,
        choices = { "preview_low", "preview_medium", "preview_high", "low", "medium", "high", "fourk" },
      },
      extra_args = {
        desc = "Additional command line arguments",
        type = "string",
        optional = true,
        default = "",
      },
      interpreter = {
        desc = "Interpreter executable",
        type = "string",
        optional = true,
        default = "uv",
      },
    }

    local scene = scene_param()
    if scene then
      params.scene = scene
    end
    return params
  end,
  builder = function(params)
    -- Validate that this is a Manim file
    if not manim_util.validate_manim_file() then
      return manim_util.failure_task("No Manim import found. Please add 'import manim' or 'from manim import ...' to your file.")
    end
    
    -- Get all scenes in file
    local scenes = manim_util.find_scene_classes()
    if #scenes == 0 then
      return manim_util.failure_task("No Scene classes found in file. Make sure you have classes that inherit from Scene.")
    end

    local selected_scene
    if #scenes == 1 then
      selected_scene = scenes[1]
    else
      for _, scene in ipairs(scenes) do
        if scene.name == params.scene then
          selected_scene = scene
          break
        end
      end
      if not selected_scene then
        return manim_util.failure_task("No Scene selected. Choose a Scene class and run again.")
      end
    end

    local file = vim.fn.expand("%:t")
    local cwd = util.project_root()
    local base_args = { "run", "python", "-m", "manim" }
    local manim_args = manim_util.build_manim_args(file, selected_scene.name, params.quality, params.extra_args)
    local all_args = util.extend_args(base_args, manim_args)
    local quality_desc = (params.quality or manim_util.default_quality):gsub("_", " ")
    local task_name = string.format("Manim: %s (%s)", selected_scene.name, quality_desc)

    return {
      name = task_name,
      cmd = { params.interpreter },
      args = all_args,
      cwd = cwd,
      components = { "uvpy_default" },
      metadata = {
        uvpy = {
          kind = "manim",
          base_args = base_args,
          scene = selected_scene.name,
          file = file,
        },
      },
    }
  end,
}
