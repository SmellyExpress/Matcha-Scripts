local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Lighting    = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local GuiService  = game:GetService("GuiService")
local Camera      = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local DEBUG = false

local DEF = {
    havoc_esp_enabled     = true,
    havoc_esp_dist_max    = 1500,
    havoc_esp_update_rate = 15,
    havoc_esp_box         = true,
    havoc_esp_name        = true,
    havoc_esp_distance    = true,
    havoc_esp_tracer      = false,
    havoc_nofog           = false,
}

local AIM_DEF = {
    enabled  = false,
    key      = 0x02, -- Right Mouse Button
    key_type = "hold",
    fov      = 180,
    smooth   = 6.0,
    dist_max = 1500,
}

local BOX_COL_DEF = Color3.fromRGB(255, 80, 80)
local NAME_COL    = Color3.fromRGB(235, 235, 235)
local DIST_COL    = Color3.fromRGB(170, 170, 170)
local TRACER_COL  = Color3.fromRGB(255, 80, 80)
local TEXT_SIZE   = 13

local function uiGet(key, fallback)
    if typeof(UI) == "table" and UI.GetValue then
        local v = UI.GetValue(key)
        if v ~= nil then return v end
    end
    return fallback
end

local function uiColor(key, fallback)
    if typeof(UI) == "table" and UI.GetValue then
        local ok, r, g, b = pcall(function() return UI.GetValue(key) end)
        if ok and type(r) == "number" then return Color3.new(r, g, b) end
    end
    return fallback
end

local _off = {}
pcall(function()
    local res = game:HttpGet("https://offsets.imtheo.lol/Offsets.json")
    local decoded = HttpService:JSONDecode(res)
    _off = (decoded and decoded.Offsets) or {}
end)

local function off(section, key, fallback)
    local s = _off[section]
    return (s and s[key]) or fallback
end

local OFF_FOG_END      = off("Lighting",   "FogEnd",   0x13C)
local OFF_FOG_START    = off("Lighting",   "FogStart", 0x140)
local OFF_ATMO_DENSITY = off("Atmosphere", "Density",  0x0E8)
local OFF_ATMO_GLARE   = off("Atmosphere", "Glare",    0x0EC)
local OFF_ATMO_HAZE    = off("Atmosphere", "Haze",     0x0F0)
local OFF_ATMO_OFFSET  = off("Atmosphere", "Offset",   0x0F4)

local lightingAddr, atmoAddr = 0, 0
local origFogEnd, origFogStart = 100000, 0
local origDensity, origGlare, origHaze, origOffset = 0.3, 0, 0, 0.25
local fogCaptured = false
local lastNoFog = false

local function captureFog()
    fogCaptured = true
    pcall(function() lightingAddr = Lighting.Address or 0 end)
    pcall(function() origFogEnd = Lighting.FogEnd; origFogStart = Lighting.FogStart end)
    local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmo then
        pcall(function() atmoAddr = atmo.Address or 0 end)
        pcall(function()
            origDensity = atmo.Density; origGlare = atmo.Glare
            origHaze    = atmo.Haze;    origOffset = atmo.Offset
        end)
    end
end

local function applyNoFog()
    if not fogCaptured then captureFog() end
    if not memory_write then return end
    pcall(function()
        if lightingAddr ~= 0 then
            memory_write("float", lightingAddr + OFF_FOG_END,   9e8)
            memory_write("float", lightingAddr + OFF_FOG_START, 9e8)
        end
        if atmoAddr ~= 0 then
            memory_write("float", atmoAddr + OFF_ATMO_DENSITY, 0)
            memory_write("float", atmoAddr + OFF_ATMO_GLARE,   0)
            memory_write("float", atmoAddr + OFF_ATMO_HAZE,    0)
            memory_write("float", atmoAddr + OFF_ATMO_OFFSET,  0)
        end
    end)
end

