local typst_root_markers = { "typst.toml", ".jj", ".git" }
local harper_root_markers = { ".harper-dictionary.txt", "typst.toml", ".jj", ".git" }

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
        root_markers = typst_root_markers,
        settings = vim.tbl_deep_extend("force", tinymist.settings or {}, {
          compileStatus = "enable",
        }),
      })
      local harper = opts.servers.harper_ls or {}
      opts.servers.harper_ls = vim.tbl_deep_extend("force", harper, {
        enabled = vim.fn.executable("harper-ls") == 1,
        mason = false,
        filetypes = { "markdown", "text", "typst" },
        root_markers = harper_root_markers,
        settings = vim.tbl_deep_extend("force", harper.settings or {}, {
          ["harper-ls"] = {
            dialect = "American",
            diagnosticSeverity = "hint",
            isolateEnglish = false,
            maxFileLength = 120000,
            excludePatterns = {},
            linters = {
              SpellCheck = true,
              SpelledNumbers = true,
              AnA = true,
              SentenceCapitalization = false,
              UnclosedQuotes = true,
              WrongApostrophe = false,
              LongSentences = true,
              RepeatedWords = true,
              Spaces = true,
              CorrectNumberSuffix = true,
              SplitWords = false,
              EllipsisLength = false,
              CapitalizePersonalPronouns = false,
              PhrasalVerbAsCompoundNoun = false,
              ExpandMinimum = false,
              ToDoHyphen = false,
              OrthographicConsistency = false,
            },
            codeActions = {
              ForceStable = false,
            },
            markdown = {
              IgnoreLinkTitle = false,
            },
          },
        }),
      })
      local previous_harper_init = opts.servers.harper_ls.on_init
      opts.servers.harper_ls.on_init = function(client, result)
        if previous_harper_init then previous_harper_init(client, result) end
        local root = client.root_dir or ""
        if root:match("/ezra%-cerpac[^/]*/manuscript$") then
          local settings = client.settings or {}
          local config = settings["harper-ls"] or {}
          config.workspaceDictPath = ".harper-dictionary.txt"
          config.isolateEnglish = true
          config.excludePatterns = { "**/frontmatter.typ", "**/archive/**", "**/build/**" }
          config.linters = config.linters or {}
          for _, rule in ipairs({
            "AnA", "AvoidAndAlso", "Beforehand", "CommaFixes", "CompoundNouns",
            "DiscourseMarkers", "DisjointPrefixes", "ExpandConfiguration", "FillerWords",
            "HowTo", "InflectedVerbAfterTo", "ItsContraction", "LongSentences",
            "MassNouns", "MergeWords", "MissingDeterminer", "MissingPreposition",
            "MissingTo", "NounVerbConfusion", "Overall", "OxfordComma",
            "PersonalAddress", "PronounInflectionBe", "RepeatedWords", "RoadMap",
            "Spaces", "SpelledNumbers", "WrongNegative",
          }) do
            config.linters[rule] = false
          end
          settings["harper-ls"] = config
          client.settings = settings
          client:notify("workspace/didChangeConfiguration", { settings = settings })
        end
      end
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
        if env_root and env_root ~= "" then
          return env_root
        end

        local absolute_path = vim.fn.fnamemodify(path_of_main_file, ":p")
        return vim.fs.root(absolute_path, typst_root_markers) or vim.fs.dirname(absolute_path)
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
