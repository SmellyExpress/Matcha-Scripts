-- =============================================================================
-- 1. CLEANUP PREVIOUS RUNS
-- =============================================================================
-- If this script ran before, call its cleanup function to prevent overlapping loops
if _G.HavocCleanup then
    local success, err = pcall(_G.HavocCleanup)
    if not success then
        warn("Failed to clean up previous script instance: " .. tostring(err))
    end
end

-- Define a running flag that we can set to false when shutting down
local isScriptRunning = true

-- =============================================================================
-- 2. CREATE THE CLEANUP FUNCTION
-- =============================================================================
_G.HavocCleanup = function()
    isScriptRunning = false
    print("[Havoc Project] Cleaned up previous session.")
end

-- =============================================================================
-- 3. BUILD THE USER INTERFACE
-- =============================================================================
if typeof(UI) == "table" and UI.AddTab then
    UI.AddTab("Havoc Project", function(tab)
        -- Create the main section
        local MainSec = tab:Section("Main Features", "Left")
        
        -- Add our primary toggle
        MainSec:Toggle("havoc_enabled", "Master Switch", false)
    end)
else
    warn("[Havoc Project] UI Library not found! Running in headless mode.")
end

-- =============================================================================
-- 4. THE MAIN LOGIC LOOP
-- =============================================================================
task.spawn(function()
    while isScriptRunning do
        -- We will verify if our UI toggle works by printing to the console
        if typeof(UI) == "table" and UI.GetValue then
            if UI.GetValue("havoc_enabled") then
                print("[Havoc Project] Script is active and running!")
            end
        end
        
        task.wait(1) -- Check once per second for testing
    end
    print("[Havoc Project] Logic loop safely stopped.")
end)

print("[Havoc Project] Step 1 initialized successfully.")
