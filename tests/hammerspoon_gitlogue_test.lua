local root = os.getenv("NVIM_TYPST_TEST_ROOT") or (arg and arg[1]) or "."
local file = assert(io.open(root .. "/dotfiles/.hammerspoon/init.lua"))
local source = file:read("*a")
file:close()
source = assert(source:match("^(.-)local function handle_gitlogue_idle%(%).*"))
local assertions = [[
local function target()
    gitlogue_target = {window_id = 42, pid = 123, session = "session:test", block = "block:test"}
end
target()
stop_gitlogue()
assert(close_count == 1 and kill_count == 1, "owned session was not cleaned up")
closed = false; close_count = 0; kill_count = 0; extra_block = true
target()
stop_gitlogue()
assert(close_count == 0 and kill_count == 0, "session with extra work was touched")
extra_block = false; duplicate_window = true
target()
stop_gitlogue()
assert(close_count == 0 and kill_count == 0, "ambiguous windows were touched")
duplicate_window = false; wrong_pid = true
target()
stop_gitlogue(8)
assert(close_count == 0 and kill_count == 0, "different app process was touched")
print("Gitlogue identity tests passed")
]]
close_count, kill_count = 0, 0
closed, extra_block, duplicate_window, wrong_pid = false, false, false, false
local app = {}
local window = {}
function app:bundleID() return "com.superlogical.rex" end
function app:pid() return wrong_pid and 124 or 123 end
function app:allWindows()
    if closed then return {} end
    return duplicate_window and {window, window} or {window}
end
function window:application() return app end
function window:title() return "gitlogue - gitlogue-screensaver" end
function window:close() close_count = close_count + 1; closed = true; return true end
hs = {
    window = { get = function(id) return id == 42 and not closed and window or nil end },
    application = { get = function() return app end },
    execute = function(command)
        if command:match(" session inspect ") then return "session-json", true, "exit", 0 end
        if command:match(" kill ") then kill_count = kill_count + 1; return "", true, "exit", 0 end
        error("unexpected command")
    end,
    json = { decode = function()
        local blocks = {{block_id = "block:test"}}
        if extra_block then blocks[#blocks + 1] = {block_id = "block:user"} end
        return {windows = {{layers = {{blocks = blocks}}}}}
    end },
    timer = { doAfter = function() error("unexpected timer") end },
}
assert(load(source .. assertions, "gitlogue identity"))()
