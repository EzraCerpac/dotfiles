local M = {}

local TOPOLOGY_SETTING = "aerospace-workspaces-last-external-topology"
local STARTUP_SETTING = "aerospace-workspaces-last-aerospace-pid"
local BUILTIN_UUIDS = {
    ["37D8832A-2D66-02CA-B9F7-8F30A301B230"] = true,
}
local MONITOR_FORMAT = "%{monitor-id} %{monitor-appkit-nsscreen-screens-id} %{monitor-name}"

local function is_builtin(screen)
    local uuid = screen:getUUID()
    if uuid and BUILTIN_UUIDS[string.upper(uuid)] then
        return true
    end

    local name = screen:name()
    name = name and string.lower(name) or ""
    return name:match("^built%-in") ~= nil or name == "color lcd"
end

local function external_screens(hs)
    local screens = hs.screen.allScreens()
    local externals = {}
    local seen = {}

    for index, screen in ipairs(screens) do
        local uuid = screen:getUUID()
        if not uuid then
            return nil, "screen UUID unavailable"
        end
        if not is_builtin(screen) then
            if seen[uuid] then
                return nil, "duplicate external screen UUID"
            end
            seen[uuid] = true
            local frame = screen:fullFrame()
            if type(frame.x) ~= "number" then
                return nil, "screen frame unavailable"
            end
            table.insert(externals, {
                uuid = uuid,
                index = index,
                x = frame.x,
                screen = screen,
            })
        end
    end

    return externals
end

local function topology_id(externals)
    local uuids = {}
    for _, screen in ipairs(externals) do
        table.insert(uuids, screen.uuid)
    end
    table.sort(uuids)
    return table.concat(uuids, ",")
end

local function has_added_external(previous, current)
    if type(previous) ~= "string" then
        return false
    end
    local old = {}
    for uuid in previous:gmatch("[^,]+") do
        old[uuid] = true
    end
    for _, screen in ipairs(current) do
        if not old[screen.uuid] then
            return true
        end
    end
    return false
end

local function find_aerospace(hs, home)
    local candidates = {
        home .. "/.local/bin/aerospace",
        "/opt/homebrew/bin/aerospace",
        "/usr/local/bin/aerospace",
    }

    for _, path in ipairs(candidates) do
        local attributes = hs.fs and hs.fs.attributes and hs.fs.attributes(path)
        if attributes and attributes.mode == "file" then
            return path
        end
    end
    return nil
end

