local overseer = require("overseer")
local util = require("overseer.template.typst.util")

local function has_toggleterm_strategy()
  return pcall(require, "overseer.strategy.toggleterm")
end

return {
  name = "Typst: watch",
  desc = "Watch a Typst file and recompile on change",
  tags = { overseer.TAG.RUN },
  priority = 40,
  condition = {
    filetype = { "typst" },
  },
  params = {
    file = {
      desc = "Typst source file",
      type = "string",
      optional = true,
    },
    out = {
      desc = "Output PDF path",
      type = "string",
      optional = true,
    },
    strategy = {
      desc = "Execution strategy (e.g., toggleterm)",
      type = "string",
      optional = true,
    },
  },
  builder = function(params)
    local file = util.default_file(params)
    if file == "" then
      return nil
    end
    local args = { "watch", file }
    if params.out and params.out ~= "" then
      table.insert(args, params.out)
    end
    local defn = {
      name = "typst watch",
      cmd = { "typst" },
      args = args,
      cwd = util.project_root(),
      components = {
        "default",
        { "on_output_quickfix", open = false },
      },
      metadata = { typst = { file = file, kind = "watch" } },
    }
    if params.strategy and params.strategy ~= "" then
      if params.strategy == "toggleterm" and not has_toggleterm_strategy() then
        vim.notify("Overseer toggleterm strategy not available; using default", vim.log.levels.WARN)
      else
        defn.strategy = params.strategy
      end
    end
    return defn
  end,
}
