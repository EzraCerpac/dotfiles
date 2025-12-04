local util = require("overseer.template.uvpy.util")
local overseer = require("overseer")

return {
  name = "Python: REPL (uv)",
  desc = "Start a Python REPL via uv (use with vim-slime to send code)",
  tags = { overseer.TAG.RUN },
  priority = 40,
  condition = {
    filetype = { "python" },
  },
  params = {},
  builder = function()
    local cwd = util.project_root()
    return {
      name = "Python REPL",
      cmd = { "uv" },
      args = { "run", "python" },
      cwd = cwd,
      components = { "default" },
      metadata = { uvpy = { kind = "repl" } },
    }
  end,
}
