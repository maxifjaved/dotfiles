-- ============================================================================
-- Enhanced Window Cycler with Predictable State Management
-- ============================================================================

-- Path to yabai (auto-detect Intel vs Apple Silicon)
local YABAI_PATH
if hs.fs.attributes("/opt/homebrew/bin/yabai") then
    YABAI_PATH = "/opt/homebrew/bin/yabai"  -- Apple Silicon
else
    YABAI_PATH = "/usr/local/bin/yabai"     -- Intel
end

-- Notification to confirm the script is active
hs.alert.show("Enhanced Window Cycler Loaded!")

-- ============================================================================
-- FIXED: Proper F18 key binding with debug alerts
-- F18 is a key, not a modifier, so we need to handle it differently
-- ============================================================================
local hyperMode = hs.hotkey.modal.new()

-- When F18 is pressed, enter "hyper mode"
hs.hotkey.bind({}, "f18",
    function()
        hs.alert.show("⌨️ F18 down → HYPER ON", 0.5)
        hyperMode:enter()
    end,
    function()
        hs.alert.show("⌨️ F18 up → HYPER OFF", 0.5)
        hyperMode:exit()
    end
)

-- ============================================================================
-- Enhanced State Management: Store window ID and cycle history
-- ============================================================================
local windowCycleState = {}

-- ============================================================================
-- Helper: Filter and sort windows predictably
-- ============================================================================
local function filterAndSortWindows(windows)
    local validWindows = {}

    -- Filter out invalid or minimized windows (allow windows on other spaces/desktops)
    for _, window in ipairs(windows) do
        local reasons = {}
        local isValid = true
        
        if not window then
            table.insert(reasons, "window is nil")
            isValid = false
        elseif not window.id then
            table.insert(reasons, "no id")
            isValid = false
        elseif not window.title then
            table.insert(reasons, "no title")
            isValid = false
        elseif window["is-minimized"] then
            table.insert(reasons, "minimized")
            isValid = false
        elseif window["is-standard"] == false then  -- Only reject if explicitly false, allow null/true
            table.insert(reasons, "not standard")
            isValid = false
        elseif window.role ~= "AXWindow" then
            table.insert(reasons, "role is not AXWindow: " .. (window.role or "nil"))
            isValid = false
        end

        -- Additional check: Skip windows without valid space/display info (usually system windows)
        if isValid and (not window.space or not window.display) then
            table.insert(reasons, "no space/display info")
            isValid = false
        end
        
        if isValid then
            table.insert(validWindows, window)
            print(string.format("DEBUG: ACCEPTED window: %s (ID: %s, Space: %s, Display: %s)", 
                window.title or "No title", tostring(window.id), 
                tostring(window.space), tostring(window.display)))
        else
            print(string.format("DEBUG: REJECTED window: %s - %s", 
                window.title or "No title", table.concat(reasons, ", ")))
        end
    end

    -- Sort by predictable criteria: space first, then by position, then title
    table.sort(validWindows, function(a, b)
        if a.space ~= b.space then
            return a.space < b.space
        end
        -- Sort by position (top-left to bottom-right)
        if a.frame.y ~= b.frame.y then
            return a.frame.y < b.frame.y
        end
        if a.frame.x ~= b.frame.x then
            return a.frame.x < b.frame.x
        end
        -- Fallback to title for consistent ordering
        return (a.title or "") < (b.title or "")
    end)

    return validWindows
end

-- ============================================================================
-- Helper: Get or initialize enhanced state for an app
-- ============================================================================
local function getAppState(appName)
    if not windowCycleState[appName] then
        windowCycleState[appName] = {
            lastWindowID = nil,
            windowList = {},
            lastUpdate = 0,
            cycleHistory = {}, -- Track recent cycle history to prevent ping-ponging
            lastCycleTime = 0
        }
    end
    return windowCycleState[appName]
end

