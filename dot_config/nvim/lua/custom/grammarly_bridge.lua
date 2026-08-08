local M = {}

local bridge_dir = vim.fn.expand("~/.local/share/grammarly-bridge")
local bridge_name = "grammarly-bridge"
local compile_state = {}
local active
local process
local owns_process = false
local bridge_url

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Grammarly Bridge" })
end

local function lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function copy(value)
  return vim.deepcopy(value)
end

local function join(value)
  return table.concat(value, "\n")
end

local function system(command, options)
  local result = vim.system(command, vim.tbl_extend("force", { text = true }, options or {})):wait()
  return result.code == 0, vim.trim(result.stdout or ""), vim.trim(result.stderr or "")
end

local function route()
  local ok, stdout = system({ "portless", "get", bridge_name, "--no-worktree" })
  if ok and stdout ~= "" then
    return stdout
  end
end

local function healthy(url)
  if not url then
    return false
  end
  local ok, stdout = system({ "curl", "--fail", "--silent", "--show-error", url .. "/health" })
  return ok and stdout:find('"service":"grammarly%-bridge"') ~= nil
end

local function stop_process()
  if owns_process and process then
    pcall(process.kill, process, 15)
  end
  process = nil
  owns_process = false
  bridge_url = nil
end

local function start_process()
  local existing = route()
  if healthy(existing) then
    bridge_url = existing
    return existing
  end

  local command = {
    "portless",
    bridge_name,
    "--",
    "deno",
    "run",
    "--quiet",
    "--allow-env=PORT",
    "--allow-net=127.0.0.1",
    "--allow-read=" .. bridge_dir,
    bridge_dir .. "/server.ts",
  }
  process = vim.system(command, { cwd = bridge_dir, text = true }, function(result)
    if owns_process and active and result.code ~= 0 then
      vim.schedule(function()
        notify("Local bridge stopped unexpectedly: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
      end)
    end
  end)
  owns_process = true

  local ready = vim.wait(5000, function()
    bridge_url = route()
    return healthy(bridge_url)
  end, 100)
  if not ready then
    stop_process()
    return nil, "local bridge did not become healthy within 5 seconds"
  end
  return bridge_url
end

local function random_token()
  local ok, stdout, stderr = system({ "openssl", "rand", "-hex", "32" })
  if not ok or not stdout:match("^[a-f0-9]+$") then
    return nil, stderr ~= "" and stderr or "openssl could not create a session token"
  end
  return stdout
end

local function draft_request(method, token, text)
  local command = {
    "curl",
    "--fail",
    "--silent",
    "--show-error",
    "--request",
    method,
    "--header",
    "Authorization: Bearer " .. token,
  }
  local options = {}
  if text then
    vim.list_extend(command, { "--data-binary", "@-" })
    options.stdin = text
  end
  table.insert(command, bridge_url .. "/api/draft")
  return system(command, options)
end

local function start_ghosttext()
  if vim.fn.exists("*ghosttext#status") == 1 and vim.fn["ghosttext#status"]() == "running" then
    return true
  end
  return pcall(vim.cmd, "GhostStart")
end

local function tinymist_client(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == "tinymist" then
      return client
    end
  end
end

local function tinymist_context(bufnr)
  local client = tinymist_client(bufnr)
  local state = client and compile_state[client.id]
  if not client or not state or not state.path or state.path == "" then
    return nil
  end
  return client, state
end

local function serialize_node(node, bufnr)
  if node:type() == "text" then
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

local function fingerprint(content)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = "typst"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
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

local function error_set(client)
  local result = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and tinymist_client(bufnr) == client then
      for _, diagnostic in ipairs(vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })) do
        local key = table.concat(
          { tostring(bufnr), diagnostic.source or "", tostring(diagnostic.code or ""), diagnostic.message },
          "\0"
        )
        result[key] = true
      end
    end
  end
  return result
end

local function has_new_errors(before, after)
  for key in pairs(after) do
    if not before[key] then
      return true
    end
  end
  return false
