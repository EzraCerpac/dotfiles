-- RTF syntax highlighting via pygmentize
-- Usage: :RTFHighlight (entire buffer) or visual selection
vim.api.nvim_create_user_command("RTFHighlight", function(args)
  if vim.fn.executable("pygmentize") == 0 then
    vim.notify("pygmentize not found", vim.log.levels.ERROR)
    return
  end

  local line1, line2 = args.line1, args.line2
  local content = table.concat(vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false), "\n")
  local lexer = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
  local theme = vim.g.rtf_theme or "xcode"

  local output = vim.fn.system("pygmentize -f rtf -O style=" .. theme .. " -l " .. lexer, content)
  if vim.v.shell_error == 0 then
    vim.fn.system("pbcopy", output)
    vim.notify("RTF copied to clipboard", vim.log.levels.INFO)
  else
    vim.notify("pygmentize failed: " .. output, vim.log.levels.ERROR)
  end
end, { range = true, desc = "Convert buffer/selection to RTF and copy to clipboard" })
