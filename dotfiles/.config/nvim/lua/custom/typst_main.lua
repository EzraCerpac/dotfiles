local M = {}
local clients = {}
local selections = {}

local function is_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file"
end

-- Only the two author trees change the thesis view; helpers keep the last view.
function M.manuscript(path)
  path = vim.fs.normalize(path)
  local directory = path:match("^(.-/manuscript)/")
  if directory and is_file(directory .. "/main.typ") and is_file(directory .. "/draft.typ") then
    return directory
  end
end

function M.resolve(path, root)
  if type(root) ~= "string" or root == "" or path == "" then
    return
  end
  path, root = vim.fs.normalize(path), vim.fs.normalize(root)
  if path:sub(1, #root + 1) ~= root .. "/" then
    return
  end
  local manuscript = M.manuscript(path)
  if manuscript then
    local view = path:sub(#manuscript + 2):match("^(main)/")
      or path:sub(#manuscript + 2):match("^(draft)/")
      or path:sub(#manuscript + 2):match("^(main)%.typ$")
      or path:sub(#manuscript + 2):match("^(draft)%.typ$")
    return view and manuscript .. "/" .. view .. ".typ"
  end
  local directory = vim.fs.dirname(path)
  while directory do
    local main = vim.fs.joinpath(directory, "main.typ")
    if is_file(main) then
      return main
    end
    if directory == root then
      return
    end
    directory = vim.fs.dirname(directory)
  end
end

function M.preview_path(path)
  local manuscript = M.manuscript(path)
  if manuscript and is_file(manuscript .. "/preview.typ") then
    if not selections[manuscript] then
      local selected = M.resolve(path, vim.fs.dirname(manuscript))
      selections[manuscript] = selected and vim.fs.basename(selected):gsub("%.typ$", "") or "main"
    end
    return manuscript .. "/preview.typ"
  end
  return path
end

function M.preview_include(path)
  local manuscript = M.manuscript(path)
  if manuscript and path == manuscript .. "/preview.typ" then
    return '#include "' .. (selections[manuscript] or "main") .. '.typ"\n'
  end
end

local function select(client, path)
  client._typst_main_selected = true
  client._typst_main_path = path
  if path then
    require("custom.typst_references").set_main(client.id, client.root_dir, path)
    local manuscript = M.manuscript(path)
    local view = manuscript and path:sub(#manuscript + 2):match("^(%a+)%.typ$")
    if view == "main" or view == "draft" then
      selections[manuscript] = view
      M.refresh_preview(manuscript .. "/preview.typ")
    end
  end
end

function M.accept_compile_status(client, path)
  local expected = client._typst_main_path
  if not expected then
    return true
  end
  path = vim.fs.normalize(path)
  local root = vim.fs.normalize(client.root_dir)
  if path:sub(1, #root + 1) ~= root .. "/" then
    path = vim.fs.joinpath(root, (path:gsub("^/", "")))
  end
  return path == expected
end

function M.follow(client, bufnr)
  if client._typst_main_manual then
    return
  end
  if client.settings and client.settings.typstExtraArgs and #client.settings.typstExtraArgs > 0 then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local main = M.resolve(path, client.root_dir)
  if not main or main == client._typst_main_path then
    return
  end
  -- Preserve the conventional one-time pin outside the thesis author trees.
  if client._typst_main_selected and not M.manuscript(path) then
    return
  end
  select(client, main)
  client._typst_main_auto_request = true
  client:exec_cmd(
    { title = "Follow manuscript pane", command = "tinymist.pinMain", arguments = { main } },
    { bufnr = bufnr }
  )
  client._typst_main_auto_request = nil
end

local function setup()
  local generation = 0
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = vim.api.nvim_create_augroup("TypstFocusedMain", { clear = true }),
    callback = function()
      generation = generation + 1
      local pending = generation
      vim.defer_fn(function()
        if pending ~= generation then
          return
        end
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.bo[bufnr].filetype ~= "typst" then
          return
        end
        for _, client in pairs(clients) do
          if client.attached_buffers and client.attached_buffers[bufnr] then
            M.follow(client, bufnr)
          end
        end
      end, 30)
    end,
  })
end

function M.attach(client, bufnr)
  if not client._typst_main_observed then
    client._typst_main_observed = true
    local request = client.request
    client.request = function(self, method, params, ...)
      if method == "workspace/executeCommand" and type(params) == "table" and params.command == "tinymist.pinMain" then
        if not self._typst_main_auto_request then
          self._typst_main_manual = true
          local path = params.arguments and params.arguments[1]
          select(self, type(path) == "string" and vim.fs.normalize(path) or nil)
        end
      end
      return request(self, method, params, ...)
    end
  end
  if not next(clients) then
    setup()
  end
  clients[client.id] = client
  -- Background attachment must not replace the focused pane's selection.
  if not client._typst_main_selected or vim.api.nvim_get_current_buf() == bufnr then
    M.follow(client, bufnr)
  end
end

-- Keep one preview compiler and browser tab while its include follows the pane.
-- The overlay uses the plugin's existing updateMemoryFiles control protocol.
function M.refresh_preview(path)
  local servers = package.loaded["typst-preview.servers"]
  if not servers then
    return
  end
  local content = M.preview_include(path)
  if not content then
    return
  end
  for _, server in ipairs(servers.get_all()) do
    if server.path == path and server._thesis_include ~= content then
      if server.suppress then
        if not server._thesis_refresh_pending then
          server._thesis_refresh_pending = true
          vim.defer_fn(function()
            server._thesis_refresh_pending = nil
            M.refresh_preview(path)
          end, 120)
        end
      else
        servers.update_memory_file(server, path, content)
      end
    end
  end
end

function M.setup_preview(opts)
  local previous_main = opts.get_main_file or function(path)
    return path
  end
  opts.get_main_file = function(path)
    local preview = M.preview_path(path)
    return preview ~= path and preview or previous_main(path)
  end
  local servers = require("typst-preview.servers")
  if servers._thesis_follow then
    return
  end
  servers._thesis_follow = true
  local update = servers.update_memory_file
  servers.update_memory_file = function(server, path, content)
    if path == server.path then
      content = M.preview_include(path) or content
      if not server.suppress then
        server._thesis_include = content
      end
    end
    return update(server, path, content)
  end
  local init = servers.init
  servers.init = function(path, mode, callback)
    return init(path, mode, function(server)
      M.refresh_preview(path)
      callback(server)
    end)
  end
end

return M
