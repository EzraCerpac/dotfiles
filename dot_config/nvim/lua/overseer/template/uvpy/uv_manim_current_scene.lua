local util = require("overseer.template.uvpy.util")
local manim_util = require("overseer.template.uvpy.uv_manim_util")
local overseer = require("overseer")

return {
  name = "Manim: Render Scene Under Cursor",
  desc = "Render the Manim Scene class under cursor",
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
      desc = "Runner (auto/uv/manim/mise or executable on PATH)",
      type = "string",
      optional = true,
      default = "auto",
      choices = { "auto", "uv", "manim", "mise" },
    },
    open_after_render = {
      desc = "Open rendered media after completion",
      type = "boolean",
      optional = true,
      default = true,
    },
  },
  builder = function(params)
    -- Validate that this is a Manim file
    if not manim_util.validate_manim_file() then
      return manim_util.failure_task("No Manim import found. Please add 'import manim' or 'from manim import ...' to your file.")
    end
    
    -- Get scene under cursor
    local scene = manim_util.get_scene_under_cursor()
    if not scene then
      return manim_util.failure_task("No Scene class found under cursor. Move cursor inside a Scene class definition.")
    end
    
    local file = vim.api.nvim_buf_get_name(0)
    if file == "" then
      file = vim.fn.expand("%:p")
    end
    local cwd = util.project_root()
    local runner, base_args, runner_err = manim_util.resolve_manim_runner(params.interpreter)
    if not runner then
      return manim_util.failure_task(runner_err)
    end
    
    local manim_args = manim_util.build_manim_args(file, scene.name, params.quality, params.extra_args)
    if params.open_after_render then
      table.insert(manim_args, 2, "--preview")
    end
    local all_args = util.extend_args(base_args, manim_args)
    
    local quality_desc = (params.quality or manim_util.default_quality):gsub("_", " ")
    local task_name = string.format("Manim: %s (%s)", scene.name, quality_desc)
    
    return {
      name = task_name,
      cmd = { runner },
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