end

local function is_bridge_buffer_name(name, url)
  return vim.startswith(name, url) or vim.fs.basename(name) == bridge_name .. ".localhost"
end

local function is_ghost_buffer(bufnr)
  return active and bridge_url and is_bridge_buffer_name(vim.api.nvim_buf_get_name(bufnr), bridge_url)
end

local function capture_proposal(bufnr)
  if not active or not vim.api.nvim_buf_is_valid(bufnr) or not is_ghost_buffer(bufnr) then
    return
  end
  active.ghost_bufnr = bufnr
  local proposal = lines(bufnr)
  if active.proposal and not vim.deep_equal(active.proposal, proposal) then
    active.reviewed = false
  end
  active.proposal = proposal
  if vim.bo[bufnr].filetype ~= "typst" then
    vim.bo[bufnr].filetype = "typst"
  end
end

local function close_ghost_buffer(draft)
  local bufnr = draft and draft.ghost_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end

local function clear_active(close_buffer)
  local draft = active
  active = nil
  if draft and bridge_url then
    draft_request("DELETE", draft.token)
  end
  if close_buffer then
    close_ghost_buffer(draft)
  end
end

function M.bridge()
  if active then
    notify("A draft is already active. Apply or discard it first.", vim.log.levels.WARN)
    return
  end

  local source_bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[source_bufnr].filetype ~= "typst" then
    notify("Current buffer is not Typst.", vim.log.levels.ERROR)
    return
  end
  if not tinymist_context(source_bufnr) then
    notify(
      "Tinymist has no compiled main-file context. Start or pin the correct project main file.",
      vim.log.levels.ERROR
    )
    return
  end

  local original = lines(source_bufnr)
  local original_fingerprint, parse_error = fingerprint(original)
  if not original_fingerprint then
    notify(parse_error, vim.log.levels.ERROR)
    return
  end

  local url, start_error = start_process()
  if not url then
    notify(start_error, vim.log.levels.ERROR)
    return
  end
  local token, token_error = random_token()
  if not token then
    notify(token_error, vim.log.levels.ERROR)
    return
  end
  local seeded, _, seed_error = draft_request("PUT", token, join(original))
  if not seeded then
    notify("Could not seed local draft: " .. seed_error, vim.log.levels.ERROR)
    return
  end

  active = {
    token = token,
    source_bufnr = source_bufnr,
    source_changedtick = vim.api.nvim_buf_get_changedtick(source_bufnr),
    original = copy(original),
    original_fingerprint = original_fingerprint,
    proposal = copy(original),
    reviewed = false,
  }

  local ok, ghost_error = start_ghosttext()
  if not ok then
    clear_active(false)
    notify("Could not start GhostText: " .. tostring(ghost_error), vim.log.levels.ERROR)
    return
  end

  local browser = vim.g.grammarly_bridge_browser or "Helium"
  vim.system({ "open", "-a", browser, url .. "/#" .. token }, { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        notify("Could not open " .. browser .. ": " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
      end)
    end
  end)
  notify("Draft opened in " .. browser .. ". Activate GhostText with Command-Shift-K.")
end

function M.review()
  if not active then
    notify("No active draft.", vim.log.levels.WARN)
    return
  end
  if not active.ghost_bufnr then
    notify("GhostText is not connected to the bridge textarea yet.", vim.log.levels.WARN)
    return
  end
  capture_proposal(active.ghost_bufnr)
  local diff = vim.diff(join(active.original), join(active.proposal), {
    result_type = "unified",
    ctxlen = 4,
  })
  local review = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(
    review,
    "[Grammarly Review " .. active.token:sub(1, 8) .. " " .. tostring(vim.uv.hrtime()) .. "]"
  )
  vim.api.nvim_buf_set_lines(review, 0, -1, false, vim.split(diff ~= "" and diff or "No changes.", "\n"))
  vim.bo[review].syntax = "diff"
  vim.bo[review].bufhidden = "wipe"
  vim.bo[review].modifiable = false
  vim.cmd("botright new")
  vim.api.nvim_win_set_buf(0, review)
  active.reviewed = true
end

local function rollback(bufnr, draft, message)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent undo")
  end)
  draft.source_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  notify(message .. " Original buffer restored; proposal retained.", vim.log.levels.ERROR)
