local M = {}

-- Chapters should use the nearest conventional entrypoint inside their project.
function M.resolve(path, root)
  if type(root) ~= "string" or root == "" or path == "" then
    return
  end
  path, root = vim.fs.normalize(path), vim.fs.normalize(root)
  if path:sub(1, #root + 1) ~= root .. "/" then
    return
  end
  local directory = vim.fs.dirname(path)
  while directory do
    local main = vim.fs.joinpath(directory, "main.typ")
    local stat = vim.uv.fs_stat(main)
    if stat and stat.type == "file" then
      return main
    end
    if directory == root then
      return
    end
    directory = vim.fs.dirname(directory)
  end
end

function M.attach(client, bufnr)
  if client._typst_main_selected then
    return
  end
  client._typst_main_selected = true
  -- Explicit project arguments own the entrypoint when supplied.
  if client.settings and client.settings.typstExtraArgs and #client.settings.typstExtraArgs > 0 then
    return
  end
  local main = M.resolve(vim.api.nvim_buf_get_name(bufnr), client.root_dir)
  if not main then
    return
  end
  -- compileStatus owns cache identity and warming, so a late command reply
  -- cannot overwrite a main the user pinned afterwards.
  client:exec_cmd({ title = "Pin project main", command = "tinymist.pinMain", arguments = { main } }, { bufnr = bufnr })
end

return M
