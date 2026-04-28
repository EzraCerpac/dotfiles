local function next_word(text)
  local first_line = text:match("^[^\n]*") or text
  local leading = first_line:match("^%s*") or ""
  local rest = first_line:sub(#leading + 1)

  if rest == "" then
    return leading
  end

  local token = rest:match("^[%w_]+") or rest:match("^%p+") or rest:match("^%S+")
  if not token then
    return leading
  end

  local trailing = rest:sub(#token + 1):match("^%s*") or ""
  return leading .. token .. trailing
end

local function accept_copilot_word()
  vim.lsp.inline_completion.get({
    on_accept = function(item)
      if type(item.insert_text) ~= "string" then
        return item
      end

      local text = next_word(item.insert_text)
      if text == "" then
        return nil
      end

      item.insert_text = text
      return item
    end,
  })

  return ""
end

return {
  {
    "neovim/nvim-lspconfig",
    keys = {
      {
        "<M-w>",
        accept_copilot_word,
        desc = "Accept Copilot Word",
        expr = true,
        mode = "i",
      },
    },
  },
}
