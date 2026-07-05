--Cleanup Previous runs
if _G.HavocCleanup then
    local success, errorMessage = pcall(_G.HavocCleanup)
    if not success then
        warn("failed to cleanup previous script instance: " ..tostring(errorMessage))
    end
end

local isScriptRunning = true

_G.HavocCleanup = function()
    isScriptRunning = false
    print("Cleaned up previous session.")
end
--Global Tables 
EntityCache = {
    NPCs = {}
}
--UI DEF
if typeof(UI) == "table" and UI.AddTab then
    UI.AddTab("Havoc", function(tab)
        local VisualSec = tab:Section("Visuals", "Left")
        VisualSec:Toggle("havoc_esp", "Esp", false)
    end)
else
    warn("UI Library not found")
end

--Cache
local function collectNpcsFromFolder(instance, playersService, localCharacter, outTable)
    local success, children = pcall(function() return instance:GetChildren() end)
    if not success or not children then return end

    for _, child in ipairs(children) do
        if child ~= localCharacter then
            
            local humanoid = child:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local isAPlayer = playersService:GetPlayerFromCharacter(child)
                
                if not isAPlayer then
                    table.insert(outTable, child)
                end
            else
                if child:IsA("Model") or child:IsA("Folder") then
                    collectNpcsFromFolder(child, playersService, localCharacter, outTable)
                end
            end
            
        end
    end
end

local function updateNpcCache()
    EntityCache.NPCs = {}

    local PlayersService = game:GetService("Players")
    if not PlayersService then return end
    
    local charactersFolder = workspace:FindFirstChild("Characters")
    if charactersFolder then
        local children = charactersFolder:GetChildren()
        print(string.format("--- [DIAGNOSTIC] Found %d total items inside Characters folder ---", #children))
        
        for _, child in ipairs(children) do
            -- Print the name of the object and its Class Type (e.g., Model, Folder, Part)
            print("Name: " .. tostring(child.Name) .. " | Class: " .. tostring(child.ClassName))
            
            -- See if it has a Humanoid or a RootPart
            local hasHumanoid = child:FindFirstChildOfClass("Humanoid") and "YES" or "NO"
            print("  -> Has Humanoid? " .. hasHumanoid)
            
            -- Standard NPC check logic
            if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                local isAPlayer = PlayersService:GetPlayerFromCharacter(child)
                if not isAPlayer then
                    table.insert(EntityCache.NPCs, child)
                end
            end
        end
        print("---------------------------------------------------------")
    else
        print("[DIAGNOSTIC] Could not find a folder named 'Characters' in Workspace!")
    end
end

--Background thread
task.spawn(function()
    while isScriptRunning do
        pcall(updateNpcCache)
        task.wait(1)
    end
end)
    

--MainLoop
task.spawn(function()
    while isScriptRunning do
        if typeof(UI) == "table" and UI.GetValue then
            if UI.GetValue("havoc_esp") then
                print("--- [DEBUG] Tracked NPCs ---")
                
                if #EntityCache.NPCs == 0 then
                    print("No non-player NPCs found in workspace.")
                else
                    for index, npc in ipairs(EntityCache.NPCs) do
                        print(string.format("[%d] %s", index, npc.Name))
                    end
                end
                
                print("-----------------------------")
            end
        end

        task.wait(1)
    end

    print("Logic loop safely stopped.")
end)

print("[Havoc Project] Step 1 initialized successfully.")

    
        
