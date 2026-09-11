local route = dofile("dot_hammerspoon/aerospace_codex.lua")
local moves = {}
local windows = {
    [151] = {bundle = "com.openai.codex", close = {}},
    [373] = {bundle = "com.openai.codex"},
    [400] = {bundle = "other.app", close = {}},
}
local hs = {
    window = {get = function(id)
        local w = windows[id]
        if not w then return nil end
        return {
            application = function() return {bundleID = function() return w.bundle end} end,
            close = w.close,
        }
    end},
    axuielement = {windowElement = function(w)
        return {attributeValue = function(_, key)
            assert(key == "AXCloseButton")
            return w.close
        end}
    end},
    task = {new = function(path, _, args)
        assert(path == "/opt/homebrew/bin/aerospace")
        return {start = function() moves[#moves + 1] = args; return true end}
    end},
}
assert(route.route(hs, "151"))
for _, id in ipairs({"373", "400", "999", "bad", "0", "1.5"}) do
    assert(not route.route(hs, id))
end
assert(#moves == 1)
assert(table.concat(moves[1], " ") == "move-node-to-workspace 2 --window-id 151")
print("PASS: main window routed; popup, other app, missing and invalid IDs ignored")
