local util = require("overseer.template.uvpy.util")
local overseer = require("overseer")

return {
  name = "Python: Run Module (uv -m)",
  desc = "Run a Python module with `uv run -m <module>`",
  tags = { overseer.TAG.RUN },
  priority = 50,
  params = {
    module = {
      desc = "Module name (e.g. package.cli)",
      type = "string",
      default = "",
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
    local base = { "run", "-m", params.module }
    local all_args = util.extend_args(base, extra)
    return {
      name = string.format("uv run -m %s", params.module),
      cmd = { params.interpreter },
      args = all_args,
      cwd = cwd,
      components = { "uvpy_default" },
      metadata = { uvpy = { kind = "module", base_args = base } },
    }
  end,
}
