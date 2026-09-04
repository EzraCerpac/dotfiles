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

function M.fingerprint(value)
  local content = source_text(value)
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
  local result = serialize_node(root, bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  return result
end

local function protect_line(line, protected)
  local spans = {}
  local function span(start_at, finish_at)
    table.insert(spans, { start = start_at, finish = finish_at })
  end

  -- Whole command and delimiter lines are never prose.
  if line:match("^%s*#")
    or line:match("^%s*[%[%]%(%){},]+%s*$") then
    span(1, #line)
  elseif line:match("^%s*```") then
    span(1, #line)
  else
    local _, heading_end = line:find("^%s*=+%s+")
    local _, list_end = line:find("^%s*[-+/>]%s+")
    local _, bracket_start = line:find("^%s*%[")
    if heading_end then span(1, heading_end) end
    if list_end then span(1, list_end) end
    if bracket_start then span(1, bracket_start) end
    local bracket_finish = line:find("%]%s*,?%s*$")
    if bracket_finish then span(bracket_finish, #line) end

    local i = 1
    while i <= #line do
      local c = line:sub(i, i)
      if c == "\\" then
        i = i + 2
      elseif c == "$" then
        local j = line:find("$", i + 1, true)
        if j then
          span(i, j)
          i = j + 1
        else
          span(i, i)
          i = i + 1
        end
      elseif c == "`" then
        local j = line:find("`", i + 1, true)
        if j then
          span(i, j)
          i = j + 1
        else
          span(i, i)
          i = i + 1
        end
      elseif c == "*" or c == "_" then
        local j = line:find(c, i + 1, true)
        span(i, i)
        if j then
          span(j, j)
          i = j + 1
        else
          i = i + 1
        end
      elseif c == "<" then
        local j = line:find(">", i + 1, true)
        if j then span(i, j); i = j + 1 else i = i + 1 end
      elseif c == "@" then
        local j = line:find("[^%w_:-]", i + 1)
        j = (j and j - 1) or #line
        span(i, j)
        i = j + 1
      elseif line:sub(i):match("^https?://") then
        local j = line:find("%s", i) or (#line + 1)
        span(i, j - 1)
        i = j
      elseif line:sub(i):match("^10%.%d%d%d%d%d?%d?%d?%d?%d?/") then
        local token = line:sub(i):match("^10%.%d%d%d%d%d?%d?%d?%d?%d?/[^%s%]%)}>,;]+")
        span(i, i + #token - 1)
        i = i + #token
      elseif line:sub(i):match("^%d[%d%.,%%]*") then
        local token = line:sub(i):match("^%d[%d%.,%%]*")
        span(i, i + #token - 1)
        i = i + #token
      else
        i = i + 1
      end
    end
  end

  table.sort(spans, function(a, b) return a.start < b.start end)
  local result = line
  local ids = {}
  for n, item in ipairs(spans) do
    ids[n] = #protected + 1
    table.insert(protected, line:sub(item.start, item.finish))
  end
  for n = #spans, 1, -1 do
    local item, id = spans[n], ids[n]
    result = result:sub(1, item.start - 1) .. string.format(PLACEHOLDER, id) .. result:sub(item.finish + 1)
  end
  return result
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
  local protected = {}
  local lines = vim.split(source, "\n", { plain = true })
  local in_fence = false
  local in_math = false
  for i, line in ipairs(lines) do
    if in_fence or line:match("^%s*```") then
      local closes = line:match("^%s*```") and in_fence
      local id = #protected + 1
      protected[id] = line
      lines[i] = string.format(PLACEHOLDER, id)
      if in_fence then
        if closes then in_fence = false end
      else
        in_fence = true
      end
    elseif in_math or line:match("^%s*%$%s*$") then
      local delimiter = line:match("^%s*%$%s*$") ~= nil
      local id = #protected + 1
      protected[id] = line
      lines[i] = string.format(PLACEHOLDER, id)
      if delimiter then in_math = not in_math end
    else
      lines[i] = protect_line(line, protected)
    end
  end
  local prepared = table.concat(lines, "\n")
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
    for line in (prepared .. "\n"):gmatch("(.-)\n") do
      local finish_at = start_at + #line - 1
      if line:match("^%s*$") then
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