local function restoreFog()
    if not fogCaptured or not memory_write then return end
    pcall(function()
        if lightingAddr ~= 0 then
            memory_write("float", lightingAddr + OFF_FOG_END,   origFogEnd)
            memory_write("float", lightingAddr + OFF_FOG_START, origFogStart)
        end
        if atmoAddr ~= 0 then
            memory_write("float", atmoAddr + OFF_ATMO_DENSITY, origDensity)
            memory_write("float", atmoAddr + OFF_ATMO_GLARE,   origGlare)
            memory_write("float", atmoAddr + OFF_ATMO_HAZE,    origHaze)
            memory_write("float", atmoAddr + OFF_ATMO_OFFSET,  origOffset)
        end
    end)
end

if _G.HAVOC_ESP_CLEANUP then pcall(_G.HAVOC_ESP_CLEANUP) end

local running  = true
local drawings = {}

local function track(obj)
    drawings[obj] = true
    return obj
end

local renderConn = nil
_G.HAVOC_ESP_CLEANUP = function()
    running = false
    if renderConn then
        pcall(function() renderConn:Disconnect() end)
        renderConn = nil
    end
    for obj in pairs(drawings) do
        pcall(function() obj:Remove() end)
    end
    drawings = {}
    pcall(restoreFog)
end

local FONT      = Drawing.Fonts.Monospace or Drawing.Fonts.System
local MAX_SLOTS = 40

local function newLine(color, thickness)
    local l = track(Drawing.new("Line"))
    l.Thickness = thickness or 1
    l.Color     = color or Color3.new(1, 1, 1)
    l.Visible   = false
    return l
end

local function newText(size, center)
    local t = track(Drawing.new("Text"))
    t.Size    = size or TEXT_SIZE
    t.Center  = center ~= false
    t.Outline = true
    t.Font    = FONT
    t.Visible = false
    return t
end

local function newSlot()
    return {
        box    = { newLine(BOX_COL_DEF), newLine(BOX_COL_DEF), newLine(BOX_COL_DEF), newLine(BOX_COL_DEF) },
        name   = newText(TEXT_SIZE, true),
        dist   = newText(TEXT_SIZE, true),
        tracer = newLine(TRACER_COL),
    }
end

local slots = {}
for i = 1, MAX_SLOTS do slots[i] = newSlot() end

local function hideSlot(s)
    for i = 1, 4 do s.box[i].Visible = false end
    s.name.Visible   = false
    s.dist.Visible   = false
    s.tracer.Visible = false
end

local function drawBox(s, x, y, w, h, col)
    local tl = Vector2.new(x, y)
    local tr = Vector2.new(x + w, y)
    local bl = Vector2.new(x, y + h)
    local br = Vector2.new(x + w, y + h)
    s.box[1].From, s.box[1].To = tl, tr
    s.box[2].From, s.box[2].To = bl, br
    s.box[3].From, s.box[3].To = tl, bl
    s.box[4].From, s.box[4].To = tr, br
    for i = 1, 4 do
        s.box[i].Color   = col
        s.box[i].Visible = true
    end
end

local V3_HEAD = Vector3.new(0, 2.6, 0)
local V3_FOOT = Vector3.new(0, 3.2, 0)

-- Reverted back to your original working environment-native implementation
local WorldToScreenFn = WorldToScreen
local function worldToScreen(pos)
    return WorldToScreenFn(pos)
end

local eyePart, eyeStamp = nil, 0
local EYE_TTL = 1.0

local function getEyePos()
    local cp = Camera and Camera.Position
    if cp and (cp.X ~= 0 or cp.Y ~= 0 or cp.Z ~= 0) then return cp end

    local now = os.clock()
    if not eyePart or (now - eyeStamp) > EYE_TTL then
        eyeStamp = now
        eyePart = nil
        local ch = LocalPlayer and LocalPlayer.Character
        if ch then
            eyePart = ch:FindFirstChild("HumanoidRootPart")
                or ch:FindFirstChild("Head")
                or ch:FindFirstChildWhichIsA("BasePart")
        end
        if not eyePart then
            local uid = LocalPlayer and LocalPlayer.UserId
            local folder = workspace:FindFirstChild("Characters")
            if uid and folder then
                for _, c in ipairs(folder:GetChildren()) do
                    local ok, lid = pcall(function() return c:GetAttribute("LinkPlayerId") end)
                    if ok and lid == uid then
                        eyePart = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart")
                        break
                    end
                end
            end
        end
    end

    if eyePart then
        local ok, p = pcall(function() return eyePart.Position end)
        if ok and p then return p end
    end
    return nil
