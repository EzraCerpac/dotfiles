---@type LazySpec
return {
  "mrjones2014/smart-splits.nvim",
  -- https://github.com/mrjones2014/smart-splits.nvim?tab=readme-ov-file
  event = "VeryLazy",
  opts = function()
    -- local wezterm_cli = vim.fn.exepath("wezterm")
    -- if wezterm_cli == "" then
    --   wezterm_cli = "wezterm"
    -- end
    return {
      multiplexer_integration = "wezterm",
      disable_multiplexer_nav_when_zoomed = true,
      -- wezterm_cli_path = wezterm_cli,
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
        return { aerospace_focus_script, direction }
      end

      local env_cli = vim.env.AEROSPACE_CLI
      if env_cli and env_cli ~= "" and vim.fn.executable(env_cli) == 1 then
        return { env_cli, "focus", "--boundaries", "all-monitors-outer-frame", direction }
      end

      local fallback = "aerospace"
      if vim.fn.executable(fallback) == 1 then
        return { fallback, "focus", "--boundaries", "all-monitors-outer-frame", direction }
      end

      local homebrew_cli = "/opt/homebrew/bin/aerospace"
      if vim.fn.executable(homebrew_cli) == 1 then
        return { homebrew_cli, "focus", "--boundaries", "all-monitors-outer-frame", direction }
      end

      local usr_local_cli = "/usr/local/bin/aerospace"
      if vim.fn.executable(usr_local_cli) == 1 then
        return { usr_local_cli, "focus", "--boundaries", "all-monitors-outer-frame", direction }
      end
    end

    local function focus_with_aerospace(direction)
      local command = resolve_focus_command(direction)
      if not command then
        return false, "AeroSpace CLI unavailable"
      end

      if vim.fn.has("nvim-0.10") == 1 and vim.system then
        local result = vim.system(command, { text = true }):wait()
        if result.code == 0 then
          return true
        end
        local stderr = vim.trim(result.stderr or "")
        return false, #stderr > 0 and stderr or string.format("command exited with code %d", result.code)
      end

      local output = vim.fn.system(command)
      if vim.v.shell_error == 0 then
        return true
      end
      output = vim.trim(output or "")
      if output == "" then
        output = string.format("command exited with code %d", vim.v.shell_error)
      end
      return false, output
    end

    opts.at_edge = function(ctx)
      local ok, err = focus_with_aerospace(ctx.direction)
      if ok then
        return
      end

      vim.notify_once(
        string.format(
          "smart-splits: AeroSpace focus handoff failed for %s (%s)",
          tostring(ctx.direction),
          err or "unknown"
        ),
        vim.log.levels.WARN
      )
    end

    smart_splits.setup(opts)
    -- Ensure WezTerm user vars are kept in sync for smart navigation
    require("smart-splits.mux.utils").startup()
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
      vim.keymap.set(all_modes, "<C-A-h>", smart_splits.resize_left)
      vim.keymap.set(all_modes, "<C-A-j>", smart_splits.resize_down)
      vim.keymap.set(all_modes, "<C-A-k>", smart_splits.resize_up)
      vim.keymap.set(all_modes, "<C-A-l>", smart_splits.resize_right)
      -- moving between splits
      vim.keymap.set(all_modes, "<A-h>", smart_splits.move_cursor_left, { remap = true })
      vim.keymap.set(all_modes, "<A-j>", smart_splits.move_cursor_down, { remap = true })
      vim.keymap.set(all_modes, "<A-k>", smart_splits.move_cursor_up, { remap = true })
      vim.keymap.set(all_modes, "<A-l>", smart_splits.move_cursor_right, { remap = true })
    end

    apply_mappings()
    vim.schedule(apply_mappings)
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyVimKeymaps",
      callback = apply_mappings,
    })
    -- vim.keymap.set(all_modes, '<C-\\>', require('smart-splits').move_cursor_previous)
    -- swapping buffers between windows
    vim.keymap.set("n", "<leader><leader>h", require("smart-splits").swap_buf_left)
    vim.keymap.set("n", "<leader><leader>j", require("smart-splits").swap_buf_down)
    vim.keymap.set("n", "<leader><leader>k", require("smart-splits").swap_buf_up)
    vim.keymap.set("n", "<leader><leader>l", require("smart-splits").swap_buf_right)
  end,
}
