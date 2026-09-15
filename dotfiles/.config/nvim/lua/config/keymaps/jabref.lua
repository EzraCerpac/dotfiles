local M = {}

function M.open_jabref()
  local bibfile = vim.fn.expand("~/References/library.bib")

  vim.fn.jobstart({ "open", "-a", "JabRef", bibfile }, {
    detach = true,
  })
end

vim.keymap.set("n", "<localLeader>jr", M.open_jabref, { desc = "Open JabRef library" })

return M
