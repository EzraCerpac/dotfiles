local M = {}

local function get_visual_selection()
  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))

  if ls > le or (ls == le and cs > ce) then
    ls, le = le, ls
    cs, ce = ce, cs
  end

  local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, false)
  if #lines == 0 then
    return nil
  end

  lines[#lines] = string.sub(lines[#lines], 1, ce)
  lines[1] = string.sub(lines[1], cs)

  return table.concat(lines, "\n"), ls - 1, le
end

function M.convert()
  local input, start_line, end_line = get_visual_selection()
  if not input then
    vim.notify("No visual selection", vim.log.levels.WARN)
    return
  end

  local output = vim.fn.system({
    "pandoc",
    "--from=latex",
    "--to=typst",
  }, input)

  if vim.v.shell_error ~= 0 then
    vim.notify("Pandoc conversion failed", vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_buf_set_lines(0, start_line or 0, end_line or -1, false, vim.split(output, "\n", { plain = true }))
end

return M
