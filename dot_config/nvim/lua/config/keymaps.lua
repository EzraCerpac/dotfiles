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

local actions = require("fzf-lua.actions")

-- TODO: Split into files
-- classify “home dot targets”
local function is_home_dot_target(abs, home)
	if not vim.startswith(abs, home .. "/") then
		return false
	end
	local tail = abs:sub(#home + 2) -- strip "$HOME/"
	return tail:match("^%.") -- ~/.zshrc, ~/.github/...
		or tail:match("^%.config/")
		or tail:match("^%.local/")
		or tail:match("^%.ssh/")
end

-- convert a chezmoi source path -> target path under $HOME
local function source_to_target(src_abs, chezmoi_dir, home)
	local rel = src_abs:sub(#chezmoi_dir + 1)
	local out = {}
	for seg in rel:gmatch("[^/]+") do
		seg = seg:gsub("^private_", "")
			:gsub("^exact_", "")
			:gsub("^executable_", "")
			:gsub("^readonly_", "")
			:gsub("^literal_", "")
			:gsub("^encrypted_", "")
		if seg:sub(1, 4) == "dot_" then
			seg = "." .. seg:sub(5)
		end
		seg = seg:gsub("slash", "/")
		seg = seg:gsub("%.tmpl$", "")
		table.insert(out, seg)
	end
	return home .. "/" .. table.concat(out, "/")
end

-- normalize one fzf-lua line into an absolute path
local function normalize_selected(line)
	if not line or line == "" then
		return nil
	end
	-- strip nerd-font icons / unicode spaces
	line = line:gsub("^[%z\1-\31\u{E000}-\u{F8FF}\u{2000}-\u{200B}]+", ""):gsub("^%s+", "")
	-- keep printable path-ish chars
	line = line:match("([%w%p%/%.%_%-~]+.*)") or line

	-- expand to absolute:
	if line:sub(1, 1) == "~" then
		return vim.fn.expand(line)
	elseif line:sub(1, 1) == "/" then
		return line
	else
		-- heuristic: “dotfile-like” relative paths belong under $HOME,
		-- everything else is relative to cwd
		if line:match("^%.") then
			return vim.fn.expand("~/" .. line)
		else
			return vim.fn.getcwd() .. "/" .. line
		end
	end
end

-- Add missing import / organize imports (pylsp rope_autoimport) IMPROVED
vim.keymap.set("n", "<leader>ci", function() -- improved aggregator version
	local bufnr = vim.api.nvim_get_current_buf()

	-- choose primary client (prefer pylsp) for encoding
	local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
	if #clients == 0 then
		vim.notify("No LSP clients", vim.log.levels.WARN)
		return
	end
	local primary = clients[1]
	for _, c in ipairs(clients) do
		if c.name == "pylsp" then
			primary = c
			break
		end
	end
	local enc = primary.offset_encoding or "utf-16"

	local pos = vim.api.nvim_win_get_cursor(0)
	local line = pos[1] - 1
	local col = pos[2]

	local params = {
		textDocument = vim.lsp.util.make_text_document_params(bufnr),
		range = { start = { line = line, character = col }, ["end"] = { line = line, character = col } },
		context = { diagnostics = {} },
		position_encoding = enc,
	}

	local function strip_number_prefix(title)
		return (title or ""):gsub("^%s*%d+%.%s*", "")
	end

	local function matches_import(title, kind)
		if kind == "source.addMissingImports" then return true end
		title = strip_number_prefix((title or ""):lower())
		return title:match("%%f[%w]import[%s%w_%.]*%[pylsp%]")
			or title:match("^import%s")
			or title:match("add missing import")
			or title:match("missing import")
			or title:match("autoimport")
	end

	local function matches_organize(title, kind)
		if kind == "source.organizeImports" then return true end
		title = strip_number_prefix((title or ""):lower())
		return title:match("organize imports")
	end

	local function apply(chosen)
		if not chosen then
			vim.notify("No matching import action", vim.log.levels.INFO)
			return
		end
		if chosen.edit then
			vim.lsp.util.apply_workspace_edit(chosen.edit, enc)
		end
		local cmd = chosen.command or (type(chosen.command) == "table" and chosen.command or nil)
		if cmd then
			vim.lsp.buf.execute_command(cmd)
		end
	end

	-- Strategy: try request_all with different param variants to coax pylsp
	local tried = {}
	local function variant(label, mod)
		local p = vim.deepcopy(params)
		mod(p)
		tried[#tried+1] = label
		return p
	end

	local variants = {
		variant("cursor-empty-diags", function(_) end),
		variant("no-diags", function(p) p.context.diagnostics = nil end),
		variant("line-range", function(p) p.range = { start = { line = line, character = 0 }, ['end'] = { line = line, character = 999 }} end),
		variant("full-doc", function(p)
			p.range = { start = { line = 0, character = 0 }, ['end'] = { line = vim.api.nvim_buf_line_count(bufnr)-1, character = 0 }}
		end),
	}

	local collected = {}
	local seen_titles = {}

	local function accumulate(actions)
		if not actions then return end
		if actions.actions then actions = actions.actions end
		for _, a in ipairs(actions) do
			local title = a.title or "?"
			if not seen_titles[title] then
				seen_titles[title] = true
				collected[#collected+1] = a
			end
		end
	end

	local function finish_and_apply()
		if #collected == 0 then
			vim.notify("No code actions (tried: "..table.concat(tried, ", ")..")", vim.log.levels.INFO)
			return
		end
		local titles = {}
		for _, a in ipairs(collected) do titles[#titles+1] = a.title or '?' end
		vim.notify("CI titles(all): "..table.concat(titles, " | "), vim.log.levels.DEBUG)
		local import_action, organize_action
		for _, a in ipairs(collected) do
			if matches_import(a.title, a.kind) then import_action = a break
			elseif matches_organize(a.title, a.kind) then organize_action = a end
		end
		if import_action then
			apply(import_action)
			return
		end
		if organize_action then apply(organize_action) return end
		-- fallback: invoke builtin picker so user can choose (non-blocking)
		vim.notify("Falling back to builtin code action UI", vim.log.levels.INFO)
		vim.lsp.buf.code_action({ apply = true })
	end

	local pending = #variants
	for _, p in ipairs(variants) do
		vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", p, function(results)
			for client_id, res in pairs(results) do
				if res.error then
					vim.notify("codeAction error ("..client_id.."): "..res.error.message, vim.log.levels.WARN)
				else
					accumulate(res.result)
				end
			end
			pending = pending - 1
			if pending == 0 then finish_and_apply() end
		end)
	end
end, { desc = "Add missing import (pylsp rope_autoimport)" })

require("fzf-lua").setup({
	files = {
		hidden = false, -- your pref
		actions = {
			["ctrl-h"] = actions.toggle_hidden, -- your remap

			["default"] = function(sel)
				if not sel or #sel == 0 then
					return
				end
				local raw = sel[1]
				local file = normalize_selected(raw)
				if not file then
					return
				end

				local home = vim.fn.expand("~")
				local chezmoi_dir = vim.fn.expand("~/.local/share/chezmoi/")

				if vim.startswith(file, chezmoi_dir) then
					-- selected a source path: map to target, then ChezmoiEdit
					local target = source_to_target(file, chezmoi_dir, home)
					vim.cmd("ChezmoiEdit " .. vim.fn.fnameescape(target))
					return
				end

				if is_home_dot_target(file, home) then
					-- selected a home “dot target”: always go through chezmoi
					vim.cmd("ChezmoiEdit " .. vim.fn.fnameescape(file))
					return
				end

				-- normal project file
				vim.cmd("edit " .. vim.fn.fnameescape(file))
			end,
		},
	},
})