end

function M.apply()
  local draft = active
  if not draft then
    notify("No active draft.", vim.log.levels.WARN)
    return
  end
  if not draft.reviewed then
    notify("Run :GrammarlyReview before applying.", vim.log.levels.WARN)
    return
  end
  if draft.ghost_bufnr then
    capture_proposal(draft.ghost_bufnr)
  end

  local bufnr = draft.source_bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    notify("Source buffer no longer exists.", vim.log.levels.ERROR)
    return
  end
  if vim.api.nvim_buf_get_changedtick(bufnr) ~= draft.source_changedtick then
    notify("Source changed since bridge start. Discard and restart; automatic merge is disabled.", vim.log.levels.ERROR)
    return
  end
  local client, context = tinymist_context(bufnr)
  if not client then
    notify("Tinymist is no longer attached. Start or pin the project main file.", vim.log.levels.ERROR)
    return
  end

  local proposal_fingerprint, parse_error = fingerprint(draft.proposal)
  if not proposal_fingerprint then
    notify(parse_error, vim.log.levels.ERROR)
    return
  end
  if proposal_fingerprint ~= draft.original_fingerprint then
    notify("Proposal changes protected Typst syntax, math, labels, citations, or code.", vim.log.levels.ERROR)
    return
  end

  local before_errors = error_set(client)
  local before_generation = context.generation
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, draft.proposal)

  local diagnostics_ready = vim.wait(5000, function()
    local current = compile_state[client.id]
    return current and current.generation > before_generation and current.status ~= "compiling"
  end, 50)
  if not diagnostics_ready then
    rollback(bufnr, draft, "Tinymist did not return fresh diagnostics within 5 seconds.")
    return
  end
  if has_new_errors(before_errors, error_set(client)) then
    rollback(bufnr, draft, "Tinymist reported a new error.")
    return
  end

  clear_active(true)
  notify("Grammarly proposal applied as one unsaved, undoable edit.")
end

function M.discard()
  if not active then
    notify("No active draft.", vim.log.levels.WARN)
    return
  end
  clear_active(true)
  notify("Draft discarded. Source unchanged.")
end

function M.stop()
  if active then
    clear_active(true)
  end
  stop_process()
  notify("Owned local bridge stopped.")
end

function M.setup()
  if M._setup then
    return
  end
  M._setup = true

  vim.api.nvim_create_user_command("GrammarlyBridge", M.bridge, {})
  vim.api.nvim_create_user_command("GrammarlyReview", M.review, {})
  vim.api.nvim_create_user_command("GrammarlyApply", M.apply, {})
  vim.api.nvim_create_user_command("GrammarlyDiscard", M.discard, {})
  vim.api.nvim_create_user_command("GrammarlyBridgeStop", M.stop, {})

  local group = vim.api.nvim_create_augroup("grammarly_bridge", { clear = true })
  local previous_compile_handler = vim.lsp.handlers["tinymist/compileStatus"]
  vim.lsp.handlers["tinymist/compileStatus"] = function(err, result, ctx, config)
    if not err and result then
      local previous = compile_state[ctx.client_id]
      compile_state[ctx.client_id] = {
        generation = (previous and previous.generation or 0) + 1,
        path = result.path,
        status = result.status,
      }
    end
    if previous_compile_handler then
      return previous_compile_handler(err, result, ctx, config)
    end
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "TextChangedP", "BufWipeout" }, {
    group = group,
    callback = function(event)
      capture_proposal(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if active then
        clear_active(false)
      end
      stop_process()
    end,
  })
end

M._fingerprint = fingerprint
M._is_bridge_buffer_name = is_bridge_buffer_name

return M
