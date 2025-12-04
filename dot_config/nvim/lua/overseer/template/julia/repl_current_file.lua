local util = require("overseer.template.julia.util")
local overseer = require("overseer")

return {
  name = "Julia: REPL Current File",
  desc = "Start a Julia REPL with the current file loaded (julia -i)",
  tags = { overseer.TAG.RUN },
  priority = 50,
  condition = {
    filetype = { "julia" },
  },
  params = {
    args = {
      desc = "Extra CLI arguments to pass to Julia",
      type = "string",
      optional = true,
      default = "",
    },
    interpreter = {
      desc = "Julia executable",
      type = "string",
      optional = true,
      default = "julia",
    },
  },
  builder = function(params)
    local file = vim.api.nvim_buf_get_name(0)
    local cwd = util.project_root()
    local extra = {}
    if params.args and params.args ~= "" then
      for word in string.gmatch(params.args, "%S+") do
        table.insert(extra, word)
      end
    end
    local base = { "--banner=no", "--project=.", "-i", file }
    local all_args = {}
    for _, v in ipairs(base) do
      table.insert(all_args, v)
    end
    for _, v in ipairs(extra) do
      table.insert(all_args, v)
    end
    return {
      name = string.format("Julia REPL: %s", vim.fn.fnamemodify(file, ":t")),
      cmd = { params.interpreter },
      args = all_args,
      cwd = cwd,
      components = { "default" },
      metadata = { julia = { kind = "repl", file = file, base_args = base } },
    }
  end,
}
