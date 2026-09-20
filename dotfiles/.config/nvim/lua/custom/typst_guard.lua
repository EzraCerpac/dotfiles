local M = {}

local PLACEHOLDER = "⟦TYPST_GUARD_%04d⟧"

local function source_text(value)
  if type(value) == "table" then
    return table.concat(value, "\n")
  end
  return value or ""
end

local function serialize_node(node, bufnr)
  if node:type() == "text" or node:type() == "shorthand" or node:type() == "quote" then
    return "<text>"
  end
  local children = {}
  for child in node:iter_children() do
    local serialized = serialize_node(child, bufnr)
    if not (serialized == "<text>" and children[#children] == "<text>") then
      table.insert(children, serialized)
    end
  end
  if #children == 0 then
    local source = vim.treesitter.get_node_text(node, bufnr) or ""
    if source:match("^%s*$") then
      source = "<ws>"
    end
    return node:type() .. "{" .. source .. "}"
  end
  return node:type() .. "[" .. table.concat(children, ",") .. "]"
end

local function parse_source(content)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = "typst"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n", { plain = true }))
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "typst")
  if not ok then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil, "Typst Tree-sitter parser is unavailable"
  end
  local tree = parser:parse()[1]
  local root = tree and tree:root()
  if not root or root:has_error() then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil, "Typst syntax contains a parse error"
  end
  return bufnr, root
end

function M.fingerprint(value)
  local content = source_text(value)
  local bufnr, root = parse_source(content)
  if not bufnr then return nil, root end
  local result = serialize_node(root, bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  return result
end

local function line_starts(source)
  local starts, cursor = { 1 }, 1
  while true do
    local newline = source:find("\n", cursor, true)
    if not newline then break end
    starts[#starts + 1] = newline + 1
    cursor = newline + 1
  end
  return starts
end

local function text_ranges(root, source)
  local starts = line_starts(source)
  local ranges = {}
  local function offset(row, column)
    return starts[row + 1] + column
  end
  local function add_text(node)
    local start_row, start_column, end_row, end_column = node:range()
    local start_at, finish_at = offset(start_row, start_column), offset(end_row, end_column)
    local cursor = start_at
    for child in node:iter_children() do
      local child_start_row, child_start_column, child_end_row, child_end_column = child:range()
      local child_start = offset(child_start_row, child_start_column)
      local child_finish = offset(child_end_row, child_end_column)
      if child_start > cursor then table.insert(ranges, { start = cursor, finish = child_start }) end
      cursor = math.max(cursor, child_finish)
    end
    if cursor < finish_at then table.insert(ranges, { start = cursor, finish = finish_at }) end
  end
  local function visit(node)
    if node:type() == "text" then
      add_text(node)
      return
    end
    for child in node:iter_children() do visit(child) end
  end
  visit(root)
  table.sort(ranges, function(a, b) return a.start < b.start end)
  return ranges
end

local function editable_ranges(source, ranges)
  local editable = {}
  local function add(start_at, finish_at)
    if finish_at > start_at then table.insert(editable, { start = start_at, finish = finish_at }) end
  end
  for _, range in ipairs(ranges) do
    local cursor, prose_start = range.start, range.start
    while cursor < range.finish do
      local tail = source:sub(cursor, range.finish - 1)
      local previous = source:sub(cursor - 1, cursor - 1)
      local identifier = tail:match("^[%w_][%w_%-]*")
      local token = nil
      if (cursor == range.start or not previous:match("[%w_%-]"))
        and identifier
        and identifier:match("%d")
        and identifier:match("[%a_]") then
        token = identifier
      end
      token = token or tail:match("^https?://[^%s%]%)}>,;]+")
        or tail:match("^10%.%d%d%d%d%d?%d?%d?%d?%d?/[^%s%]%)}>,;]+")
      if not token then
        local first = tail:sub(1, 1)
        local second = tail:sub(2, 2)
        if first:match("%d") or ((first == "+" or first == "-") and second:match("%d")) then
          token = tail:match("^[%+%-]?%d[%d%.,%%]*[eE][%+%-]?%d+")
            or tail:match("^[%+%-]?%d[%d%.,%%]*")
        end
      end
      if token then
        add(prose_start, cursor)
        cursor = cursor + #token
        prose_start = cursor
      else
        cursor = cursor + 1
      end
    end
    add(prose_start, range.finish)
  end
  return editable
end

local function mask_source(source, editable)
  local protected, pieces = {}, {}
  local function append(value)
    if value ~= "" then table.insert(pieces, value) end
  end
  local function protect(value)
    if value == "" then return end
    protected[#protected + 1] = value
    append(string.format(PLACEHOLDER, #protected))
  end
  local function protect_range(start_at, finish_at)
    local cursor = start_at
    while cursor < finish_at do
      local newline = source:find("\n", cursor, true)
      if not newline or newline >= finish_at then
        protect(source:sub(cursor, finish_at - 1))
        break
      end
      protect(source:sub(cursor, newline - 1))
      append("\n")
      cursor = newline + 1
    end
  end
  local cursor = 1
  for _, range in ipairs(editable) do
    protect_range(cursor, range.start)
    append(source:sub(range.start, range.finish - 1))
    cursor = range.finish
  end
  protect_range(cursor, #source + 1)
  return table.concat(pieces), protected
end

local function placeholder_ids(text)
  local ids = {}
  for id in text:gmatch("⟦TYPST_GUARD_(%d+)⟧") do
    table.insert(ids, tonumber(id))
  end
  return ids
end

function M.prepare(value, paragraph_mode)
  local source = source_text(value)
  local fingerprint, err = M.fingerprint(source)
  if not fingerprint then return nil, err end
  if source:find("⟦TYPST_GUARD_") then return nil, "source contains a reserved Typst guard placeholder" end
  local bufnr, root = parse_source(source)
  if not bufnr then return nil, root end
  local ranges = editable_ranges(source, text_ranges(root, source))
  vim.api.nvim_buf_delete(bufnr, { force = true })
  local prepared, protected = mask_source(source, ranges)
  local chunks, spans = {}, {}
  local function add_chunk(start_at, finish_at)
    if finish_at >= start_at then
      local text = prepared:sub(start_at, finish_at)
      local prose = text:gsub("⟦TYPST_GUARD_%d+⟧", ""):gsub("%s", "")
      if prose ~= "" then
        table.insert(chunks, { id = #chunks + 1, text = text })
        table.insert(spans, { start = start_at, finish = finish_at })
      end
    end
  end
  if paragraph_mode == false then
    add_chunk(1, #prepared)
  else
    local start_at, paragraph_start = 1, nil
    local source_lines = vim.split(source, "\n", { plain = true })
    local line_number = 0
    for line in (prepared .. "\n"):gmatch("(.-)\n") do
      line_number = line_number + 1
      local finish_at = start_at + #line - 1
      if (source_lines[line_number] or ""):match("^%s*$") then
        if paragraph_start then add_chunk(paragraph_start, start_at - 2) end
        paragraph_start = nil
      elseif not paragraph_start then
        paragraph_start = start_at
      end
      start_at = finish_at + 2
    end
    if paragraph_start then add_chunk(paragraph_start, #prepared) end
  end
  if #chunks == 0 then return nil, "Typst input contains no prose to rewrite" end
  return { source = source, fingerprint = fingerprint, protected = protected, template = prepared, spans = spans, paragraph_mode = paragraph_mode ~= false }, chunks
end

function M.restore(plan, outputs)
  if type(plan) ~= "table" or type(outputs) ~= "table" then return nil, "invalid Typst guard plan" end
  local by_id = {}
  for _, output in ipairs(outputs) do
    if by_id[output.id] then return nil, "duplicate chunk id" end
    by_id[output.id] = output.text or ""
  end
  local result = plan.template
  for i = #plan.spans, 1, -1 do
    local span, text = plan.spans[i], by_id[i]
    if text == nil then return nil, "missing chunk output" end
    local expected = placeholder_ids(plan.template:sub(span.start, span.finish))
    local actual = placeholder_ids(text)
    if #expected ~= #actual then return nil, "protected Typst placeholder mismatch" end
    for n = 1, #expected do if expected[n] ~= actual[n] then return nil, "protected Typst placeholder reordered" end end
    result = result:sub(1, span.start - 1) .. text .. result:sub(span.finish + 1)
  end
  for id, value in ipairs(plan.protected) do
    local marker = string.format(PLACEHOLDER, id)
    local count = 0
    result = result:gsub(marker, function() count = count + 1; return value end)
    if count ~= 1 then return nil, "protected Typst placeholder missing or duplicated" end
  end
  local fingerprint, err = M.fingerprint(result)
  if not fingerprint then return nil, err end
  if fingerprint ~= plan.fingerprint then return nil, "Typst syntax or structural fingerprint changed" end
  return result
end

M._placeholder_ids = placeholder_ids
return M
