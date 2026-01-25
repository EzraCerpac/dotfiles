local util = require("overseer.template.uvpy.util")
local manim_util = require("overseer.template.uvpy.uv_manim_util")
local overseer = require("overseer")

return {
  name = "Manim: Render Scene Under Cursor",
  desc = "Render the Manim Scene class under cursor with uv",
  tags = { overseer.TAG.RUN },
  priority = 50,
  condition = {
    filetype = { "python" },
  },
  params = {
    quality = {
      desc = "Quality preset for rendering",
      type = "string",
      optional = true,
      default = manim_util.default_quality,
      choices = { "preview_low", "preview_medium", "preview_high", "low", "medium", "high", "fourk" }
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
  },
  builder = function(params)
    -- Validate that this is a Manim file
    if not manim_util.validate_manim_file() then
      return nil, "No Manim import found. Please add 'import manim' or 'from manim import ...' to your file."
    end
    
    -- Get scene under cursor
    local scene = manim_util.get_scene_under_cursor()
    if not scene then
      return nil, "No Scene class found under cursor. Move cursor inside a Scene class definition."
    end
    
    local file = vim.fn.expand("%:t")
    local cwd = util.project_root()
    
    -- Build command: uv run python -m manim [quality] [file] [scene]
    local base_args = { "run", "python", "-m", "manim" }
    local manim_args = manim_util.build_manim_args(file, scene.name, params.quality, params.extra_args)
    local all_args = util.extend_args(base_args, manim_args)
    
    local quality_desc = params.quality:gsub("_", " ")
    local task_name = string.format("Manim: %s (%s)", scene.name, quality_desc)
    
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
          scene = scene.name,
          file = file
        } 
      },
    }
  end,
}