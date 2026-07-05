-- =============================================================================
-- HAVOC PROJECT: CLEAN MATCHED INSTANCE
-- =============================================================================

-- 1. CLEANUP PREVIOUS RUNS
if _G.HavocCleanup then
    local success, errorMessage = pcall(_G.HavocCleanup)
    if not success then
        warn("Failed to cleanup previous script instance: " .. tostring(errorMessage))
    end
end

local isScriptRunning = true
local drawingsPool = {}

_G.HavocCleanup = function()
    isScriptRunning = false
    
    if drawingsPool then
        for _, slot in ipairs(drawingsPool) do
            pcall(function() slot.box1:Remove() end)
            pcall(function() slot.box2:Remove() end)
            pcall(function() slot.box3:Remove() end)
            pcall(function() slot.box4:Remove() end)
            pcall(function() slot.name:Remove() end)
            pcall(function() slot.distance:Remove() end)
        end
    end
    
    print("Cleaned up previous session and drawings.")
end

-- 2. GLOBAL TABLES & CONFIGS
EntityCache = { NPCs = {} }
local BOX_COL = Color3.fromRGB(255, 80, 80)
local TEXT_SIZE = 13

-- Adjusted offsets to properly encase standard NPC humanoids
local V3_HEAD = Vector3.new(0, 2.3, 0)
local V3_FOOT = Vector3.new(0, 3.0, 0)

-- 3. UI DEFINITION
if typeof(UI) == "table" and UI.AddTab then
    UI.AddTab("Havoc", function(tab)
        local VisualSec = tab:Section("Visuals", "Left")
        VisualSec:Toggle("havoc_esp", "Esp", true)
    end)
else
    warn("UI Library not found")
end

-- 4. ENVIRONMENT NATIVE FUNCTIONS
local WorldToScreenFn = WorldToScreen -- Native environment global discovered in reference script
local function worldToScreen(pos)
    if WorldToScreenFn then
        return WorldToScreenFn(pos)
    end
    return nil, false
end

-- 5. SCREEN DRAWING POOL
local Camera = workspace.CurrentCamera
local MAX_SLOTS = 40 
local FONT = Drawing.Fonts.Monospace or Drawing.Fonts.System

local function newLine()
    local l = Drawing.new("Line")
    l.Thickness = 1
    l.Color = BOX_COL
    l.Visible = false
    return l
end

local function createScreenText()
    local t = Drawing.new("Text")
    t.Size = TEXT_SIZE
    t.Center = true
    t.Outline = true
    t.Font = FONT
    t.Visible = false
    return t
end

-- Initialize pool objects cleanly matching the 4-line box structure
for i = 1, MAX_SLOTS do
    drawingsPool[i] = {
        box1 = newLine(),
        box2 = newLine(),
        box3 = newLine(),
        box4 = newLine(),
        name = createScreenText(),
        distance = createScreenText()
    }
end

local function hideVisualSlot(slot)
    slot.box1.Visible = false
    slot.box2.Visible = false
    slot.box3.Visible = false
    slot.box4.Visible = false
    slot.name.Visible = false
    slot.distance.Visible = false
end

local function drawEspBox(slot, x, y, w, h)
    local tl = Vector2.new(x, y)
    local tr = Vector2.new(x + w, y)
    local bl = Vector2.new(x, y + h)
    local br = Vector2.new(x + w, y + h)
    
    slot.box1.From, slot.box1.To = tl, tr
    slot.box2.From, slot.box2.To = bl, br
    slot.box3.From, slot.box3.To = tl, bl
    slot.box4.From, slot.box4.To = tr, br
    
    slot.box1.Visible = true
    slot.box2.Visible = true
    slot.box3.Visible = true
    slot.box4.Visible = true
end

-- 6. CACHE ENGINE
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

-- Cache thread
task.spawn(function()
    while isScriptRunning do
        pcall(updateNpcCache)
        task.wait(0.5)
    end
end)

-- =============================================================================
-- 7. MAIN RENDERING ENGINE (Native WorldToScreen Processing)
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
            local npcPos = npcRoot.Position
            
            -- Vector projection using updated V3 offsets
            local topPos, topOn = worldToScreen(npcPos + V3_HEAD)
            local botPos, botOn = worldToScreen(npcPos - V3_FOOT)

            if topOn and botOn then
                currentSlotIndex = currentSlotIndex + 1
                local slot = drawingsPool[currentSlotIndex]

                -- Box sizing derivations from screen space calculations
                local height = math.abs(botPos.Y - topPos.Y)
                if height < 1 then height = 1 end
                local width = height * 0.55 -- Scaled layout constraint
                local boxX = topPos.X - width * 0.5
                local boxY = topPos.Y

                -- Draw perfectly aligned visuals
                drawEspBox(slot, boxX, boxY, width, height)

                -- Identity tag positioning
                slot.name.Text = npc.Name
                slot.name.Position = Vector2.new(topPos.X, boxY - TEXT_SIZE - 2)
                slot.name.Visible = true

                -- Range metric calculation
                if myRootPart then
                    local realDistance = math.floor((myRootPart.Position - npcPos).Magnitude)
                    slot.distance.Text = tostring(realDistance) .. "m"
                else
                    slot.distance.Text = "NPC"
                end
                slot.distance.Position = Vector2.new(topPos.X, boxY + height + 2)
                slot.distance.Visible = true
            end
        end
    end

    -- Turn off unused pool items
    for i = currentSlotIndex + 1, lastDrawnSlots do
        hideVisualSlot(drawingsPool[i])
    end
    lastDrawnSlots = currentSlotIndex
end)

print("[Havoc Project] Engine fully synchronized with native environment projection.")
