-- Compatibility shim for trouble.nvim treesitter decoration provider
-- Some Neovim versions expose `vim.treesitter.highlighter.on_line/on_win`
-- while others use `_on_line/_on_win`. Trouble calls the underscored ones.
-- Alias whichever are missing to avoid nil calls in the decoration provider.
return {
  "folke/trouble.nvim",
  cmd = { "TroubleToggle", "Trouble" },
  init = function()
    local ok, hl = pcall(function()
      return vim.treesitter and vim.treesitter.highlighter
    end)
    if not ok or not hl then
      return
    end
    -- Ensure the active table exists (used by trouble to swap highlighters)
    hl.active = hl.active or {}
    -- Provide fallbacks between underscored and non-underscored methods
    if hl.on_line and not hl._on_line then
      hl._on_line = hl.on_line
    end
    if hl.on_win and not hl._on_win then
      hl._on_win = hl.on_win
    end
    if hl._on_line and not hl.on_line then
      hl.on_line = hl._on_line
    end
    if hl._on_win and not hl.on_win then
      hl.on_win = hl._on_win
    end
  end,
  config = function()
    -- As a safety net, avoid registering the decoration provider
    -- if neither variant of the highlighter callbacks is available.
    pcall(function()
      local tsmod = require("trouble.view.treesitter")
      local orig_setup = tsmod.setup
      tsmod.setup = function(...)
        local ok, hl = pcall(function()
          return vim.treesitter and vim.treesitter.highlighter
        end)
        if not ok or not hl then
          return
        end
        local has_line = hl._on_line or hl.on_line
        local has_win = hl._on_win or hl.on_win
        if not (has_line and has_win) then
          -- Skip provider registration entirely if the callbacks are missing
          return
        end
        return orig_setup(...)
      end
    end)
  end,
}
