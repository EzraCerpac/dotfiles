local util = require("overseer.template.uvpy.util")
local overseer = require("overseer")

return {
  name = "Python: Run Current File (uv)",
  desc = "Run the current Python buffer with `uv run`",
  tags = { overseer.TAG.RUN },
  priority = 50,
  condition = {
    filetype = { "python" },
  },
  params = {
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
    local file = vim.api.nvim_buf_get_name(0)
    local cwd = util.project_root()
    local extra = util.split_args(params.args)
    local base = { "run", file }
    local all_args = util.extend_args(base, extra)
    return {
      name = string.format("uv run %s", vim.fn.fnamemodify(file, ":t")),
      cmd = { params.interpreter },
      args = all_args,
      cwd = cwd,
      components = { "uvpy_default" },
      metadata = { uvpy = { kind = "file", base_args = base } },
    }
  end,
}
