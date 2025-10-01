-- Configure blink.cmp as the completion engine (instead of nvim-cmp).
return {
  "saghen/blink.cmp",
  version = not vim.g.lazyvim_blink_main and "*",
  build = vim.g.lazyvim_blink_main and "cargo build --release",
  opts_extend = {
    "sources.completion.enabled_providers",
    "sources.compat",
    "sources.default",
  },
  dependencies = {
    "rafamadriz/friendly-snippets",
    "Kaiser-Yang/blink-cmp-git",
    "fang2hou/blink-copilot",
    {
      "saghen/blink.compat",
      optional = true,
      opts = {},
      version = not vim.g.lazyvim_blink_main and "*",
    },
  },
  event = "InsertEnter",
  opts = {
    enabled = function()
      return not vim.tbl_contains({ "markdown" }, vim.bo.filetype)
        and vim.bo.buftype ~= "prompt"
        and vim.b.completion ~= false
    end,
    snippets = nil,
    appearance = {
      use_nvim_cmp_as_default = false,
      nerd_font_variant = "mono",
    },
    completion = {
      accept = {
        auto_brackets = {
          enabled = true,
        },
      },
      menu = {
        draw = {
          treesitter = { "lsp" },
        },
      },
      documentation = {
        auto_show = true,
        auto_show_delay_ms = 200,
      },
      ghost_text = {
        enabled = false,
      },
    },
    sources = {
      compat = {},
      default = {
        "git",
        "lsp",
        "path",
        "snippets",
        "buffer",
      },
      providers = {
        git = {
          module = "blink-cmp-git",
          name = "Git",
        },
        copilot = {
          module = "blink-copilot",
        },
      },
    },
    cmdline = { enabled = false },
    keymap = {
      preset = "super-tab",
      ["<C-y>"] = { "select_and_accept" },
      ["<Tab>"] = {
        function(cmp)
          local buf = vim.api.nvim_get_current_buf()
          local buf_state = vim.b[buf]
          if buf_state and buf_state.nes_state then
            local ok, nes = pcall(require, "copilot-lsp.nes")
            if ok then
              cmp.hide()
              if nes.apply_pending_nes() then
                nes.walk_cursor_end_edit()
                return
              end
            end
          end
          if cmp.snippet_active() then
            return cmp.accept()
          end
          return cmp.select_and_accept()
        end,
        "snippet_forward",
        "fallback",
      },
    },
  },
  config = function(_, opts)
    local enabled = opts.sources.default
    for _, source in ipairs(opts.sources.compat or {}) do
      opts.sources.providers[source] = vim.tbl_deep_extend(
        "force",
        { name = source, module = "blink.compat.source" },
        opts.sources.providers[source] or {}
      )
      if type(enabled) == "table" and not vim.tbl_contains(enabled, source) then
        table.insert(enabled, source)
      end
    end

    require("blink.cmp").setup(opts)
  end,
}
