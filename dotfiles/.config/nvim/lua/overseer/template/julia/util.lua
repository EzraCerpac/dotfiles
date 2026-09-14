local M = {}

-- Find a project root using common Julia markers
function M.project_root()
  local buf_dir = vim.fn.expand("%:p:h")
  -- Prefer Julia project files; then .git directory
  local found = vim.fs.find({ "Project.toml" }, {
    upward = true,
    type = "file",
    path = buf_dir,
  })[1]
  if found then
    return vim.fs.dirname(found)
  end
  local gitdir = vim.fs.find({ ".git" }, { upward = true, type = "directory", path = buf_dir })[1]
  if gitdir then
    return vim.fs.dirname(gitdir)
  end
  return buf_dir
end

return M
