local function next_word(text)
  local first_line = text:match("^[^\n]*") or text
  local leading = first_line:match("^%s*") or ""
  local rest = first_line:sub(#leading + 1)

  if rest == "" then
    return ""
  end

  local token = rest:match("^[%w_]+") or rest:match("^%p+") or rest:match("^%S+")
  if not token then
    return leading
  end

  local trailing = rest:sub(#token + 1):match("^%s*") or ""
  return leading .. token .. trailing
end

local function lcp(a, b)
  local i = 1
  while i <= #a and i <= #b and a:sub(i, i) == b:sub(i, i) do
    i = i + 1
  end
  return i
end

local function completion_text(insert_text)
  if type(insert_text) == "string" then
    return insert_text
  end
  if type(insert_text) == "table" and type(insert_text.value) == "string" then
    return insert_text.value
  end
end

local function text_filetype(bufnr)
  local ft = vim.bo[bufnr or 0].filetype
  return ft == "markdown" or ft == "text"
end

local function completion_skip(bufnr, item, text)
  local range = item.range
  if not range then
    return 1
  end

  local row, col = range.start.row, range.start.col
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local first_line = text:match("^[^\n]*") or text
  local skip = lcp(line:sub(col + 1), first_line)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) == bufnr then
    local cursor = vim.api.nvim_win_get_cursor(win)
    local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
    if row == cursor_row then
      skip = math.max(skip, cursor_col - col + 1)
    end
  end
  return skip
end

local function partial_completion_text(bufnr, item)
  local text = completion_text(item.insert_text)
  if not text then
    return nil
  end

  local skip = completion_skip(bufnr, item, text)
  local raw_suffix = text:sub(skip)
  if not raw_suffix:find("%S") then
    return nil
  end

  local suffix = next_word(raw_suffix)
  if suffix == "" or not suffix:find("%S") then
    return nil
  end
  return text:sub(1, skip - 1) .. suffix
end

local function tab_fallback()
  if vim.fn.maparg("<Plug>(Tabout)", "i") ~= "" then
    return vim.api.nvim_replace_termcodes("<Plug>(Tabout)", true, true, true)
  end
  return "\t"
end

local function accept_copilot_word_action(bufnr)
  return vim.lsp.inline_completion.get({
    bufnr = bufnr,
    on_accept = function(item)
      local text = partial_completion_text(bufnr, item)
      if not text then
        return nil
      end

      item.insert_text = text
      return item
    end,
  })
end

local function accept_copilot_word(bufnr)
  return accept_copilot_word_action(bufnr) and "" or tab_fallback()
end

local function accept_copilot_full(bufnr)
  vim.lsp.inline_completion.get({ bufnr = bufnr })
  return ""
end

local default_ai_accept

local function ai_accept_text_word()
  if text_filetype(0) then
    return accept_copilot_word_action(0)
  end
  return default_ai_accept and default_ai_accept()
end

local function override_ai_accept()
  if not LazyVim or not LazyVim.cmp or not LazyVim.cmp.actions then
    return
  end
  if LazyVim.cmp.actions.ai_accept ~= ai_accept_text_word then
    default_ai_accept = LazyVim.cmp.actions.ai_accept
    LazyVim.cmp.actions.ai_accept = ai_accept_text_word
  end
end

local function map_text_copilot_keys(event)
  vim.b[event.buf].sidekick_nes = false
  override_ai_accept()
  local opts = { buffer = event.buf, expr = true }
  vim.keymap.set(
    "i",
    "<Tab>",
    function()
      return accept_copilot_word(event.buf)
    end,
    vim.tbl_extend("force", opts, {
      desc = "Accept Copilot Word",
    })
  )
  vim.keymap.set(
    "i",
    "<M-Tab>",
    function()
      return accept_copilot_full(event.buf)
    end,
    vim.tbl_extend("force", opts, {
      desc = "Accept Copilot Full",
    })
  )
end

return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("text_copilot_accept_keys", { clear = true }),
        pattern = { "markdown", "text" },
        callback = map_text_copilot_keys,
      })
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("text_copilot_accept_action", { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.name == "copilot" then
            override_ai_accept()
          end
        end,
      })
    end,
  },
}
