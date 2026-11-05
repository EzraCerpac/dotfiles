local root = os.getenv("NVIM_TYPST_TEST_ROOT") or (arg and arg[1]) or "."
local original_vim = vim
local clients, listeners, callbacks = { [3] = 31184 }, {}, {}
vim = {
  uv = { os_get_passwd = function() return { uid = 501 } end, fs_chmod = function() return true end },
  fn = {
    expand = function() return "/private/fixture" end,
    mkdir = function() end,
    getpid = function() return 10744 end,
    serverstart = function(path) assert(not listeners[path]); listeners[path] = true; return path end,
    serverstop = function(path) assert(listeners[path]); listeners[path] = nil end,
  },
  api = {
    nvim_list_uis = function()
      local result = {}
      for channel in pairs(clients) do result[#result + 1] = { chan = channel } end
      return result
    end,
    nvim_get_chan_info = function(channel) return { client = { name = "nvim-tui", attributes = { pid = clients[channel] } } } end,
    nvim_create_autocmd = function(events, options)
      for _, event in ipairs(type(events) == "table" and events or { events }) do callbacks[event] = options.callback end
    end,
  },
  schedule = function(callback) callback() end,
}
local navigation = dofile(root .. "/dotfiles/.config/nvim/lua/config/modules/rex-navigation.lua")
navigation.start()
assert(listeners["/private/fixture/501-10744"])
assert(listeners["/private/fixture/501-31184"])
assert(not listeners["/private/fixture/501-1"])
clients[4] = 32000
callbacks.UIEnter()
assert(listeners["/private/fixture/501-32000"])
clients[3] = nil
callbacks.UILeave()
assert(not listeners["/private/fixture/501-31184"])
assert(listeners["/private/fixture/501-10744"])
navigation.start() -- Reinitialization must not replace listener ownership.
callbacks.VimLeavePre()
assert(next(listeners) == nil)
vim = original_vim
print("Neovim UI attachment lifecycle tests passed")
