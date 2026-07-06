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
    charCache = out
    return out
end

if typeof(UI) == "table" and UI.AddTab then
    pcall(function()
        UI.AddTab("HAVOC ESP", function(tab)
            local sec = tab:Section("AI ESP", "Left", nil, 260)
            sec:Toggle("havoc_esp_enabled",  "Enabled",     DEF.havoc_esp_enabled)
            sec:Toggle("havoc_esp_box",      "Box",         DEF.havoc_esp_box)
            sec:Toggle("havoc_esp_name",     "Name",        DEF.havoc_esp_name)
