local util = require("overseer.template.uvpy.util")
local manim_util = require("overseer.template.uvpy.uv_manim_util")
local overseer = require("overseer")

return {
  name = "Manim: Pick Scene to Render",
  desc = "Interactive selection of Scene class to render with uv",
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
    
    -- Get all scenes in file
    local scenes = manim_util.find_scene_classes()
    if #scenes == 0 then
      return nil, "No Scene classes found in file. Make sure you have classes that inherit from Scene."
    end
    
    -- If only one scene, use it directly
    if #scenes == 1 then
      local scene = scenes[1]
      local file = vim.fn.expand("%:t")
      local cwd = util.project_root()
      
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
    end
    
    -- Multiple scenes - return a special task that will prompt the user
    return {
      name = "Manim: Pick Scene",
      cmd = { "echo", "Multiple scenes found - use telescope picker or vim.ui.select" },
      components = {
        {
          "on_complete",
          statuses = { "FAILURE" },
        },
        {
          "open_list",
          direction = "vertical",
          max_height = 0.3,
        },
      },
      metadata = { 
        uvpy = { 
          kind = "manim_picker",
          scenes = scenes,
          file = vim.fn.expand("%:t"),
          params = params
        } 
      },
    }
  end,
  
  -- Special run handler for the picker case
  run = function(self, task_defn, status_cb)
    local metadata = task_defn.metadata and task_defn.metadata.uvpy
    
    if metadata and metadata.kind == "manim_picker" then
      -- Use our picker utility
      manim_util.pick_scene(metadata.scenes, function(scene)
        if not scene then
          return
        end
        
        local file = metadata.file
        local params = metadata.params
        local cwd = util.project_root()
        
        local base_args = { "run", "python", "-m", "manim" }
        local manim_args = manim_util.build_manim_args(file, scene.name, params.quality, params.extra_args)
        local all_args = util.extend_args(base_args, manim_args)
        
        local quality_desc = params.quality:gsub("_", " ")
        local task_name = string.format("Manim: %s (%s)", scene.name, quality_desc)
        
        -- Create and run the actual render task
        local overseer = require("overseer")
        overseer.new_task({
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
        }):start()
        
        -- Close the picker task
        self:stop()
      end)
    end
  end,
}