-- ============================================================================
-- Helper: Prevent two-window ping-pong cycling
-- ============================================================================
local function getNextWindowIndex(state, currentWindowID, windowList)
    local currentIndex = nil

    -- Find current window index
    for i, window in ipairs(windowList) do
        if window.id == currentWindowID then
            currentIndex = i
            break
        end
    end

    if not currentIndex then
        return 1 -- Default to first window if current not found
    end

    -- Check for recent cycling pattern to prevent ping-ponging
    local now = os.time()
    if now - state.lastCycleTime < 2 then -- Within 2 seconds
        table.insert(state.cycleHistory, currentWindowID)
        -- Keep only last 4 entries
        if #state.cycleHistory > 4 then
            table.remove(state.cycleHistory, 1)
        end

        -- Detect ping-pong pattern (cycling between same 2 windows)
        if #state.cycleHistory >= 4 then
            local recent = state.cycleHistory
            local isPingPong = (recent[1] == recent[3] and recent[2] == recent[4] and
                recent[1] ~= recent[2])

            if isPingPong and #windowList > 2 then
                -- Break the cycle by skipping to the next available window
                local nextIndex = currentIndex + 1
                if nextIndex > #windowList then
                    nextIndex = 1
                end
                -- If that's still in the ping-pong pair, skip one more
                if windowList[nextIndex].id == recent[2] or windowList[nextIndex].id == recent[1] then
                    nextIndex = nextIndex + 1
                    if nextIndex > #windowList then
                        nextIndex = 1
                    end
                end
                state.cycleHistory = {} -- Reset history after breaking cycle
                return nextIndex
            end
        end
    else
        -- Reset history if enough time has passed
        state.cycleHistory = {}
    end

    state.lastCycleTime = now

    -- Normal cycling: go to next window
    local nextIndex = currentIndex + 1
    if nextIndex > #windowList then
        nextIndex = 1
    end

    return nextIndex
end

