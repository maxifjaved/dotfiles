-- ============================================================================
-- Robust Window Cycler with State Management (FIXED F18 binding)
-- ============================================================================

-- Path to yabai
local YABAI_PATH = "/usr/local/bin/yabai"

-- Notification to confirm the script is active
hs.alert.show("Window Cycler Loaded!")

-- ============================================================================
-- FIXED: Proper F18 key binding
-- F18 is a key, not a modifier, so we need to handle it differently
-- ============================================================================
local hyperMode = hs.hotkey.modal.new()
local hyperPressed = false

-- When F18 is pressed, enter "hyper mode"
hs.hotkey.bind({}, "f18", function()
    hyperPressed = true
    hyperMode:enter()
end, function()
    hyperPressed = false
    hyperMode:exit()
end)

-- ============================================================================
-- State Management: Store last focused window index for each app
-- ============================================================================
local windowCycleState = {}

-- ============================================================================
-- Helper: Sort windows consistently (by space, then by window ID)
-- ============================================================================
local function sortWindows(windows)
    table.sort(windows, function(a, b)
        if a.space ~= b.space then
            return a.space < b.space
        end
        if a.display ~= b.display then
            return a.display < b.display
        end
        return a.id < b.id
    end)
    return windows
end

-- ============================================================================
-- Helper: Get or initialize state for an app
-- ============================================================================
local function getAppState(appName)
    if not windowCycleState[appName] then
        windowCycleState[appName] = {
            lastIndex = 0,
            windowList = {},
            lastUpdate = 0
        }
    end
    return windowCycleState[appName]
end

-- ============================================================================
-- Main Cycle Function: Can be reused for any app
-- ============================================================================
local function cycleAppWindows(appName)
    hs.task.new(YABAI_PATH, function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
            print("Error: yabai query failed - " .. (stdErr or ""))
            hs.alert.show("yabai error!")
            return
        end

        local ok, allWindows = pcall(hs.json.decode, stdOut)
        if not ok then
            print("Error: Could not decode JSON from yabai")
            return
        end

        local appWindows = {}
        for _, windowData in ipairs(allWindows) do
            if windowData.app == appName then
                table.insert(appWindows, windowData)
            end
        end

        if #appWindows == 0 then
            print(string.format("No %s windows found. Attempting to launch...", appName))
            hs.alert.show(string.format("Launching %s...", appName))
            hs.application.launchOrFocus(appName)
            local state = getAppState(appName)
            state.lastIndex = 0
            state.windowList = {}
            return
        end

        appWindows = sortWindows(appWindows)

        local state = getAppState(appName)
        state.windowList = appWindows
        state.lastUpdate = os.time()

        local currentFocusedID = nil
        for _, win in ipairs(appWindows) do
            if win["has-focus"] then
                currentFocusedID = win.id
                for i, w in ipairs(appWindows) do
                    if w.id == currentFocusedID then
                        state.lastIndex = i
                        break
                    end
                end
                break
            end
        end

        local nextIndex = state.lastIndex + 1
        if nextIndex > #appWindows then
            nextIndex = 1
        end

        state.lastIndex = nextIndex

        local windowToFocus = appWindows[nextIndex]

        local title = windowToFocus.title
        if title and #title > 30 then
            title = string.sub(title, 1, 27) .. "..."
        end
        hs.alert.show(string.format("%s: Window %d/%d - %s",
            appName, nextIndex, #appWindows, title or "Untitled"))

        print(string.format("Focusing %s window #%d (ID: %d, Space: %d)",
            appName, nextIndex, windowToFocus.id, windowToFocus.space))

        hs.task.new(YABAI_PATH, function(exitCode, stdOut, stdErr)
            if exitCode ~= 0 then
                print("Error focusing window: " .. (stdErr or ""))
                hs.task.new(YABAI_PATH, nil, {
                    "-m", "space", "--focus", tostring(windowToFocus.space)
                }):start()
                hs.timer.doAfter(0.2, function()
                    hs.task.new(YABAI_PATH, nil, {
                        "-m", "window", "--focus", tostring(windowToFocus.id)
                    }):start()
                end)
            end
        end, { "-m", "window", "--focus", tostring(windowToFocus.id) }):start()
    end, { "-m", "query", "--windows" }):start()
end

-- ============================================================================
-- Hotkeys: Only work when F18 is held down
-- ============================================================================

-- F18 + T for Trae
hyperMode:bind({}, "t", function()
    cycleAppWindows("Trae")
end)

-- F18 + D for Debug
hyperMode:bind({}, "d", function()
    print("=== Window Cycle State ===")
    for appName, state in pairs(windowCycleState) do
        print(string.format("%s: lastIndex=%d, windows=%d, lastUpdate=%s",
            appName,
            state.lastIndex,
            #state.windowList,
            os.date("%H:%M:%S", state.lastUpdate)
        ))
        for i, win in ipairs(state.windowList) do
            local marker = (i == state.lastIndex) and " <-- LAST" or ""
            print(string.format("  [%d] ID:%d Space:%d - %s%s",
                i, win.id, win.space, win.title or "Untitled", marker))
        end
    end
    print("=== End State ===")
end)

-- F18 + R to Reset state
hyperMode:bind({}, "r", function()
    windowCycleState = {}
    hs.alert.show("Window cycle state reset!")
    print("Window cycle state has been reset")
end)

-- ============================================================================
-- Optional: Add more apps
-- ============================================================================
-- hyperMode:bind({}, "s", function()
--     cycleAppWindows("Safari")
-- end)

-- hyperMode:bind({}, "c", function()
--     cycleAppWindows("Chrome")
-- end)

-- ============================================================================
-- Alternative approach if the modal doesn't work with your Karabiner setup
-- ============================================================================
-- If the above doesn't work, try this simpler approach:
-- Comment out the modal code above and uncomment this:

--[[
hs.hotkey.bind({}, "f18", function()
    -- Do nothing, just to capture F18
end, function()
    -- F18 released
end)

-- Then use this format for bindings:
hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    local flags = event:getFlags()
    local keyCode = event:getKeyCode()

    -- Check if F18 (keycode 79) is pressed
    if hs.keycodes.map[79] then
        -- Map T key (keycode 17)
        if keyCode == 17 then
            cycleAppWindows("Trae")
            return true -- Consume the event
        end
        -- Map D key (keycode 2)
        if keyCode == 2 then
            -- Debug code here
            return true
        end
    end
    return false -- Let the event pass through
end):start()
--]]
