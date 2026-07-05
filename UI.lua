--Cleanup Previous runs
if _G.HavocCleanup then
    local success, errorMessage = pcall(_G.HavocCleanup)
    if not success then
        warn("failed to cleanup previous script instance: " ..tostring(errorMessage))
    end
end

local isScriptRunning = true
local drawingsPool = {}

_G.HavocCleanup = function()
    isScriptRunning = false
    
    if drawingsPool then
        for _, slot in ipairs(drawingsPool) do
            pcall(function() slot.box:Remove() end)
            pcall(function() slot.name:Remove() end)
            pcall(function() slot.distance:Remove() end)
        end
    end
    
    print("Cleaned up previous session and drawings.")
end

--Global Tables 
EntityCache = {
    NPCs = {}
}

--UI Definition
if typeof(UI) == "table" and UI.AddTab then
    UI.AddTab("Havoc", function(tab)
        local VisualSec = tab:Section("Visuals", "Left")
        VisualSec:Toggle("havoc_esp", "Esp", false)
    end)
else
    warn("UI Library not found")
end

--Screen Drawing Pool
local Camera = workspace.CurrentCamera
local MAX_SLOTS = 40 
local DEFAULT_TEXT_SIZE = 13

local function createScreenBox(color)
    local box = Drawing.new("Square")
    box.Filled = false 
    box.Thickness = 1
    box.Color = color or Color3.fromRGB(255, 80, 80)
    box.Visible = false
    return box
end

local function createScreenText(fontSize)
    local text = Drawing.new("Text")
    text.Size = fontSize or DEFAULT_TEXT_SIZE -- FIX: Changed from FontSize to Size
    text.Center = true
    text.Outline = true
    text.Font = Drawing.Fonts.Monospace 
    text.Color = Color3.fromRGB(235, 235, 235)
    text.Visible = false
    return text
end

for i = 1, MAX_SLOTS do
    drawingsPool[i] = {
        box = createScreenBox(),
        name = createScreenText(DEFAULT_TEXT_SIZE),
        distance = createScreenText(DEFAULT_TEXT_SIZE)
    }
end

local function hideVisualSlot(slot)
    slot.box.Visible = false
    slot.name.Visible = false
    slot.distance.Visible = false
end

--Cache
local function collectOnlyNpcs(inst, myChar, playerNames, outTable, depth)
    if depth > 8 then return end
    local ok, kids = pcall(function() return inst:GetChildren() end)
    if not ok or not kids then return end

    for _, child in ipairs(kids) do
        if child ~= myChar then
            local hum
            pcall(function() hum = child:FindFirstChildOfClass("Humanoid") end)
            
            if hum then
                local modelName = child.Name
                if not playerNames[modelName] then
                    local hrp = child:FindFirstChild("HumanoidRootPart")
                        or child:FindFirstChild("Torso")
                        or child:FindFirstChild("UpperTorso")
                        or child:FindFirstChild("Head")
                    if not hrp then
                        pcall(function() hrp = child:FindFirstChildWhichIsA("BasePart") end)
                    end
                    
                    if hrp then
                        table.insert(outTable, child)
                    end
                end
            else
                local cn = child.ClassName
                if cn == "Model" or cn == "Folder" then
                    collectOnlyNpcs(child, myChar, playerNames, outTable, depth + 1)
                end
            end
        end
    end
end

local function updateNpcCache()
    EntityCache.NPCs = {}

    local PlayersService = game:GetService("Players")
    if not PlayersService then return end

    local localPlayer = PlayersService.LocalPlayer
    local myChar = localPlayer and localPlayer.Character

    local playerNames = {}
    for _, p in ipairs(PlayersService:GetPlayers()) do
        playerNames[p.Name] = true
    end

    local folder = workspace:FindFirstChild("Characters")
    if folder then
        collectOnlyNpcs(folder, myChar, playerNames, EntityCache.NPCs, 0)
    else
        collectOnlyNpcs(workspace, myChar, playerNames, EntityCache.NPCs, 0)
    end
end

--Background thread
task.spawn(function()
    while isScriptRunning do
        pcall(updateNpcCache)
        task.wait(1)
    end
end)

-- =============================================================================
-- 7. MAIN RENDERING ENGINE
-- =============================================================================
local RunService = game:GetService("RunService")
local lastDrawnSlots = 0

local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
    if not isScriptRunning then
        if renderConnection then renderConnection:Disconnect() end
        return
    end

    local isEspEnabled = false
    if typeof(UI) == "table" and UI.GetValue then
        isEspEnabled = UI.GetValue("havoc_esp")
    end

    if not isEspEnabled then
        for i = 1, lastDrawnSlots do
            hideVisualSlot(drawingsPool[i])
        end
        lastDrawnSlots = 0
        return
    end

    local currentSlotIndex = 0
    local localPlayer = game:GetService("Players").LocalPlayer
    local myCharacter = localPlayer and localPlayer.Character
    local myRootPart = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")

    for _, npc in ipairs(EntityCache.NPCs or {}) do
        if currentSlotIndex >= MAX_SLOTS then break end

        local npcRoot = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head")
        if npcRoot then
            local screenPos, onScreen = Camera:WorldToViewportPoint(npcRoot.Position)

            if onScreen then
                currentSlotIndex = currentSlotIndex + 1
                local slot = drawingsPool[currentSlotIndex]

                local distanceToCam = Camera.CoordinateFrame.p - npcRoot.Position
                local factor = 1 / (distanceToCam.Magnitude * math.tan(math.rad(Camera.FieldOfView / 2))) * 1000
                local width = math.clamp(factor * 0.6, 10, 150)
                local height = math.clamp(factor, 15, 200)

                slot.box.Position = Vector2.new(screenPos.X - (width / 2), screenPos.Y - (height / 2))
                slot.box.Size = Vector2.new(width, height)
                slot.box.Visible = true

                slot.name.Text = npc.Name
                -- FIX: Changed from slot.name.FontSize to slot.name.Size
                slot.name.Position = Vector2.new(screenPos.X, screenPos.Y - (height / 2) - slot.name.Size - 2)
                slot.name.Visible = true

                if myRootPart then
                    local realDistance = math.floor((myRootPart.Position - npcRoot.Position).Magnitude)
                    slot.distance.Text = tostring(realDistance) .. "m"
                else
                    slot.distance.Text = "NPC"
                end
                slot.distance.Position = Vector2.new(screenPos.X, screenPos.Y + (height / 2) + 4)
                slot.distance.Visible = true
            end
        end
    end

    for i = currentSlotIndex + 1, lastDrawnSlots do
        hideVisualSlot(drawingsPool[i])
    end
    lastDrawnSlots = currentSlotIndex
end)

print("[Havoc Project] Step 2 & 3: Rendering engine loaded successfully.")
        
