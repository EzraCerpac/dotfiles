local util = require("overseer.template.uvpy.util")
local manim_util = require("overseer.template.uvpy.uv_manim_util")
local overseer = require("overseer")

return {
  name = "Manim: Export High Quality",
  desc = "Export Manim Scene with high quality settings",
  tags = { overseer.TAG.RUN },
  priority = 50,
  condition = {
    filetype = { "python" },
  },
  params = {
    quality = {
      desc = "Quality preset for export (default: high)",
      type = "string",
      optional = true,
      default = "high",
      choices = { "high", "fourk" }
    },
    output_dir = {
      desc = "Custom output directory",
      type = "string",
      optional = true,
    },
    transparent = {
      desc = "Export with transparent background",
      type = "boolean",
      optional = true,
      default = false,
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
    
    -- Start with quality flag
    local manim_args = { manim_util.get_quality_flag(params.quality) }
    
    -- Add output directory if specified
    if params.output_dir and params.output_dir ~= "" then
      table.insert(manim_args, "--media_dir=" .. params.output_dir)
    end
    
    -- Add transparent background if requested
    if params.transparent then
      table.insert(manim_args, "--transparent")
    end
    if params.open_after_render then
      table.insert(manim_args, "--preview")
    end
    
    -- Add file and scene name
    table.insert(manim_args, file)
    table.insert(manim_args, scene.name)
    
    -- Add extra args if provided
    if params.extra_args and params.extra_args ~= "" then
      local extra = util.split_args(params.extra_args)
      for _, arg in ipairs(extra) do
        table.insert(manim_args, arg)
      end
    end
    
    local all_args = util.extend_args(base_args, manim_args)
    
    local quality_desc = (params.quality or "high"):gsub("_", " ")
    local export_desc = string.format("Manim Export: %s (%s)", scene.name, quality_desc)
    if params.output_dir then
      export_desc = export_desc .. " -> " .. params.output_dir
    end
    
    return {
      name = export_desc,
      cmd = { runner },
      args = all_args,
      cwd = cwd,
      components = { "uvpy_default" },
      metadata = { 
        uvpy = { 
          kind = "manim_export",
          base_args = base_args,
          scene = scene.name,
          file = file,
          quality = params.quality
        } 
      },
    }
  end,
}
