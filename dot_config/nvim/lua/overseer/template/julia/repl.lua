local util = require("overseer.template.julia.util")
local overseer = require("overseer")

return {
  name = "Julia: REPL",
  desc = "Start a Julia REPL via overseer (for task management; use <leader>r for interactive REPL)",
  tags = { overseer.TAG.RUN },
  priority = 40,
  condition = {
    filetype = { "julia" },
  },
  params = {
    interpreter = {
      desc = "Julia executable",
      type = "string",
      optional = true,
      default = "julia",
    },
  },
  builder = function(params)
    local cwd = util.project_root()
    return {
      name = "Julia REPL",
      cmd = { params.interpreter },
      args = { "--banner=no", "--project=." },
      cwd = cwd,
      components = { "default" },
      metadata = { julia = { kind = "repl" } },
    }
  end,
}
