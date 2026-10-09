local M = {}
local cache, mains = {}, {}
local uv = vim.uv
local limit = 2000
local label_chars = "[%w_\128-\255:%-]"

local function identity(client, bufnr)
  local root = client.root_dir or (client.config or {}).root_dir
  if type(root) ~= "string" or root == "" then
    return
  end
  root = vim.fs.normalize(root)
  local main = mains[client.id]
  if not main or main.root ~= root then
    main = { root = root, path = vim.api.nvim_buf_get_name(bufnr) }
  end
  if main.path == "" then
    return
  end
  return root, vim.fs.normalize(main.path)
end

local function filename(root, main)
  return vim.fn.stdpath("state") .. "/typst-references/" .. vim.fn.sha256(root .. "\0" .. main) .. ".json"
end

local function valid_label(label)
  return type(label) == "string" and #label <= 512 and label:match("^" .. label_chars .. "+$") ~= nil
end

local function load(root, main)
  local path = filename(root, main)
  if cache[path] then
    return cache[path], path
  end
  local labels = {}
  local stat = uv.fs_stat(path)
  if stat and stat.size < 1024 * 1024 then
    local ok, data = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    end)
    if
      ok
      and type(data) == "table"
      and data.version == 1
      and data.root == root
      and data.main == main
      and type(data.labels) == "table"
      and #data.labels <= limit
    then
      local valid = true
      for key, label in pairs(data.labels) do
        if type(key) ~= "number" or key < 1 or key > #data.labels or key % 1 ~= 0 or not valid_label(label) then
          valid = false
          break
        end
      end
      if valid then
        labels = data.labels
      end
    end
  end
  cache[path] = labels
  return labels, path
end

