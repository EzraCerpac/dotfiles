local util = {}

local function buffer_file(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  return vim.fs.normalize(name)
end

local function project_root_for_file(file)
  local start_dir = vim.fs.dirname(file)
  local git = vim.fs.find(".git", { path = start_dir, upward = true, type = "directory" })[1]
  if git then
    return vim.fs.dirname(git)
  end

  return start_dir
end

function util.project_root(bufnr)
  local file = buffer_file(bufnr or 0)
  if not file then
    return vim.loop.cwd()
  end

  return project_root_for_file(file)
end

function util.typst_root(file)
  return project_root_for_file(vim.fs.normalize(file))
end

function util.default_file(params)
  if params and params.file and params.file ~= "" then
    return params.file
  end
  local file = buffer_file(0)
  return file or ""
end

return util
