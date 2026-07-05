if _G.HavocCleanup then
    local success, errorMessage = pcall(_G.HavocCleanup)
    if not success then
        warn("failed to cleanup previous script instance: " ..tostring(errorMessage))
    end
end

local isScriptRunnning = true

_G.HavocCleanup = function()
    isScriptRunning = false
    print("Cleaned up previous session.")
end

if typeof(UI) == "table" and UI.AddTab then
    UI.AddTab("Havoc", function(tab)
        local VisualSec = tab:Section("Visuals", "Left")
        VisualSec:Toggle("havoc_esp", "Esp", false)
    end)

else warn("UI Library not found")
end

task.spawn(function()
    while isScriptRunning do
        if typeof(UI) == "table" and UI.GetValue then
            if UI.GetValue("havoc_esp") then
                print("Script is active and running")
            end
        end

        task.wait(1)
    end

    print("Logic loop safely stopped.")
end)

print("[Havoc Project] Step 1 initialized successfully.")

    
        