function M.new(options)
    options = options or {}
    local hs = options.hs or _G.hs
    assert(hs, "Hammerspoon API is required")

    local home = options.home or os.getenv("HOME") or ""
    local aerospace = options.aerospacePath or find_aerospace(hs, home)
    local watcher
    local topology_timer
    local startup_timer
    local last_observed_topology
    local pending_connection = false
    local running = false
    local pending_request
    local controller = {}

    local function setting(key)
        return hs.settings.get(key)
    end

    local function save_setting(key, value)
        hs.settings.set(key, value)
    end

    local function log(message)
        if hs.printf then
            hs.printf("AeroSpace workspace defaults: %s", message)
        end
    end

    local function active_aerospace_pid()
        if options.aerospacePid then
            return options.aerospacePid()
        end
        local app = hs.application.get("AeroSpace")
        if app then
            return tostring(app:pid())
        end
        return nil
    end

    local function run_cli(arguments, callback)
        if not aerospace then
            callback(false, "", "AeroSpace CLI not found")
            return
        end

        local task = hs.task.new(aerospace, function(exit_code, stdout, stderr)
            callback(exit_code == 0, stdout or "", stderr or "")
        end, nil, arguments)
        if not task or not task:start() then
            callback(false, "", "could not start AeroSpace CLI")
        end
    end

    local function decode_records(output)
        local ok, records = pcall(hs.json.decode, output)
        if not ok or type(records) ~= "table" then
            return nil
        end
        return records
    end

    local function rightmost_external(externals)
        local rightmost_x = -math.huge
        local rightmost
        local ties = 0
        for _, screen in ipairs(externals) do
            if screen.x > rightmost_x then
                rightmost_x = screen.x
                rightmost = screen
                ties = 1
            elseif screen.x == rightmost_x then
                ties = ties + 1
            end
        end
        if ties ~= 1 then
            return nil
        end
        return rightmost
    end

    local function apply_defaults(callback)
        if not aerospace then
            callback("unavailable")
            return
        end
        local externals = external_screens(hs)
        if not externals then
            callback("unavailable")
            return
        end
        if #externals == 0 then
            callback("no-external")
            return
        end

        local rightmost = rightmost_external(externals)
        if not rightmost then
            log("rightmost external screen is ambiguous; skipped")
            callback("unavailable")
            return
        end

        local screen_count = 0
        for _, screen in ipairs(hs.screen.allScreens()) do
            if screen:getUUID() == rightmost.uuid then
                screen_count = screen_count + 1
            end
        end
        if screen_count ~= 1 then
            callback("unavailable")
            return
        end

        run_cli({ "list-monitors", "--json", "--format", MONITOR_FORMAT }, function(ok, output, err)
            if not ok then
                log("could not list monitors: " .. tostring(err))
                callback("unavailable")
                return
            end
            local records = decode_records(output)
            if not records then
                log("monitor list was not valid JSON")
                callback("unavailable")
                return
            end
            local monitor_id
            local matches = 0
            for _, record in ipairs(records) do
                if tonumber(record["monitor-appkit-nsscreen-screens-id"]) == rightmost.index then
                    matches = matches + 1
                    monitor_id = tonumber(record["monitor-id"])
                end
            end
            if matches ~= 1 or not monitor_id then
                log("could not map external screen to one AeroSpace monitor")
                callback("unavailable")
                return
            end

            run_cli({ "list-workspaces", "--focused", "--json", "--format", "%{workspace}" }, function(focused_ok, focused_output, focused_err)
                if not focused_ok then
                    log("could not read focused workspace: " .. tostring(focused_err))
                    callback("unavailable")
                    return
                end
                local workspaces = decode_records(focused_output)
                local focused = workspaces and workspaces[1] and workspaces[1].workspace
                if type(focused) ~= "string" or focused == "" then
                    callback("unavailable")
                    return
                end

                local function move_defaults(focused_window)
                    local current_externals = external_screens(hs)
                    local current_rightmost = current_externals and rightmost_external(current_externals)
                    if not current_rightmost
                        or current_rightmost.uuid ~= rightmost.uuid
                        or current_rightmost.index ~= rightmost.index then
                        log("screen topology changed during mapping; skipped")
                        callback("unavailable")
                        return
                    end

                    local placements_ok = true
                    local function restore_workspace()
                        run_cli({ "workspace", focused }, function(restored, _, restore_err)
                            if not restored then
                                log("could not restore focused workspace: " .. tostring(restore_err))
                            end
                            callback(placements_ok and restored and "applied" or "unavailable")
                        end)
                    end

                    local function restore_focus()
                        if not focused_window then
                            restore_workspace()
                            return
                        end
                        run_cli({ "focus", "--window-id", tostring(focused_window) }, function(restored)
                            if restored then
                                callback(placements_ok and "applied" or "unavailable")
                            else
                                restore_workspace()
                            end
                        end)
                    end

                    run_cli({ "move-workspace-to-monitor", "--workspace", "9", "--", tostring(monitor_id) }, function(ops_ok, _, ops_err)
                        placements_ok = placements_ok and ops_ok
                        if not ops_ok then
                            log("could not place workspace 9: " .. tostring(ops_err))
                        end
                        run_cli({ "move-workspace-to-monitor", "--workspace", "M", "--", tostring(monitor_id) }, function(media_ok, _, media_err)
                            placements_ok = placements_ok and media_ok
                            if not media_ok then
                                log("could not place workspace M: " .. tostring(media_err))
                            end
                            restore_focus()
                        end)
                    end)
                end

                run_cli({ "list-windows", "--focused", "--json", "--format", "%{window-id}" }, function(window_ok, window_output)
                    local window_id
                    if window_ok then
                        local windows = decode_records(window_output)
                        local value = windows and windows[1] and windows[1]["window-id"]
                        if type(value) == "string" or type(value) == "number" then
                            window_id = tostring(value)
                        end
                    end
                    move_defaults(window_id)
                end)
            end)
        end)
    end

    local function start_request(reason, pid)
        if running then
            if reason == "startup" and pid then
                if not pending_request then
                    pending_request = { reason = reason, pid = pid }
                else
                    pending_request.pid = pid
                end
            elseif not pending_request or reason == "connect" then
                pending_request = { reason = reason, pid = pid }
            end
            return
        end
        if not active_aerospace_pid() then
            return
        end
        if reason == "startup" and pid and tostring(setting(STARTUP_SETTING)) == tostring(pid) then
            return
        end

        running = true
        apply_defaults(function(result)
            local pending = pending_request
            if result == "applied" or result == "no-external" then
                if pid then
                    save_setting(STARTUP_SETTING, tostring(pid))
                end
                if pending and pending.pid then
                    save_setting(STARTUP_SETTING, tostring(pending.pid))
                end
            end
            running = false
            pending_request = nil
            if pending then
                start_request(pending.reason, pending.pid)
            end
        end)
    end

    local function request_startup_defaults()
        local pid = active_aerospace_pid()
        if not pid then
            return
        end
        if tostring(setting(STARTUP_SETTING)) == tostring(pid) then
            return
        end
        start_request("startup", tostring(pid))
    end

    local function current_topology()
        local screens, err = external_screens(hs)
        if not screens then
            log(err)
            return nil
        end
        return screens, topology_id(screens)
    end

    local function observe_topology()
        topology_timer = nil
        local screens, current = current_topology()
        if not screens then
            return
        end
        local added = pending_connection or has_added_external(last_observed_topology, screens)
        pending_connection = false
        last_observed_topology = current
        save_setting(TOPOLOGY_SETTING, current)
        if added then
            start_request("connect")
        end
    end

    local function schedule_topology_check()
        if topology_timer then
            topology_timer:stop()
        end
        topology_timer = hs.timer.doAfter(0.5, observe_topology)
    end

    local function schedule_startup_check()
        if startup_timer then
            startup_timer:stop()
        end
        startup_timer = hs.timer.doAfter(0.5, function()
            startup_timer = nil
            request_startup_defaults()
        end)
    end

    function controller:start()
        hs.urlevent.bind("aerospace-default-workspaces", function()
            schedule_startup_check()
        end)

        watcher = hs.screen.watcher.new(schedule_topology_check)
        watcher:start()

        local screens, current = current_topology()
        if screens then
            local previous = setting(TOPOLOGY_SETTING)
            local added = has_added_external(previous, screens)
            last_observed_topology = current
            save_setting(TOPOLOGY_SETTING, current)
            if added then
                pending_connection = true
                schedule_topology_check()
            end
        end

        schedule_startup_check()
        return controller
    end

    controller._scheduleTopologyCheck = schedule_topology_check
    controller._requestStartupDefaults = request_startup_defaults
    return controller
end

return M
