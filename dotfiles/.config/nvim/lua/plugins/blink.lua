return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      local references = require("custom.typst_references")
      opts.keymap = vim.tbl_deep_extend("force", opts.keymap or {}, {
        preset = "enter",
        -- Tab is not used for completions; accept with <C-y>.
        ["<Tab>"] = false,
        ["<S-Tab>"] = false,
      })
      opts.sources = opts.sources or {}
      opts.sources.per_filetype = opts.sources.per_filetype or {}
      opts.sources.per_filetype.codecompanion = { "codecompanion", "buffer" }
      local default = opts.sources.default or { "lsp", "path", "snippets", "buffer" }
      opts.sources.default = function(ctx)
        local sources = vim.deepcopy(type(default) == "function" and default(ctx) or default)
        if not vim.tbl_contains(sources, "typst_references") then
          sources[#sources + 1] = "typst_references"
        end
        return sources
      end
      opts.sources.providers = opts.sources.providers or {}
      local providers = opts.sources.providers
      providers.typst_references = { name = "References", module = "custom.typst_references" }
      providers.lsp = providers.lsp or {}
      local previous_transform = providers.lsp.transform_items
      providers.lsp.transform_items = function(ctx, items)
        if previous_transform then
          items = previous_transform(ctx, items)
        end
        references.record(ctx, items)
        return items
      end
      local previous_fallbacks = providers.lsp.fallbacks or { "buffer" }
      providers.lsp.fallbacks = function(ctx, source_ids)
        local fallbacks = vim.deepcopy(
          type(previous_fallbacks) == "function" and previous_fallbacks(ctx, source_ids) or previous_fallbacks
        )
        if references.is_reference(ctx) then
          table.insert(fallbacks, 1, "typst_references")
        end
        return fallbacks
      end
      local previous_timeout = providers.lsp.timeout_ms or 2000
      providers.lsp.timeout_ms = function(ctx)
        if references.is_reference(ctx) then
          return 150
        end
        return type(previous_timeout) == "function" and previous_timeout(ctx) or previous_timeout
      end
      providers.buffer = providers.buffer or {}
      local previous_show = providers.buffer.should_show_items
      providers.buffer.should_show_items = function(ctx, items)
        if references.is_reference(ctx) then
          return false
        end
        if type(previous_show) == "function" then
          return previous_show(ctx, items)
        end
        return previous_show ~= false
      end
      return opts
    end,
  },
}
