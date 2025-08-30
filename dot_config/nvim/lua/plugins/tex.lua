return {
  "lervag/vimtex",
  lazy = false, -- lazy-loading will disable inverse search
  config = function()
    vim.g.vimtex_mappings_disable = { ["n"] = { "K" } } -- disable `K` as it conflicts with LSP hover
    vim.g.vimtex_quickfix_method = vim.fn.executable("pplatex") == 1 and "pplatex" or "latexlog"
    vim.api.nvim_create_autocmd({ "FileType" }, {
      group = vim.api.nvim_create_augroup("lazyvim_vimtex_conceal", { clear = true }),
      pattern = { "bib", "tex" },
      callback = function()
        vim.wo.conceallevel = 0
      end,
    })

    vim.g.vimtex_view_method = "skim"
    vim.g.vimtex_view_skim_sync = 1
    vim.g.vimtex_view_skim_activate = 1
    vim.g.vimtex_view_skim_reading_bar = 1

    vim.g.vimtex_compiler_latexmk = {
      aux_dir = "./aux",
      out_dir = "./out",
    }

    -- Fix for returning focus to Neovim after inverse search on macOS with Ghostty
    local function tex_focus_vim()
      -- Use 'open -a' to focus the Ghostty terminal application
      vim.fn.system("open -a Ghostty")
      vim.cmd("redraw!")
    end

    -- Create autocommand group for VimTeX inverse search focus fix
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("vimtex_event_focus", { clear = true }),
      pattern = "VimtexEventViewReverse",
      callback = tex_focus_vim,
      desc = "Return focus to Neovim after inverse search from PDF viewer",
    })
  end,
  keys = {
    { "<localLeader>l", "", desc = "+vimtex", ft = "tex" },
  },
}