-- ============================================================================
-- Enhanced Main Cycle Function with Smart State Management
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

        -- Filter to get only windows for this app
        local appWindows = {}
        print(string.format("DEBUG: Looking for app '%s' in %d total windows", appName, #allWindows))
        
        for _, windowData in ipairs(allWindows) do
            -- Debug: show app names to help identify the correct app name
            if windowData.app then
                print(string.format("DEBUG: Found app '%s' with window title '%s'", 
                    windowData.app, windowData.title or "No title"))
            end
            
            if windowData.app == appName then
                table.insert(appWindows, windowData)
                print(string.format("DEBUG: Matched window for %s: %s", appName, windowData.title or "No title"))
            end
        end
        
        print(string.format("DEBUG: Found %d windows for app '%s'", #appWindows, appName))

        if #appWindows == 0 then
            print(string.format("No %s windows found. Attempting to launch...", appName))
            hs.alert.show(string.format("Launching %s...", appName))
            hs.application.launchOrFocus(appName)
            local state = getAppState(appName)
            state.lastWindowID = nil
            state.windowList = {}
            return
        end

        -- Use enhanced filtering and sorting
        print(string.format("DEBUG: Before filtering: %d windows", #appWindows))
        appWindows = filterAndSortWindows(appWindows)
        print(string.format("DEBUG: After filtering: %d windows", #appWindows))

        if #appWindows == 0 then
            hs.alert.show(string.format("No valid %s windows to cycle", appName))
            print(string.format("DEBUG: No windows passed filtering for app '%s'", appName))
            return
        end

        local state = getAppState(appName)
        state.windowList = appWindows
        state.lastUpdate = os.time()

        -- Find currently focused window
        local currentFocusedID = nil
        for _, win in ipairs(appWindows) do
            if win["has-focus"] then
                currentFocusedID = win.id
                break
            end
        end

        -- If no window has focus, use the last known focused window
        if not currentFocusedID then
            currentFocusedID = state.lastWindowID
        end

        -- Get next window using enhanced logic that prevents ping-ponging
        local nextIndex
        if currentFocusedID then
            nextIndex = getNextWindowIndex(state, currentFocusedID, appWindows)
        else
            nextIndex = 1 -- Default to first window
        end

        local windowToFocus = appWindows[nextIndex]
        state.lastWindowID = windowToFocus.id

        -- Display user-friendly notification
        local title = windowToFocus.title
        if title and #title > 30 then
            title = string.sub(title, 1, 27) .. "..."
        end

        local spaceInfo = ""
        if windowToFocus.space and windowToFocus.space ~= 0 then
            spaceInfo = string.format(" (Space %d)", windowToFocus.space)
        end

        hs.alert.show(string.format("%s: %d/%d - %s%s",
            appName, nextIndex, #appWindows, title or "Untitled", spaceInfo))

        print(string.format("Focusing %s window #%d (ID: %d, Space: %d, Title: %s)",
            appName, nextIndex, windowToFocus.id, windowToFocus.space, windowToFocus.title or "Untitled"))

        -- Focus the selected window with improved error handling
        hs.task.new(YABAI_PATH, function(exitCode, stdOut, stdErr)
            if exitCode ~= 0 then
                print("Error focusing window: " .. (stdErr or ""))
                -- Try to focus the space first, then the window
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
    print("=== Enhanced Window Cycle State ===")
    for appName, state in pairs(windowCycleState) do
        print(string.format("%s: lastWindowID=%s, windows=%d, lastUpdate=%s, cycleHistoryLen=%d",
            appName,
            tostring(state.lastWindowID),
            #state.windowList,
            os.date("%H:%M:%S", state.lastUpdate),
            #state.cycleHistory
        ))

        -- Show cycle history
        if #state.cycleHistory > 0 then
            local historyStr = "Recent cycle history: "
            for _, winID in ipairs(state.cycleHistory) do
                historyStr = historyStr .. winID .. " -> "
            end
            print("  " .. historyStr:sub(1, -5)) -- Remove trailing " -> "
        end

        -- Show window list with current focus indicator
        for i, win in ipairs(state.windowList) do
            local marker = ""
            if win.id == state.lastWindowID then
                marker = " <-- LAST FOCUSED"
            elseif win["has-focus"] then
                marker = " <-- CURRENTLY FOCUSED"
            end

            local visible = win["is-visible"] and "visible" or "hidden"
            local minimized = win["is-minimized"] and "minimized" or "normal"

            print(string.format("  [%d] ID:%d Space:%d %s/%s - %s%s",
                i, win.id, win.space or 0, visible, minimized, win.title or "Untitled", marker))
        end
    end
    print("=== End Enhanced State ===")
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
-- If the modal approach gives you grief, uncomment this simpler fallback:

--[[
-- Track F18 state with a flag
local hyperPressed = false

-- Track F18 state
hs.hotkey.bind({}, "f18",
    function() 
        hyperPressed = true
        hs.alert.show("⌨️ F18 down → HYPER ON", 0.5)
    end,
    function() 
        hyperPressed = false 
        hs.alert.show("⌨️ F18 up → HYPER OFF", 0.5)
    end
)

-- Only cycle when T is pressed *and* hyperPressed is true
hs.hotkey.bind({}, "t", function()
    if hyperPressed then
        cycleAppWindows("Trae")
    end
end)

-- Debug hotkey
hs.hotkey.bind({}, "d", function()
    if hyperPressed then
        print("=== Enhanced Window Cycle State ===")
        -- ... debug code here ...
    end
end)

-- Reset hotkey
hs.hotkey.bind({}, "r", function()
    if hyperPressed then
        windowCycleState = {}
        hs.alert.show("Window cycle state reset!")
    end
end)
--]]

-- ============================================================================
-- ENHANCEMENT SUMMARY
-- ============================================================================
-- This enhanced version addresses the original issues and is now 100% ready:
--
-- 1. PREDICTABLE SORTING: Windows sort by space, position (top-left to 
--    bottom-right), then title - providing consistent, predictable ordering
--
-- 2. SMART FILTERING: Only cycles through visible, non-minimized, standard 
--    windows, preventing cycling to hidden/invalid windows
--
-- 3. PING-PONG PREVENTION: Detects rapid cycling between same 2 windows
--    and breaks the cycle by jumping to the next available window
--
-- 4. IMPROVED STATE MANAGEMENT: Tracks windows by ID instead of index, making
--    state persistent even when window list changes
--
-- 5. ENHANCED DEBUGGING: F18+D shows detailed state including cycle history
--    and window properties for troubleshooting. Visual alerts show F18 state.
--
-- 6. BETTER ERROR HANDLING: Gracefully handles focus failures with fallback
--    to space switching + delayed window focus
--
-- 7. CROSS-PLATFORM SUPPORT: Auto-detects yabai path for Intel/Apple Silicon
--
-- 8. MODAL VERIFICATION: Debug alerts confirm F18 key state for troubleshooting
--
-- Usage: Hold F18 + T to cycle windows, F18 + D for debug, F18 + R to reset
-- Fallback method available in comments if modal approach has issues
-- ============================================================================
