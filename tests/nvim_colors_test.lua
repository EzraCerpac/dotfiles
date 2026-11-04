local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local plugins = (os.getenv("NVIM_TEST_PLUGIN_ROOT") or vim.fn.stdpath("data") .. "/lazy") .. "/"
vim.opt.rtp:prepend(plugins .. "catppuccin")

-- Load the actual options, without enabling unrelated language servers.
local enable = vim.lsp.enable
vim.lsp.enable = function() end
dofile(root .. "/dotfiles/.config/nvim/lua/config/options.lua")
vim.lsp.enable = enable

for _, event in ipairs({ "ColorScheme", "TermResponse", "UIEnter" }) do
  for _, group in ipairs({ "Normal", "NormalNC" }) do
    vim.api.nvim_set_hl(0, group, { fg = "#cdd6f4", bg = "#1e1e2e", bold = true })
  end
  vim.api.nvim_exec_autocmds(event, {})
  vim.wait(20, function()
    return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == nil
  end)
  for _, group in ipairs({ "Normal", "NormalNC" }) do
    local hl = vim.api.nvim_get_hl(0, { name = group })
    assert(hl.bg == nil, event .. " left an opaque background")
    assert(hl.fg == 0xcdd6f4 and hl.bold, event .. " erased foreground or style")
  end
end

local specs = dofile(root .. "/dotfiles/.config/nvim/lua/plugins/colorscheme.lua")
local theme, opts
for _, spec in ipairs(specs) do
  if spec[1] == "LazyVim/LazyVim" then
    theme = spec.opts.colorscheme
  end
  if spec[1] == "catppuccin/nvim" then
    opts = vim.deepcopy(spec.opts)
  end
end
assert(theme == "catppuccin-nvim", "Use the unambiguous plugin theme entry point")
local cache = vim.fn.tempname()
opts.compile_path = cache
require("catppuccin").setup(opts)
vim.o.background = "dark"
vim.cmd.colorscheme(theme)
vim.wait(20, function()
  return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == nil
end)
assert(vim.g.colors_name == "catppuccin-mocha", "Did not load the plugin's dark palette")
assert(vim.api.nvim_get_hl(0, { name = "Normal" }).fg == 0xcdd6f4, "Lost the plugin foreground")
assert(vim.api.nvim_get_hl(0, { name = "LineNr" }).fg == 0xa6adc8, "Lost custom plugin highlights")
vim.o.background = "light"
assert(vim.g.colors_name == "catppuccin-latte", "Background detection did not reload the plugin")
vim.o.background = "dark"
assert(vim.g.colors_name == "catppuccin-mocha", "Background detection loaded another theme")
vim.wait(20, function()
  return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == nil
end)
assert(vim.api.nvim_get_hl(0, { name = "Normal" }).fg == 0xcdd6f4)
vim.fn.delete(cache, "rf")
print("Catppuccin plugin selection and transparent foreground tests passed")
