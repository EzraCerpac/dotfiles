local overseer = require("overseer")
local util = require("overseer.template.typst.util")

return {
  name = "Typst: compile pdf",
  desc = "Compile a Typst file to PDF",
  tags = { overseer.TAG.BUILD },
  priority = 50,
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
  },
  builder = function(params)
    local file = util.default_file(params)
    if file == "" then
      return nil
    end
    local args = { "compile", file }
    if params.out and params.out ~= "" then
      table.insert(args, params.out)
    end
    local cwd = util.project_root()
    return {
      name = string.format("typst compile %s", vim.fn.fnamemodify(file, ":t")),
      cmd = { "typst" },
      args = args,
      cwd = cwd,
      components = {
        "default",
        { "on_complete_notify", statuses = { "FAILURE" } },
      },
      metadata = { typst = { file = file, kind = "compile" } },
    }
  end,
}
