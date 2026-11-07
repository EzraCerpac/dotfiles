local typst_root_markers = { "typst.toml", ".jj", ".git" }
local harper_root_markers = { ".harper-dictionary.txt", "typst.toml", ".jj", ".git" }

local function filter_harper_typst(params, client)
  local bufnr = vim.fn.bufnr(vim.uri_to_fname(params.uri))
  if bufnr < 0 or not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].filetype ~= "typst" then
    return params
  end
  if params.version and params.version ~= vim.lsp.util.buf_versions[bufnr] then return params end

  local parser = vim.treesitter.get_parser(bufnr, "typst")
  local tree = parser:parse()[1]
  if not tree then return params end
  local root = tree:root()
  local diagnostics = {}
  for _, diagnostic in ipairs(params.diagnostics) do
    local range = diagnostic.range
    local start = range and range.start
    local finish = range and range["end"]
    local suppress = false
    if start and finish and start.line == finish.line and finish.character > start.character then
      local line = vim.api.nvim_buf_get_lines(bufnr, start.line, start.line + 1, true)[1]
      if line then
        local first = vim.str_byteindex(line, client.offset_encoding, start.character)
        local last = vim.str_byteindex(line, client.offset_encoding, finish.character)
        -- A position in the middle of a UTF-16 surrogate pair is not reliable.
        if vim.str_utfindex(line, client.offset_encoding, first) == start.character
          and vim.str_utfindex(line, client.offset_encoding, last) == finish.character
          and last > first
        then
          local node = root:named_descendant_for_range(start.line, first, finish.line, last - 1)
          while node and node:type() ~= "ident" and node:type() ~= "string" do
            if node:type() == "content" or node:type() == "ERROR" then break end
            node = node:parent()
          end
          if node and (node:type() == "ident" or node:type() == "string") and not node:has_error() then
            local candidate = node:type() == "ident"
            if node:type() == "string" then
              local value = vim.treesitter.get_node_text(node, bufnr):match('^"([%w_%-]+)"$')
              candidate = value ~= nil and (value:find("[%d_]") ~= nil or value:find("%l%u") ~= nil)
            end
            local parent = node:parent()
            while candidate and parent do
              if parent:type() == "content" or parent:type() == "ERROR" then break end
              if parent:type() == "code" then
                suppress = not parent:has_error()
                break
              end
              parent = parent:parent()
            end
          end
        end
      end
    end
    if not suppress then diagnostics[#diagnostics + 1] = diagnostic end
  end
  return vim.tbl_extend("force", params, { diagnostics = diagnostics })
end

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
      opts.servers.mise = {
        cmd = { "mise", "lsp" },
        mason = false,
        filetypes = { "toml" },
        root_markers = { "mise.toml", ".mise.toml", ".jj", ".git" },
        -- Taplo handles general TOML features; mise adds diagnostics and task navigation.
        init_options = {
          formatting = false,
          hover = false,
          completion = false,
        },
      }
      -- Typst inlay hints repeatedly analyse package imports on edits and scrolling.
      opts.inlay_hints = opts.inlay_hints or {}
      opts.inlay_hints.exclude = opts.inlay_hints.exclude or {}
      if not vim.tbl_contains(opts.inlay_hints.exclude, "typst") then
        table.insert(opts.inlay_hints.exclude, "typst")
      end
      local tinymist = opts.servers.tinymist or {}
      local patched_tinymist = vim.fn.expand("~/.local/share/tinymist-patched/bin/tinymist")
      if vim.fn.executable(patched_tinymist) == 1 then
        tinymist.cmd = { patched_tinymist }
        tinymist.mason = false
      end
      opts.servers.tinymist = vim.tbl_deep_extend("force", tinymist, {
        keys = {
          {
            "gd",
            function()
              require("custom.typst_definition").goto_definition()
            end,
            desc = "Goto Definition",
            has = "definition",
          },
        },
        root_markers = typst_root_markers,
        settings = vim.tbl_deep_extend("force", tinymist.settings or {}, {
          compileStatus = "enable",
          -- Tree-sitter provides highlighting without Tinymist's import analysis.
          semanticTokens = "disable",
          -- Tinymist otherwise rejects ':' triggers, including @ch: references.
          completion = { triggerOnSnippetPlaceholders = true },
        }),
      })
      local previous_tinymist_attach = opts.servers.tinymist.on_attach
      opts.servers.tinymist.on_attach = function(client, bufnr)
        if previous_tinymist_attach then
          previous_tinymist_attach(client, bufnr)
        end
        require("custom.typst_main").attach(client, bufnr)
      end
      local previous_tinymist_init = opts.servers.tinymist.on_init
      opts.servers.tinymist.on_init = function(client, result)
        if previous_tinymist_init then
          previous_tinymist_init(client, result)
        end
        -- Tinymist still advertises this capability when semanticTokens is disabled.
        client.server_capabilities.semanticTokensProvider = nil
        -- These background queries can swamp Tinymist's thesis import analysis.
        client.server_capabilities.colorProvider = nil
        client.server_capabilities.foldingRangeProvider = nil
        client.server_capabilities.documentHighlightProvider = nil
        local references = require("custom.typst_references")
        references.attach(client)
        local previous_status = client.handlers["tinymist/compileStatus"] or vim.lsp.handlers["tinymist/compileStatus"]
        client.handlers["tinymist/compileStatus"] = function(err, result, ctx, config)
          if
            not err
            and result
            and result.path
            and require("custom.typst_main").accept_compile_status(client, result.path)
          then
            references.set_main(client.id, client.root_dir, result.path)
            if result.status == "compileSuccess" then
              references.warm(client)
            end
          end
          if previous_status then
            return previous_status(err, result, ctx, config)
          end
        end
      end
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
      local handlers = opts.servers.harper_ls.handlers or {}
      local previous_harper_diagnostics = handlers["textDocument/publishDiagnostics"]
        or vim.lsp.handlers["textDocument/publishDiagnostics"]
      handlers["textDocument/publishDiagnostics"] = function(err, params, ctx, config)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        if not err and params and params.uri and params.diagnostics and client and client.name == "harper_ls" then
          local ok, filtered = pcall(filter_harper_typst, params, client)
          if ok then params = filtered end
        end
        return previous_harper_diagnostics(err, params, ctx, config)
      end
      opts.servers.harper_ls.handlers = handlers
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
      require("custom.typst_main").setup_preview(opts)
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
