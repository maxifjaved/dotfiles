-- ============================================================================
-- Step 1: List all Desktops and Full-Screen Spaces
-- ============================================================================
-- Define F18 as our Hyper key, triggered by Karabiner-Elements.
local hyper = { "f18" }

-- Notification to confirm the new script is active.
hs.alert.show("Space Listing Script Loaded (Hyper+D)")

-- ============================================================================
-- Hotkey: Hyper + D
-- Action: List every Space on the system.
-- ============================================================================
hs.hotkey.bind(hyper, "D", function()
    print("--- Listing All Spaces/Desktops ---")

    -- Get all spaces grouped by screen
    local allSpaces = hs.spaces.allSpaces()
    local spaceCount = 0

    -- Iterate through each screen
    for screenUUID, spaceIDs in pairs(allSpaces) do
        print("Screen: " .. screenUUID)

        -- Iterate through each space on this screen
        for index, spaceID in ipairs(spaceIDs) do
            spaceCount = spaceCount + 1
            local spaceType = "Unknown"
            local spaceName = ""

            -- Get space type
            local spaceTypeNum = hs.spaces.spaceType(spaceID)
            if spaceTypeNum then
                if spaceTypeNum == 0 then
                    spaceType = "Desktop"
                elseif spaceTypeNum == 4 then
                    spaceType = "Full-Screen App"
                else
                    spaceType = "Type " .. tostring(spaceTypeNum)
                end
            end

            -- Try to get windows in this space
            local windowsInSpace = hs.spaces.windowsForSpace(spaceID)
            if windowsInSpace and #windowsInSpace > 0 then
                local win = hs.window.get(windowsInSpace[1])
                if win then
                    local appName = win:application():name()
                    local winTitle = win:title()
                    spaceName = string.format("%s - %s", appName, winTitle)
                end
            else
                spaceName = "Desktop " .. tostring(index)
            end

            -- Print the result for this space
            print(string.format("  Space #%d (ID:%s): [%s] %s",
                spaceCount, tostring(spaceID), spaceType, spaceName))
        end
    end

    print("Total Spaces: " .. spaceCount)
    print("--- End of List ---")
end)
