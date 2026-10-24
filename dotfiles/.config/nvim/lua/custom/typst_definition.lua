local M = {}

local markup_scopes = {
  source_file = true,
  content = true,
  heading = true,
  strong = true,
  emph = true,
  item = true,
  term = true,
}
local rendered_content =
  { text = true, math = true, ref = true, heading = true, strong = true, emph = true, item = true, term = true }

local function emitted_markup(node)
  while node:parent() do
    local parent = node:parent()
    local kind = parent:type()
    if kind == "code" then
      if node:type() ~= "content" then
        return -- Only a directly emitted literal content block is provable.
      end
    elseif kind ~= "section" and not markup_scopes[kind] then
      return -- Assignments, functions and conditional or repeated content need Tinymist.
    end
    node = parent
  end
  return node:type() == "source_file" or nil
end

local function markup_attachment(node, bufnr)
  local preceded = false
  while node do
    local previous = node:prev_named_sibling()
    while previous do
      if rendered_content[previous:type()] and vim.treesitter.get_node_text(previous, bufnr):find("%S") then
        preceded = true
        break
      end
      previous = previous:prev_named_sibling()
    end
    local parent = node:parent()
    if not parent then
      return false
    end
    local kind = parent:type()
    if markup_scopes[kind] then
      -- Without a proven predecessor, even an empty heading may own the label.
      if preceded then
        return emitted_markup(parent)
      end
      return
    end
    if kind ~= "section" then
      return false -- Code values, math and uncertain contexts need Tinymist.
    end
    node = parent
  end
  return false
end

-- Resolve literal references in the current buffer, including unsaved labels.
function M.local_target(bufnr, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "typst")
  if not ok or not parser then
    return
  end
  local tree = parser:parse()[1]
  local node = tree:root():named_descendant_for_range(row, col, row, col)
  if not node or node:type() ~= "ref" then
    return
  end
  local label = "<" .. vim.treesitter.get_node_text(node, bufnr):sub(2) .. ">"
  local query = vim.treesitter.query.parse("typst", "(label) @label")
  local target
  for _, candidate in query:iter_captures(tree:root(), bufnr) do
    if vim.treesitter.get_node_text(candidate, bufnr) == label then
      local attached = markup_attachment(candidate, bufnr)
      if attached == nil then
        return -- An uncertain attachment could render beside a known one.
      end
      if attached then
        if target then
          return -- Ambiguous labels need the compiler's interpretation.
        end
        local r, c = candidate:range()
        target = { r + 1, c }
      end
    end
  end
  return target
end

function M.goto_definition()
  local bufnr, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local target = M.local_target(bufnr, cursor[1] - 1, cursor[2])
  if target then
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(win, target)
    vim.cmd("normal! zv")
    return
  end
  local client = vim.tbl_filter(function(c)
    return not c:is_stopped()
  end, vim.lsp.get_clients({ bufnr = bufnr, name = "tinymist" }))[1]
  if not client then
    vim.notify("Tinymist is not attached", vim.log.levels.WARN)
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local done = false
  local accepted, request_id = client:request(
    "textDocument/definition",
    vim.lsp.util.make_position_params(win, client.offset_encoding),
    function(err, result)
      if done then
        return
      end
      done = true
      if
        vim.api.nvim_get_current_win() ~= win
        or vim.api.nvim_get_current_buf() ~= bufnr
        or vim.api.nvim_buf_get_changedtick(bufnr) ~= tick
        or not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
      then
        return -- Do not jump after the user has moved elsewhere.
      end
      if err then
        vim.notify(err.message or tostring(err), vim.log.levels.WARN)
      elseif not result or vim.tbl_isempty(result) then
        vim.notify("No definition found", vim.log.levels.INFO)
      else
        local locations = (result.uri or result.targetUri) and { result } or result
        if #locations == 1 then
          vim.lsp.util.show_document(locations[1], client.offset_encoding, { focus = true })
        else
          vim.fn.setqflist({}, " ", {
            title = "Typst definitions",
            items = vim.lsp.util.locations_to_items(locations, client.offset_encoding),
          })
          vim.cmd("copen")
        end
      end
    end,
    bufnr
  )
  if accepted then
    vim.defer_fn(function()
      if not done then
        done = true
        client:cancel_request(request_id)
        vim.notify("Tinymist definition request timed out (5s)", vim.log.levels.WARN)
      end
    end, 5000)
  else
    vim.notify("Tinymist could not accept the definition request", vim.log.levels.WARN)
  end
end

return M
