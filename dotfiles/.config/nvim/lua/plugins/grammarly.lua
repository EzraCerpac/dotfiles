return {
  {
    "vim-denops/denops.vim",
    lazy = true,
  },
  {
    "gamoutatsumi/dps-ghosttext.vim",
    dependencies = { "vim-denops/denops.vim" },
    cmd = { "GhostStart" },
    init = function()
      vim.g["dps_ghosttext#enable_autostart"] = 0
      vim.g["dps_ghosttext#disable_defaultmap"] = 1
      vim.g["dps_ghosttext#ftmap"] = {
        ["grammarly-bridge.localhost"] = "typst",
      }
    end,
    config = function()
      local function discover()
        vim.fn["denops#plugin#discover"]()
      end
      if vim.fn["denops#server#status"]() == "running" then
        discover()
      end
    end,
  },
}