local function save(client, items, bufnr)
  local root, main = identity(client, bufnr)
  if not root then
    return
  end
  local labels, seen = {}, {}
  for _, item in ipairs(items) do
    if item.kind == 18 and valid_label(item.label) and not seen[item.label] then
      seen[item.label] = true
      labels[#labels + 1] = item.label
      if #labels == limit then
        break
      end
    end
  end
  if #labels == 0 then
    return
  end -- Errors and empty replies preserve the last successful list.
  local previous, path = load(root, main)
  -- A prefix response is only a subset: retain labels observed in other successful replies.
  for _, label in ipairs(previous) do
    if #labels == limit then
      break
    end
    if not seen[label] then
      seen[label] = true
      labels[#labels + 1] = label
    end
  end
  table.sort(labels)
  if vim.deep_equal(previous, labels) then
    return
  end
  cache[path] = labels
  vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
  local temp = path .. "." .. uv.hrtime() .. ".tmp"
  local fd = uv.fs_open(temp, "wx", 384)
  if not fd then
    return
  end
  local written = uv.fs_write(fd, vim.json.encode({ version = 1, root = root, main = main, labels = labels }), 0)
  uv.fs_close(fd)
  if written then
    uv.fs_rename(temp, path)
  end
  uv.fs_unlink(temp)
end

function M.set_main(client_id, root, path)
  if type(root) ~= "string" or type(path) ~= "string" or root == "" or path == "" then
    return
  end
  root, path = vim.fs.normalize(root), vim.fs.normalize(path)
  if path ~= root and path:sub(1, #root + 1) ~= root .. "/" then
    path = vim.fs.joinpath(root, (path:gsub("^/", "")))
  end
  mains[client_id] = { root = root, path = path }
end

function M.is_reference(context)
  context = context
    or {
      bufnr = vim.api.nvim_get_current_buf(),
      cursor = vim.api.nvim_win_get_cursor(0),
      line = vim.api.nvim_get_current_line(),
    }
  if vim.bo[context.bufnr].filetype ~= "typst" then
    return false
  end
  local prefix = context.line:sub(1, context.cursor[2])
  if not prefix:match("@" .. label_chars .. "*$") then
    return false
  end
  local before = prefix:match("^(.*)@" .. label_chars .. "*$")
  if #(before:match("(\\*)$") or "") % 2 == 1 then
    return false
  end
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = context.bufnr,
    pos = { context.cursor[1] - 1, math.max(0, context.cursor[2] - 1) },
  })
  if ok and node then
    while node do
      local kind = node:type()
      if kind:find("comment") or kind:find("string") or kind:find("import") then
        return false
      end
      if kind == "content" then
        break
      end
      if kind == "code" or kind == "math" then
        return false
      end
      if kind == "ERROR" and before:match("^%s*#") then
        return false
      end
      node = node:parent()
    end
  else
    -- Without a parser, avoid the common comment/string/path contexts on this line.
    if before:find("//", 1, true) or before:find("/*", 1, true) or select(2, before:gsub('"', "")) % 2 == 1 then
      return false
    end
  end
  return true
end

function M.record(context, items)
  if not M.is_reference(context) then
    return items
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = context.bufnr, name = "tinymist" })) do
    local owned = {}
    for _, item in ipairs(items) do
      if item.client_id == client.id then
        owned[#owned + 1] = item
      end
    end
    -- Attached clients record before Blink transforms the reply, with the main
    -- captured at request time. Do not reassign a late reply after a main switch.
    if not client._typst_references_attached then
      save(client, owned, context.bufnr)
    end
  end
  return items
end

function M.seed(client, items, main_path)
  local root = client.root_dir or (client.config or {}).root_dir
  if main_path then
    M.set_main(client.id, root, main_path)
  end
  save(client, items, vim.api.nvim_get_current_buf())
end

function M.attach(client)
  if client._typst_references_attached then
    return
  end
  client._typst_references_attached = true
  local request = client.request
  client.request = function(self, method, params, callback, bufnr)
    if method ~= "textDocument/completion" or not callback or not params.position then
      return request(self, method, params, callback, bufnr)
    end
    bufnr = bufnr and bufnr ~= 0 and bufnr
      or (params.textDocument and vim.uri_to_bufnr(params.textDocument.uri))
      or vim.api.nvim_get_current_buf()
    local position = params.position
    local line = vim.api.nvim_buf_get_lines(bufnr, position.line, position.line + 1, false)[1] or ""
    local context = {
      bufnr = bufnr,
      line = line,
      cursor = {
        position.line + 1,
        vim.str_byteindex(line, self.offset_encoding or "utf-16", position.character, false),
      },
    }
    if not M.is_reference(context) then
      return request(self, method, params, callback, bufnr)
    end
    local root, main = identity(self, bufnr)
    return request(self, method, params, function(err, result, ...)
      if not err then
        local items = result and (result.items or result) or {}
        if vim.api.nvim_buf_is_valid(bufnr) then
          local current_root, current_main = identity(self, bufnr)
          if current_root == root and current_main == main then
            save(self, items, bufnr)
          end
        end
        -- Before the first successful compile Tinymist returns an empty complete
        -- list. Blink must retry as the reference prefix advances.
        if #items == 0 then
          result = { items = {}, isIncomplete = true }
        end
      end
      return callback(err, result, ...)
    end, bufnr)
  end
end

function M.warm(client)
  for bufnr in pairs(client.attached_buffers or {}) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local root, main = identity(client, bufnr)
      if root and vim.api.nvim_buf_get_name(bufnr) == main then
        local labels, key = load(root, main)
        client._typst_references_pending = client._typst_references_pending or {}
        if #labels == 0 and not client._typst_references_pending[key] then
          local anchor
          for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
            for column in line:gmatch("()@" .. label_chars .. "+") do
              if M.is_reference({ bufnr = bufnr, line = line, cursor = { row, column } }) then
                anchor = { row = row, column = column, line = line }
                break
              end
            end
            if not anchor then
              for column in line:gmatch("()<" .. label_chars .. "+>") do
                local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row - 1, column } })
                if ok and node and node:type() == "label" then
                  anchor = { row = row, column = column, line = line }
                  break
                end
              end
            end
            if anchor then
              break
            end
          end
          if anchor then
            client._typst_references_pending[key] = true
            local sent = client:request("textDocument/completion", {
              textDocument = { uri = vim.uri_from_bufnr(bufnr) },
              position = {
                line = anchor.row - 1,
                character = vim.str_utfindex(anchor.line, client.offset_encoding or "utf-16", anchor.column, false),
              },
              context = { triggerKind = 1 },
            }, function(err, result)
              client._typst_references_pending[key] = nil
              if not err and result and vim.api.nvim_buf_is_valid(bufnr) then
                local current_root, current_main = identity(client, bufnr)
                if current_root == root and current_main == main then
                  -- Query the compiled main at existing syntax, without editing it.
                  -- A declaration yields document labels; a reference also yields citations.
                  save(client, result.items or result, bufnr)
                  local cmp = package.loaded["blink.cmp"]
                  if
                    cmp
                    and vim.api.nvim_get_mode().mode == "i"
                    and client.attached_buffers[vim.api.nvim_get_current_buf()]
                    and M.is_reference()
                  then
                    cmp.show({ providers = { "lsp", "typst_references" } })
                  end
                end
              end
            end, bufnr)
            if not sent then
              client._typst_references_pending[key] = nil
            end
            return
          end
        end
      end
    end
  end
end

function M.new()
  return setmetatable({}, { __index = M })
end
function M:enabled()
  return M.is_reference()
end
function M:get_trigger_characters()
  return { "@", ":" }
end

function M:get_completions(context, callback)
  local items = {}
  if M.is_reference(context) then
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = context.bufnr, name = "tinymist" })) do
      local root, main = identity(client, context.bufnr)
      if root then
        local labels = load(root, main)
        local start = context.line:sub(1, context.cursor[2]):find("@" .. label_chars .. "*$")
        local tail = context.line:sub(context.cursor[2] + 1):match("^" .. label_chars .. "*")
        for _, label in ipairs(labels) do
          items[#items + 1] = {
            label = label,
            insertText = label,
            kind = 18,
            cursor_column = context.cursor[2],
            textEdit = {
              newText = label,
              range = {
                start = { line = context.cursor[1] - 1, character = start },
                ["end"] = { line = context.cursor[1] - 1, character = context.cursor[2] + #tail },
              },
            },
          }
        end
      end
    end
  end
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

return M
