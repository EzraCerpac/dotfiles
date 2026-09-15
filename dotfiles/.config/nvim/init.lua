local function delftblue_enabled()
  local host = ""
  if vim.uv and vim.uv.os_gethostname then
    host = (vim.uv.os_gethostname() or ""):lower()
  end

  return host:match("delftblue") ~= nil
    or vim.env.DB_MODULE_STACK ~= nil
    or vim.env.DB_SLURM_ACCOUNT ~= nil
    or vim.env.DB_SPACK_ROOT ~= nil
end

if delftblue_enabled() then
  package.preload["sidekick.status"] = function()
    return {
      get = function()
        return nil
      end,
      cli = function()
        return {}
      end,
    }
  end

  local orig_notify = vim.notify
  vim.notify = function(msg, level, opts)
    if msg == "defaults.lua: Did not detect DSR response from terminal. This results in a slower startup time." then
      return
    end
    return orig_notify(msg, level, opts)
  end
end

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Settings from old .vimrc
-- vim.opt.incsearch = true  -- Enable incremental search
