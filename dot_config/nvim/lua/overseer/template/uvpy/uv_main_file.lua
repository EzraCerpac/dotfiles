local util = require("overseer.template.uvpy.util")
local overseer = require("overseer")

return {
  name = "Python: Run Main File (uv)",
  desc = "Select a Python file to run with `uv run`",
  tags = { overseer.TAG.RUN },
  priority = 50,
  params = {
    main = {
      desc = "Path to main Python file",
      type = "string",
      default = function()
        -- Prefer common entry points if present
        local candidates = { "main.py", "cli.py", "app.py" }
        local cwd = util.project_root()
        for _, f in ipairs(candidates) do
          local p = cwd .. "/" .. f
          if vim.uv.fs_stat(p) then
            return p
          end
        end
        return vim.fn.expand("%:p")
      end,
    },
    args = {
      desc = "CLI arguments",
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
    local cwd = util.project_root()
    local extra = util.split_args(params.args)
    local main = params.main
    local base = { "run", main }
    local all_args = util.extend_args(base, extra)
    return {
      name = string.format("uv run %s", vim.fn.fnamemodify(main, ":t")),
      cmd = { params.interpreter },
      args = all_args,
      cwd = cwd,
      components = { "uvpy_default" },
      metadata = { uvpy = { kind = "file", base_args = base } },
    }
  end,
}
