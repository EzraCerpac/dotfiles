-- Exit 77 (tests/run's skip code) unless Neovim can load a tree-sitter parser.
-- Older Neovim raises for a missing parser; newer releases return nil.
return function(language)
  local ok, added = pcall(vim.treesitter.language.add, language)
  if not (ok and added) then
    io.stdout:write("skip: requires the ", language, " tree-sitter parser\n")
    os.exit(77)
  end
end
