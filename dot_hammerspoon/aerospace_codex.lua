local M = {}
local tasks = {}

function M.route(hs, window_id)
    local id = tonumber(window_id)
    if not id or id <= 0 or id % 1 ~= 0 then return false end
    local window = hs.window.get(id)
    if not window then return false end
    local app = window:application()
    if not app or app:bundleID() ~= "com.openai.codex" then return false end
    local element = hs.axuielement.windowElement(window)
    -- Codex's popup shares the main window's title and AXStandardWindow role,
    -- but has no close button. Missing metadata must never trigger a move.
    if not element or not element:attributeValue("AXCloseButton") then return false end
    local task
    task = hs.task.new("/opt/homebrew/bin/aerospace", function()
        tasks[task] = nil
    end, {"move-node-to-workspace", "2", "--window-id", tostring(id)})
    if not task then return false end
    tasks[task] = true
    if not task:start() then tasks[task] = nil; return false end
    return true
end

function M.start(hs)
    hs.urlevent.bind("aerospace-route-codex", function(_, params)
        M.route(hs, params.window_id)
    end)
end

return M
