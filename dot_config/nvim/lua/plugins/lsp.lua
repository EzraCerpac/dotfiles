return {
  {
    "folke/lazydev.nvim",
    ft = "lua",
    dependencies = {
      { "DrKJeff16/wezterm-types", lazy = true },
    },
    opts = {
      library = {
        -- Other library configs...
        { path = "wezterm-types", mods = { "wezterm" } },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts = opts or {}
      opts.servers = opts.servers or {}
      opts.servers.pyright = { enabled = false } -- using ty instead
      local tinymist = opts.servers.tinymist or {}
      opts.servers.tinymist = vim.tbl_deep_extend("force", tinymist, {
        settings = vim.tbl_deep_extend("force", tinymist.settings or {}, {
          compileStatus = "enable",
        }),
      })
      opts.setup = opts.setup or {}
      opts.setup.julials = function(_, sopts)
        -- critical: do NOT let Mason manage Julia LS
        -- mason = false alone is not enough: Mason's automatic_enable still
        -- overrides the config. Returning truthy here adds the server to
        -- mason_exclude and skips vim.lsp.config — we call it ourselves below
        -- to preserve the default on_attach (which registers :LspJuliaActivateEnv).
        sopts.mason = false
        sopts.cmd = {
          "julia",
          "--startup-file=no",
          "--history-file=no",
          vim.fn.stdpath("config") .. "/lua/helpers/julials.jl",
        }
        sopts.settings = vim.tbl_deep_extend("force", sopts.settings or {}, {
          julia = {
            completionmode = "qualify",
            -- lint = { missingrefs = "none" },
          },
        })
        sopts.single_file_support = true
        vim.lsp.config("julials", sopts)
        vim.lsp.enable("julials")
        return true
      end
      return opts
    end,
  },
  {
    "chomosuke/typst-preview.nvim",
    opts = function(_, opts)
      opts = opts or {}
      opts.get_root = function(path_of_main_file)
        local env_root = os.getenv("TYPST_ROOT")
        if env_root then
          return env_root
        end

        local main_dir = vim.fs.dirname(vim.fn.fnamemodify(path_of_main_file, ":p"))
        local git = vim.fs.find(".git", { path = main_dir, upward = true, type = "directory" })[1]
        if git then
          return vim.fs.dirname(git)
        end

        local typst_toml = vim.fs.find("typst.toml", { path = main_dir, upward = true, type = "file" })[1]
        return typst_toml and vim.fs.dirname(typst_toml) or main_dir
      end
      return opts
    end,
  },
  -- Julia DAP configuration via nvim-dap-julia
  {
    -- https://github.com/kdheepak/nvim-dap-julia/
    "mfussenegger/nvim-dap",
    dependencies = {
      {
        "kdheepak/nvim-dap-julia",
        config = function()
          require("nvim-dap-julia").setup()
        end,
      },
    },
  },
  {
    "jmbuhr/otter.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      vim.api.nvim_create_autocmd({ "FileType" }, {
        pattern = { "toml" },
        group = vim.api.nvim_create_augroup("EmbedToml", {}),
        callback = function()
          require("otter").activate()
        end,
      })
    end,
  },
}
