-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("n", "<leader>j", "*``cgn", { desc = "Search word under cursor and change next match" })
--
-- vim.keymap.set("x", "<leader>j", function()
--   -- Yank visual selection to register z
--   vim.cmd('normal! "zy')
--   -- Escape for search
--   local text = vim.fn.getreg("z")
--   text = vim.fn.escape(text, "\\/.*$^~[]")
--   vim.fn.setreg("/", text)
--   -- Exit visual mode and feed 'n' and 'cgn' as keypresses
--   vim.api.nvim_feedkeys("n", "n", false)
--   vim.api.nvim_feedkeys("cgn", "n", false)
-- end, { desc = "Change visual selection and repeat with dot" })

-- Ensure <leader>e opens mini.files (override any LazyVim defaults)
vim.keymap.set("n", "<leader>e", function()
	require("mini.files").open(vim.api.nvim_buf_get_name(0), true)
end, { desc = "Open mini.files (Directory of Current File)" })

require("fzf-lua").setup({
	files = {
		hidden = false,
		actions = {
			["ctrl-h"] = require("fzf-lua.actions").toggle_hidden,

			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end
				local file = selected[1]

				-- 1. Strip leading icons / whitespace
				file = file:gsub("^[%z\1-\31\u{E000}-\u{F8FF}\u{2000}-\u{200B}]+", "")
				file = file:gsub("^%s+", "")
				file = file:match("([%w%p%/%.%_%-~]+.*)")

				local chezmoi_dir = vim.fn.expand("~/.local/share/chezmoi/")
				local home = vim.fn.expand("~")

				-- 2. Expand relative paths intelligently
				if not file:match("^/") and not file:match("^~") then
					if file:match("^%.") then
						-- dotfiles: prefer chezmoi source dir
						local candidate = chezmoi_dir .. file:gsub("^%.", "dot_")
						if vim.fn.filereadable(candidate) == 1 or vim.fn.isdirectory(candidate) == 1 then
							file = candidate
						else
							-- fallback to $HOME
							file = home .. "/" .. file
						end
					else
						-- normal relative path → project cwd
						file = vim.fn.getcwd() .. "/" .. file
					end
				end

				-- 3. If path is inside chezmoi’s source dir, map to target
				if file:sub(1, #chezmoi_dir) == chezmoi_dir then
					local target = file:gsub(chezmoi_dir, home .. "/")
					target = target:gsub("^dot_", ".")
					target = target:gsub("private_", "")
					target = target:gsub("slash", "/")
					vim.cmd("ChezmoiEdit " .. vim.fn.fnameescape(target))
				else
					vim.cmd("edit " .. vim.fn.fnameescape(file))
				end
			end,
		},
	},
})