end

local function collectFrom(inst, myChar, playerNames, out, depth)
    if depth > 8 then return end
    local ok, kids = pcall(function() return inst:GetChildren() end)
    if not ok or not kids then return end

    for _, child in ipairs(kids) do
        if child ~= myChar and not playerNames[child.Name] then
            local hum
            pcall(function() hum = child:FindFirstChildOfClass("Humanoid") end)
            if hum then
                local hrp = child:FindFirstChild("HumanoidRootPart")
                    or child:FindFirstChild("Torso")
                    or child:FindFirstChild("UpperTorso")
                    or child:FindFirstChild("Head")
                if not hrp then
                    pcall(function() hrp = child:FindFirstChildWhichIsA("BasePart") end)
                end
                if hrp then
                    out[#out + 1] = { model = child, hrp = hrp }
                end
            else
                local cn = child.ClassName
                if cn == "Model" or cn == "Folder" then
                    collectFrom(child, myChar, playerNames, out, depth + 1)
                end
            end
        end
    end
end

local charCache, charStamp = {}, 0
local CHAR_TTL = 0.5

local function getCharacters()
    local now = os.clock()
    if (now - charStamp) < CHAR_TTL then return charCache end
    charStamp = now

    local playerNames = {}
    for _, p in ipairs(Players:GetPlayers()) do
        playerNames[p.Name] = true
    end

    local out = {}
    local folder = workspace:FindFirstChild("Characters")
    if folder then
        collectFrom(folder, LocalPlayer and LocalPlayer.Character, playerNames, out, 0)
    end
    
    local gibs = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Gibs")
    if gibs then
        collectFrom(gibs, LocalPlayer and LocalPlayer.Character, playerNames, out, 0)
    end

    charCache = out
    return out
end

local aimKey = nil

if typeof(UI) == "table" then
    if UI.Unload then pcall(UI.Unload) end
    if UI.Clear then pcall(UI.Clear) end
end

if typeof(UI) == "table" and UI.AddTab then
    pcall(function()
        UI.AddTab("HAVOC ESP", function(tab)
            local sec = tab:Section("AI ESP", "Left", nil, 260)
            sec:Toggle("havoc_esp_enabled",  "Enabled",     DEF.havoc_esp_enabled)
            sec:Toggle("havoc_esp_box",      "Box",         DEF.havoc_esp_box)
            sec:Toggle("havoc_esp_name",     "Name",        DEF.havoc_esp_name)
            sec:Toggle("havoc_esp_distance", "Distance",    DEF.havoc_esp_distance)
            sec:Toggle("havoc_esp_tracer",   "Tracers",     DEF.havoc_esp_tracer)
            sec:SliderInt("havoc_esp_dist_max",    "Max Distance",      50, 3000, DEF.havoc_esp_dist_max)
            sec:SliderInt("havoc_esp_update_rate", "Update Rate (fps)",  5,   60, DEF.havoc_esp_update_rate)
            sec:ColorPicker("havoc_esp_boxcol", "Box Color", 255 / 255, 80 / 255, 80 / 255)

            local aim = tab:Section("Aimbot", "Left", nil, 260)
            aim:Toggle("aim_enabled", "Enabled", AIM_DEF.enabled)
            aimKey = aim:Keybind("aim_key", AIM_DEF.key, AIM_DEF.key_type)
            if aimKey and aimKey.AddToHotkey then
                pcall(function() aimKey:AddToHotkey("Aimbot", "aim_enabled") end)
            end
            aim:SliderInt("aim_fov", "Field of View (deg)", 1, 360, AIM_DEF.fov)
            aim:SliderFloat("aim_smooth", "Smoothing", 1.0, 30.0, AIM_DEF.smooth, "%.1f")
            aim:SliderInt("aim_dist_max", "Max Aim Range", 50, 3000, AIM_DEF.dist_max)

            local vis = tab:Section("Visuals", "Right", nil, 260)
            vis:Toggle("havoc_nofog", "No Fog", DEF.havoc_nofog)
        end)
    end)
end

local espItems = {}
local snap = { box = true, name = true, dist = true, tracer = false, boxCol = BOX_COL_DEF }
local lastBuild = 0

local function rebuildItems()
    snap.box    = uiGet("havoc_esp_box",      DEF.havoc_esp_box)
    snap.name   = uiGet("havoc_esp_name",     DEF.havoc_esp_name)
    snap.dist   = uiGet("havoc_esp_distance", DEF.havoc_esp_distance)
    snap.tracer = uiGet("havoc_esp_tracer",   DEF.havoc_esp_tracer)
    snap.boxCol = uiColor("havoc_esp_boxcol", BOX_COL_DEF)

    local camP    = getEyePos()
    local maxDist = uiGet("havoc_esp_dist_max", DEF.havoc_esp_dist_max)

    local out = {}
    for _, e in ipairs(getCharacters()) do
        local ok, rootPos = pcall(function() return e.hrp.Position end)
        if ok and rootPos then
            local d = camP and (camP - rootPos).Magnitude or nil
            if not (d and d > maxDist) then
                out[#out + 1] = {
                    part     = e.hrp,
                    name     = e.model.Name,
                    distText = d and string.format("%dm", math.floor(d)) or nil,
                }
                if #out >= MAX_SLOTS then break end
            end
        end
    end
    espItems = out
end

local function getBestAimTarget()
    local cam = Camera
    if not cam then return nil end
    local camPos = cam.CFrame.Position
    local lookDir = cam.CFrame.LookVector

    local maxDist = uiGet("aim_dist_max", 1500)
    local fovDeg = uiGet("aim_fov", 180)

    local best = nil
    local bestAngle = 1e9

    for _, it in ipairs(espItems) do
        local basePart = it.part
        if basePart and basePart.Parent then
            local targetPart = basePart.Parent:FindFirstChild("Head") 
                or basePart.Parent:FindFirstChild("UpperTorso") 
                or basePart.Parent:FindFirstChild("Torso")
                or basePart
            
            local ok, pos = pcall(function() return targetPart.Position end)
            if ok and pos then
                local dist = (camPos - pos).Magnitude
                if dist <= maxDist then
                    local dirToTarget = (pos - camPos).Unit
                    local dot = lookDir:Dot(dirToTarget)
                    local clamped = math.max(-1, math.min(1, dot))
                    local angle = math.deg(math.acos(clamped))
                    if angle <= fovDeg then
                        if angle < bestAngle then
                            bestAngle = angle
                            best = {
                                position = pos,
                                part = targetPart,
                                name = it.name,
                                distance = dist,
                                angle = angle
                            }
                        end
                    end
                end
            end
        end
    end
    return best
end

local function aimStep(delta, smooth, maxStep)
    local value = delta / smooth
    if value > maxStep then value = maxStep elseif value < -maxStep then value = -maxStep end

    if math.abs(delta) > 1 and math.abs(value) < 1 then
        if delta > 0 then return 1 end
        return -1
    end

    if value >= 0 then return math.floor(value + 0.5) else return math.ceil(value - 0.5) end
end

local function aimAtTarget(target, smoothVal)
    if not target or not target.position then return end
    local screenPos, onScreen = worldToScreen(target.position)
    if not onScreen then return end

    local vp = Camera.ViewportSize
    local inset = GuiService:GetGuiInset()
    local center = Vector2.new(vp.X / 2, (vp.Y / 2) + inset.Y)

    local dx = screenPos.X - center.X
    local dy = screenPos.Y - center.Y

    if mousemoverel then
        local moveX = aimStep(dx, smoothVal, 35)
        local moveY = aimStep(dy, smoothVal, 35)

        if moveX ~= 0 or moveY ~= 0 then
            pcall(function() mousemoverel(moveX, moveY) end)
        end
    end
end

-- Fixes the explicit nil Enum error by utilizing native context-aware hooks
local function checkHotkeyActive()
    local key = uiGet("aim_key", AIM_DEF.key)
    if type(key) == "table" and key.Value ~= nil then key = key.Value end

    if key == 0x01 then
        return (ismouse1pressed and ismouse1pressed())
    elseif key == 0x02 then
        return (ismouse2pressed and ismouse2pressed())
    elseif iskeypressed then
        local success, down = pcall(function() return iskeypressed(key) end)
        if success then return down end
    end
    return (ismouse2pressed and ismouse2pressed())
end

local lastDrawn = 0
local dbgClock  = os.clock()

renderConn = RunService.RenderStepped:Connect(function()
    if not running then return end

    local noFog = uiGet("havoc_nofog", DEF.havoc_nofog)
    if noFog then
        applyNoFog()
    elseif lastNoFog then
        restoreFog()
    end
    lastNoFog = noFog

    if not uiGet("havoc_esp_enabled", DEF.havoc_esp_enabled) then
        for i = 1, lastDrawn do hideSlot(slots[i]) end
        lastDrawn = 0
        return
    end

    local now  = os.clock()
    local rate = uiGet("havoc_esp_update_rate", DEF.havoc_esp_update_rate)
    if (now - lastBuild) >= (1 / math.max(1, rate)) then
        lastBuild = now
        rebuildItems()
    end

    local vp   = Camera.ViewportSize
    local slot = 0

    for _, it in ipairs(espItems) do
        if slot >= MAX_SLOTS then break end

        local ok, rootPos = pcall(function() return it.part.Position end)
        if ok and rootPos then
            local topPos, topOn = worldToScreen(rootPos + V3_HEAD)
            local botPos, botOn = worldToScreen(rootPos - V3_FOOT)
            if topOn and botOn then
                slot = slot + 1
                local s = slots[slot]
                hideSlot(s)

                local height = math.abs(botPos.Y - topPos.Y)
                if height < 1 then height = 1 end
                local width = height * 0.5
                local boxX  = topPos.X - width * 0.5
                local boxY  = topPos.Y

                if snap.box then
                    drawBox(s, boxX, boxY, width, height, snap.boxCol)
                end

                if snap.name then
                    s.name.Text     = it.name
                    s.name.Position = Vector2.new(topPos.X, boxY - TEXT_SIZE - 2)
                    s.name.Color    = NAME_COL
                    s.name.Visible  = true
                end

                if snap.dist and it.distText then
                    s.dist.Text     = it.distText
                    s.dist.Position = Vector2.new(topPos.X, boxY + height + 2)
                    s.dist.Color    = DIST_COL
                    s.dist.Visible  = true
                end

                if snap.tracer then
                    s.tracer.From    = Vector2.new(vp.X * 0.5, vp.Y)
                    s.tracer.To      = Vector2.new(topPos.X, boxY + height)
                    s.tracer.Color   = TRACER_COL
                    s.tracer.Visible = true
                end
            end
        end
    end

    for i = slot + 1, lastDrawn do hideSlot(slots[i]) end
    lastDrawn = slot

    local aimEnabled = uiGet("aim_enabled", false)
    local keyActive = checkHotkeyActive()
    local isForeground = (isrbxactive == nil) or isrbxactive()

    if aimEnabled and keyActive and isForeground then
        local smoothVal = uiGet("aim_smooth", 6.0)
        if type(smoothVal) ~= "number" then smoothVal = 6.0 end
        
        local target = getBestAimTarget()
        if target then
            aimAtTarget(target, math.max(1, smoothVal))
        end
    end
end)

print("[HAVOC AI ESP] Aimbot hotkey and step math synced successfully.")
