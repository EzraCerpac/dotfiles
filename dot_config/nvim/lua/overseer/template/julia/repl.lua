local util = require("overseer.template.julia.util")
local overseer = require("overseer")

return {
  name = "Julia: REPL",
  desc = "Start a Julia REPL (use with vim-slime to send code)",
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
