---@type LazySpec
return {
  "mrjones2014/smart-splits.nvim",
  -- https://github.com/mrjones2014/smart-splits.nvim?tab=readme-ov-file
  event = "VeryLazy",
  opts = function()
    return {
      multiplexer_integration = false,
      at_edge = "stop",
      default_amount = 5, -- default is 3
      float_win_behavior = "mux",
    }
  end,
  config = function(_, opts)
    local smart_splits = require("smart-splits")
    local aerospace_focus_script = vim.fn.expand("~/.config/aerospace/bin/aerospace-focus")

    local function resolve_focus_command(direction)
      if vim.fn.executable(aerospace_focus_script) == 1 then
        return { aerospace_focus_script, "--from-nvim", direction }, "navigation"
      end
    end

    opts.at_edge = function(ctx)
      local command, backend = resolve_focus_command(ctx.direction)
      if not command then
        return
      end

      local result = vim.system(command, { text = true }):wait()
      if result.code == 0 then
        return
      end
      local err = vim.trim(result.stderr or "")
      vim.notify_once(
        string.format(
          "smart-splits: %s focus handoff failed for %s (%s)",
          backend,
          tostring(ctx.direction),
          err ~= "" and err or string.format("command exited with code %d", result.code)
        ),
        vim.log.levels.WARN
      )
    end

    smart_splits.setup(opts)
    local function apply_mappings()
      for _, lhs in ipairs({ "<A-j>", "<A-k>" }) do
        for _, mode in ipairs({ "n", "i", "v", "x" }) do
          if vim.fn.maparg(lhs, mode) ~= "" then
            pcall(vim.keymap.del, mode, lhs)
          end
        end
      end

      local all_modes = { "n", "i", "v", "x", "s", "o", "t" }
      -- these keymaps will also accept a range,
      -- for example `10<A-h>` will `resize_left` by `(10 * config.default_amount)`
      vim.keymap.set(all_modes, "<S-A-h>", smart_splits.resize_left)
      vim.keymap.set(all_modes, "<S-A-j>", smart_splits.resize_down)
      vim.keymap.set(all_modes, "<S-A-k>", smart_splits.resize_up)
      vim.keymap.set(all_modes, "<S-A-l>", smart_splits.resize_right)
      vim.keymap.set(all_modes, "<S-A-Left>", smart_splits.resize_left)
      vim.keymap.set(all_modes, "<S-A-Down>", smart_splits.resize_down)
      vim.keymap.set(all_modes, "<S-A-Up>", smart_splits.resize_up)
      vim.keymap.set(all_modes, "<S-A-Right>", smart_splits.resize_right)
      -- moving between splits
      vim.keymap.set(all_modes, "<A-h>", smart_splits.move_cursor_left, { remap = true })
      vim.keymap.set(all_modes, "<A-j>", smart_splits.move_cursor_down, { remap = true })
      vim.keymap.set(all_modes, "<A-k>", smart_splits.move_cursor_up, { remap = true })
      vim.keymap.set(all_modes, "<A-l>", smart_splits.move_cursor_right, { remap = true })
      vim.keymap.set(all_modes, "<A-Left>", smart_splits.move_cursor_left, { remap = true })
      vim.keymap.set(all_modes, "<A-Down>", smart_splits.move_cursor_down, { remap = true })
      vim.keymap.set(all_modes, "<A-Up>", smart_splits.move_cursor_up, { remap = true })
      vim.keymap.set(all_modes, "<A-Right>", smart_splits.move_cursor_right, { remap = true })
      -- vim-herdr-navigation forwards Herdr navigation as Ctrl+h/j/k/l.
      vim.keymap.set(all_modes, "<C-h>", smart_splits.move_cursor_left, { remap = true })
      vim.keymap.set(all_modes, "<C-j>", smart_splits.move_cursor_down, { remap = true })
      vim.keymap.set(all_modes, "<C-k>", smart_splits.move_cursor_up, { remap = true })
      vim.keymap.set(all_modes, "<C-l>", smart_splits.move_cursor_right, { remap = true })
    end

    apply_mappings()
    vim.schedule(apply_mappings)
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyVimKeymaps",
      callback = apply_mappings,
    })
    -- vim.keymap.set(all_modes, '<C-\\>', require('smart-splits').move_cursor_previous)
    -- swapping buffers between windows
    -- vim.keymap.set("n", "<leader><leader>h", require("smart-splits").swap_buf_left)
    -- vim.keymap.set("n", "<leader><leader>j", require("smart-splits").swap_buf_down)
    -- vim.keymap.set("n", "<leader><leader>k", require("smart-splits").swap_buf_up)
    -- vim.keymap.set("n", "<leader><leader>l", require("smart-splits").swap_buf_right)
  end,
}
