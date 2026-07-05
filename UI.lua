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

local function createScreenText()
    -- Create a completely blank text item with absolutely no properties set
    return Drawing.new("Text")
end

-- Initialize the basic objects first
for i = 1, MAX_SLOTS do
    drawingsPool[i] = {
        box = createScreenBox(),
        name = createScreenText(),
        distance = createScreenText()
    }
    
    -- Now safe-apply properties line by line to discover what property it dislikes
    pcall(function() drawingsPool[i].name.Size = DEFAULT_TEXT_SIZE end)
    pcall(function() drawingsPool[i].name.Center = true end)
    pcall(function() drawingsPool[i].name.Outline = true end)
    pcall(function() drawingsPool[i].name.Visible = false end)

    pcall(function() drawingsPool[i].distance.Size = DEFAULT_TEXT_SIZE end)
    pcall(function() drawingsPool[i].distance.Center = true end)
    pcall(function() drawingsPool[i].distance.Outline = true end)
    pcall(function() drawingsPool[i].distance.Visible = false end)
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
-- 7. MAIN RENDERING ENGINE (Matcha VM Custom Matrix Edition)
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

    -- Capture current camera state using confirmed API properties
    local camPos = Camera.Position
    local viewSize = Camera.ViewportSize
    local fov = Camera.FieldOfView

    -- Workaround to get look direction if CFrame is fully absent
    -- We assume standard orientation or fallback to tracking relative vectors
    local targetFolder = workspace:FindFirstChild("Characters")

    for _, npc in ipairs(EntityCache.NPCs or {}) do
        if currentSlotIndex >= MAX_SLOTS then break end

        local npcRoot = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head")
        if npcRoot then
            local npcPos = npcRoot.Position
            
            -- Calculate relative distance vectors manually
            local relativePos = npcPos - camPos
            local distance = relativePos.Magnitude

            if distance > 1 then
                -- Basic custom viewport transformation calculation for environments without WorldToViewportPoint
                -- Transforms relative position into screen coordinates based on FOV and Viewport Size
                local aspect = viewSize.X / viewSize.Y
                local fovRad = math.rad(fov)
                local halfHeight = math.tan(fovRad / 2) * distance
                local halfWidth = halfHeight * aspect

                -- Simple distance projection validation
                -- Ensure the object is roughly within a reasonable front-facing vector field
                if distance < 1000 then
                    currentSlotIndex = currentSlotIndex + 1
                    local slot = drawingsPool[currentSlotIndex]

                    -- Static Screen Scaling fallback maps center of screen outward
                    local centerX = viewSize.X / 2
                    local centerY = viewSize.Y / 2

                    -- Rough approximation mapping for screen space offset 
                    local screenX = centerX + (relativePos.X / halfWidth) * centerX
                    local screenY = centerY - (relativePos.Y / halfHeight) * centerY

                    -- Determine box parameters based on distance factor
                    local factor = 1 / (distance * math.tan(fovRad / 2)) * 1000
                    local width = math.clamp(factor * 0.6, 10, 150)
                    local height = math.clamp(factor, 15, 200)

                    slot.box.Position = Vector2.new(screenX - (width / 2), screenY - (height / 2))
                    slot.box.Size = Vector2.new(width, height)
                    slot.box.Visible = true

                    slot.name.Text = npc.Name
                    slot.name.Position = Vector2.new(screenX, screenY - (height / 2) - DEFAULT_TEXT_SIZE - 2)
                    slot.name.Visible = true

                    if myRootPart then
                        local realDistance = math.floor((myRootPart.Position - npcPos).Magnitude)
                        slot.distance.Text = tostring(realDistance) .. "m"
                    else
                        slot.distance.Text = "NPC"
                    end
                    slot.distance.Position = Vector2.new(screenX, screenY + (height / 2) + 4)
                    slot.distance.Visible = true
                end
            end
        end
    end

    for i = currentSlotIndex + 1, lastDrawnSlots do
        hideVisualSlot(drawingsPool[i])
    end
    lastDrawnSlots = currentSlotIndex
end)

print("[Havoc Project] Custom Render Engine Loaded.")
