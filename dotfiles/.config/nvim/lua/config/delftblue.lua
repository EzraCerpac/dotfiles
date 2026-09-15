local M = {}

function M.enabled()
  if vim.g.delftblue_profile ~= nil then
    return vim.g.delftblue_profile
  end

  local host = ""
  if vim.uv and vim.uv.os_gethostname then
    host = (vim.uv.os_gethostname() or ""):lower()
  end

  return host:match("delftblue") ~= nil
    or vim.env.DB_MODULE_STACK ~= nil
    or vim.env.DB_SLURM_ACCOUNT ~= nil
    or vim.env.DB_SPACK_ROOT ~= nil
end

function M.has(bin)
  return vim.fn.executable(bin) == 1
end

return M
