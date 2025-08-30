return {
  "3rd/image.nvim",
  build = false,
  opts = {
    -- Rendering backend: Kitty protocol works with Ghostty/Kitty/WezTerm
    backend = "kitty",
    -- Use ImageMagick CLI backend for processing
    processor = "magick_cli",

    -- Avoid global hijack to prevent conflicts with MiniFiles' virtual URIs
    hijack_file_patterns = {},

    -- Keep native integrations
    integrations = {
      markdown = {
        enabled = true,
        -- keep defaults; this version exposes only 'enabled' in defaults
      },
      -- neorg = { enabled = true },
    },

    -- Quality-of-life options
    window_overlap_clear_enabled = true,
    -- Do NOT ignore 'minifiles' so overlapped regions are cleared
    window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "snacks_notif", "scrollview", "scrollview_sign" },
    editor_only_render_when_focused = false,
    tmux_show_only_in_active_window = false,
  },
  config = function(_, opts)
    local image = require("image")
    image.setup(opts)

    -- Minimal, safe auto-render for real image buffers.
    -- We keep global hijack off to not break MiniFiles (minifiles://...).
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
      callback = function(ev)
        local name = vim.api.nvim_buf_get_name(ev.buf) or ""
        -- Skip MiniFiles virtual buffers
        if name:match("^minifiles:") then return end
        -- Only render if the path actually exists
        local abs = vim.fn.fnamemodify(name, ":p")
        if vim.uv.fs_stat(abs) then
          pcall(image.hijack_buffer, name, 0, ev.buf)
        end
      end,
    })
  end,
}
