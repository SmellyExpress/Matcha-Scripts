local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Camera      = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local TEXT_SIZE = 13
local HEAD_OFFSET = 2.6
local FOOT_OFFSET = 3.2

local ENTITY_SCAN_INTERVAL = 1.0
local PLAYER_MATCH_DIST = 5.0
local FOLDER_POLL_INTERVAL = 0.25

-- ============================================================================
-- Loot Configuration
-- ============================================================================

local LOOT_TYPES = {
    { key = "loot_medium_crate", match = "Medium Wooden Crate", display = "Medium Wooden Crate", color = { 0.62, 0.44, 0.24, 1.0 } },
    { key = "loot_complex_crate", match = "Complex Crate", display = "Complex Crate", color = { 0.55, 0.55, 0.6, 1.0 } },
    { key = "loot_military_crate", match = "Military Crate", display = "Military Crate", color = { 0.3, 0.55, 0.3, 1.0 } },
    { key = "loot_wooden_crate", match = "Wooden Crate", display = "Wooden Crate", color = { 0.55, 0.4, 0.25, 1.0 } },
    { key = "loot_weapon_locker", match = "Weapon Locker", display = "Weapon Locker", color = { 1.0, 0.4, 0.2, 1.0 } },
    { key = "loot_weapon_box", match = "Weapon Box", display = "Weapon Box", color = { 1.0, 0.35, 0.25, 1.0 } },
    { key = "loot_medical_box", match = "Medical Box", display = "Medical Box", color = { 0.9, 0.2, 0.2, 1.0 } },
}
local LOOT_FALLBACK = { key = "loot_other", display = "Other Loot", color = { 0.8, 0.8, 0.8, 1.0 } }
local BODY_BAG_TYPE = { key = "loot_body_bag", display = "Body Bag", color = { 0.35, 0.35, 0.35, 1.0 } }

local function name_matches(name, pattern)
    if type(pattern) == "table" then
        for i = 1, #pattern do
            if string.find(name, pattern[i], 1, true) then return true end
        end
        return false
    end
    return string.find(name, pattern, 1, true) ~= nil
end

local function categorize_loot(name)
    for i = 1, #LOOT_TYPES do
        local entry = LOOT_TYPES[i]
        if name_matches(name, entry.match) then
            return entry
        end
    end
    return LOOT_FALLBACK
end

-- ============================================================================
-- Bone Configuration
-- ============================================================================

local BONE_NAMES = {
    "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
    "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local SKELETON_R15 = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "UpperTorso", "RightUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" }, { "RightUpperArm", "RightLowerArm" },
    { "LeftLowerArm", "LeftHand" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LowerTorso", "RightUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" }, { "RightUpperLeg", "RightLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" }, { "RightLowerLeg", "RightFoot" },
}
local SKELETON_R6 = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

-- ============================================================================
-- Entity Collection
-- ============================================================================

local function collect_body_parts(model)
    local parts = {}
    local sizes = {}
    local ok, children = pcall(function() return model:GetChildren() end)
    if not ok or not children then return parts, sizes end

    for i = 1, #children do
        local child = children[i]
        local cls = child.ClassName
        if cls == "Part" or cls == "MeshPart" then
            for j = 1, #BONE_NAMES do
                if child.Name == BONE_NAMES[j] then
                    parts[child.Name] = child
                    local ok_size, size = pcall(function() return child.Size end)
                    sizes[child.Name] = ok_size and size or nil
                    break
                end
            end
        end
    end

    return parts, sizes
end

local function is_player_character(model, root, players)
    for i = 1, #players do
        local char = players[i].Character
        if char and char == model then return true end
    end

    local ok, pos = pcall(function() return root.Position end)
    if not ok or not pos then return false end

    for i = 1, #players do
        local ok_ppos, ppos = pcall(function() return players[i].Position end)
        if ok_ppos and ppos and (pos - ppos).Magnitude < PLAYER_MATCH_DIST then return true end
    end

    if LocalPlayer then
        local ok_char, char = pcall(function() return LocalPlayer.Character end)
        if ok_char and char and char == model then return true end

        local ok_lp_pos, lp_pos = pcall(function() return LocalPlayer.Position end)
        if ok_lp_pos and lp_pos and (pos - lp_pos).Magnitude < PLAYER_MATCH_DIST then return true end
    end

    return false
end

local entity_by_model = {}

local function get_or_create_entity(model, root, humanoid)
    local entry = entity_by_model[model]
    if entry then return entry end

    local parts, part_sizes = collect_body_parts(model)
    entry = { model = model, root = root, humanoid = humanoid, parts = parts, part_size = part_sizes }
    entity_by_model[model] = entry
    return entry
end

local function collect_entities(container, players, out, depth)
    if depth > 6 then return end

    local ok, children = pcall(function() return container:GetChildren() end)
    if not ok or not children then return end

    for i = 1, #children do
        local child = children[i]
        local cls = child.ClassName

        if cls == "Model" or cls == "WorldModel" then
            local hum = child:FindFirstChildOfClass("Humanoid")
            if hum then
                local root = child:FindFirstChild("HumanoidRootPart")
                    or child:FindFirstChild("Torso")
                    or child:FindFirstChild("UpperTorso")
                    or child:FindFirstChild("Head")
                    or child:FindFirstChildWhichIsA("BasePart")

                if root and not is_player_character(child, root, players) then
                    out[#out + 1] = get_or_create_entity(child, root, hum)
                end
            else
                collect_entities(child, players, out, depth + 1)
            end
        elseif cls == "Folder" then
            collect_entities(child, players, out, depth + 1)
        end
    end
end

local characters_folder = nil

local function get_entity_root()
    if not characters_folder then
        characters_folder = game.Workspace:FindFirstChild("Characters")
    end
    return characters_folder
end

local entity_cache = {}
local entity_cache_stamp = 0

local function refresh_entity_cache()
    local now = os.clock()
    local interval = characters_folder and ENTITY_SCAN_INTERVAL or FOLDER_POLL_INTERVAL
    if (now - entity_cache_stamp) < interval then return end
    entity_cache_stamp = now

    local root = get_entity_root()
    if not root then return end

    local players = Players:GetPlayers()
    local out = {}
    collect_entities(root, players, out, 0)

    local new_by_model = {}
    for i = 1, #out do
        new_by_model[out[i].model] = out[i]
    end
    entity_by_model = new_by_model
    entity_cache = out
end

-- ============================================================================
-- Loot Collection
-- ============================================================================

local function get_loot_info(model)
    local data = model:FindFirstChild("data")
    if not data or data.ClassName ~= "Configuration" then return nil end

    local is_open = data:FindFirstChild("isOpen")
    local is_locked = data:FindFirstChild("isLocked")
    if not (is_open and is_locked) then return nil end

    return is_open, is_locked
end

local loot_by_model = {}

local function get_or_create_loot(model, root, category, is_open_inst, is_locked_inst)
    local entry = loot_by_model[model]
    if entry then return entry end

    local ok_pos, pos = pcall(function() return root.Position end)
    entry = {
        model = model,
        root = root,
        pos = ok_pos and pos or nil,
        is_open_inst = is_open_inst,
        is_locked_inst = is_locked_inst,
        is_open = nil,
        is_locked = nil,
        category = category,
    }
    loot_by_model[model] = entry
    return entry
end

local function collect_loot(container, out, depth)
    if depth > 8 then return end

    local ok, children = pcall(function() return container:GetChildren() end)
    if not ok or not children then return end

    for i = 1, #children do
        local child = children[i]
        local cls = child.ClassName

        if cls == "Model" then
            local is_open, is_locked = get_loot_info(child)
            if is_open then
                local root = child:FindFirstChildWhichIsA("BasePart")
                if root then
                    out[#out + 1] = get_or_create_loot(child, root, categorize_loot(child.Name), is_open, is_locked)
                end
            else
                collect_loot(child, out, depth + 1)
            end
        elseif cls == "Folder" or cls == "WorldModel" then
            collect_loot(child, out, depth + 1)
        end
    end
end

local buildings_folder = nil

local function get_buildings_folder()
    if not buildings_folder then
        buildings_folder = game.Workspace:FindFirstChild("Buildings")
    end
    return buildings_folder
end

local function collect_body_bags(buildings, out)
    local loots1 = buildings:FindFirstChild("Loots")
    if not loots1 then return end
    local loots2 = loots1:FindFirstChild("Loots")
    if not loots2 then return end
    local characters = loots2:FindFirstChild("Characters")
    if not characters then return end

    local ok, children = pcall(function() return characters:GetChildren() end)
    if not ok or not children then return end

    for i = 1, #children do
        local child = children[i]
        if child.ClassName == "Model" then
            local root = child:FindFirstChildWhichIsA("BasePart")
            if root then
                out[#out + 1] = get_or_create_loot(child, root, BODY_BAG_TYPE, nil, nil)
            end
        end
    end
end

local loot_cache = {}
local loot_cache_stamp = 0

local function refresh_loot_cache()
    local now = os.clock()
    local interval = buildings_folder and 30.0 or FOLDER_POLL_INTERVAL
    if (now - loot_cache_stamp) < interval then return end
    loot_cache_stamp = now

    local out = {}
    local buildings = get_buildings_folder()
    if buildings then
        local ok, children = pcall(function() return buildings:GetChildren() end)
        if ok and children then
            for i = 1, #children do
                local loots = children[i]:FindFirstChild("Loots")
                if loots then
                    collect_loot(loots, out, 0)
                end
            end
        end
        collect_body_bags(buildings, out)
    end

    local new_by_model = {}
    for i = 1, #out do
        new_by_model[out[i].model] = out[i]
    end
    loot_by_model = new_by_model
    loot_cache = out
end

local loot_live_cursor = 1

local function refresh_loot_live()
    local n = #loot_cache
    if n == 0 then return end

    if loot_live_cursor > n then loot_live_cursor = 1 end

    local remaining = math.min(60, n)
    while remaining > 0 do
        local loot = loot_cache[loot_live_cursor]
        if loot.is_open_inst then
            local ok, is_open_val, is_locked_val = pcall(function()
                return loot.is_open_inst.Value, loot.is_locked_inst.Value
            end)
            if ok then
                loot.is_open = is_open_val
                loot.is_locked = is_locked_val
            end
        end

        loot_live_cursor = loot_live_cursor + 1
        if loot_live_cursor > n then loot_live_cursor = 1 end
        remaining = remaining - 1
    end
end

-- ============================================================================
-- Aimbot
-- ============================================================================

local function get_aim_part(ent, bone_idx)
    if bone_idx == 0 then
        return ent.parts["Head"] or ent.root
    else
        return ent.parts["Torso"] or ent.parts["UpperTorso"] or ent.root
    end
end

local function evaluate_candidate(ent, bone_idx, cam_pos, max_dist)
    local health = ent.humanoid.Health
    if not (health and health > 0) then return nil end

    local part = get_aim_part(ent, bone_idx)
    if not part then return nil end

    local pos = part.Position
    if not pos then return nil end

    local dist = (cam_pos - pos).Magnitude
    if max_dist > 0 and dist > max_dist then return nil end

    return pos, dist
end

local aimbot_prev_target = nil
local aimbot_locked_ent = nil
local aimbot_next_acquire = 0
local aimbot_draw_state = { scx = nil, scy = nil, fov = 150, draw_fov = false, active = false, tx = 0, ty = 0 }

local function aimbot_tick()
    if not UI.GetValue("havoc_aimbot_enabled") then
        aimbot_prev_target = nil
        aimbot_locked_ent = nil
        aimbot_draw_state.scx = nil
        aimbot_draw_state.active = false
        return
    end

    local settings = {
        fov = UI.GetValue("havoc_aimbot_fov"),
        draw_fov = UI.GetValue("havoc_aimbot_draw_fov"),
        bone_idx = UI.GetValue("havoc_aimbot_bone"),
        target_type = UI.GetValue("havoc_aimbot_target_type"),
        max_dist = UI.GetValue("havoc_aimbot_max_distance"),
    }

    local vp = Camera.ViewportSize
    local scx = vp.X * 0.5
    local scy = vp.Y * 0.5

    aimbot_draw_state.scx = scx
    aimbot_draw_state.scy = scy
    aimbot_draw_state.fov = settings.fov
    aimbot_draw_state.draw_fov = settings.draw_fov

    local now = os.clock()
    local cam_pos = Camera.Position

    local best_pos, best_model = nil, nil

    if aimbot_locked_ent and now < aimbot_next_acquire then
        local pos = evaluate_candidate(aimbot_locked_ent, settings.bone_idx, cam_pos, settings.max_dist)
        if pos then
            local sx, sy, svis = WorldToScreen(pos)
            if svis then
                best_pos = pos
                best_model = aimbot_locked_ent.model
            end
        end
    end

    if not best_pos then
        aimbot_next_acquire = now + 0.05

        local best_score = math.huge
        local best_ent = nil

        for i = 1, #entity_cache do
            local ent = entity_cache[i]
            local pos, dist = evaluate_candidate(ent, settings.bone_idx, cam_pos, settings.max_dist)
            if pos then
                local sx, sy, svis = WorldToScreen(pos)
                if svis then
                    local dx, dy = sx - scx, sy - scy
                    local px_dist = math.sqrt(dx * dx + dy * dy)
                    local is_incumbent = ent.model == aimbot_prev_target
                    local effective_fov = is_incumbent and (settings.fov * 1.15) or settings.fov
                    if px_dist <= effective_fov then
                        local score = (settings.target_type == 1) and dist or px_dist
                        local effective_score = is_incumbent and (score * 0.75) or score
                        if effective_score < best_score then
                            best_score = effective_score
                            best_pos = pos
                            best_model = ent.model
                            best_ent = ent
                        end
                    end
                end
            end
        end

        aimbot_locked_ent = best_ent
    end

    aimbot_prev_target = best_model

    if best_pos then
        local fx, fy, fvis = WorldToScreen(best_pos)
        if fvis then
            aimbot_draw_state.active = true
            aimbot_draw_state.tx = fx
            aimbot_draw_state.ty = fy
        else
            aimbot_draw_state.active = false
        end
    else
        aimbot_draw_state.active = false
    end
end

-- ============================================================================
-- Drawing
-- ============================================================================

local function draw_aimbot_visuals()
    if not UI.GetValue("havoc_aimbot_enabled") then return end
    if aimbot_draw_state.scx == nil then return end

    if aimbot_draw_state.draw_fov then
        draw.Circle(aimbot_draw_state.scx, aimbot_draw_state.scy, aimbot_draw_state.fov,
            { 1.0, 1.0, 1.0, 1.0 }, 48)
    end

    if aimbot_draw_state.active and UI.GetValue("havoc_aimbot_target_line") then
        draw.Line(aimbot_draw_state.scx, aimbot_draw_state.scy, aimbot_draw_state.tx, aimbot_draw_state.ty,
            { 1.0, 0.3, 0.3, 1.0 })
    end
end

local function get_held_item_name(ent)
    local model_children = ent.model:GetChildren()
    if model_children then
        for i = 1, #model_children do
            local child = model_children[i]
            if child.ClassName == "Tool" then
                return child.Name
            end
        end
    end

    for _, part in pairs(ent.parts) do
        local children = part:GetChildren()
        if children then
            for i = 1, #children do
                local child = children[i]
                if child.ClassName == "Model" and child:FindFirstChild("Handle") then
                    return child.Name
                end
            end
        end
    end

    return nil
end

local function draw_entity_skeleton(part_pos, color)
    local bone_list = part_pos["UpperTorso"] and SKELETON_R15 or SKELETON_R6

    for i = 1, #bone_list do
        local pos1 = part_pos[bone_list[i][1]]
        local pos2 = part_pos[bone_list[i][2]]
        if pos1 and pos2 then
            local x1, y1, vis1 = WorldToScreen(pos1)
            local x2, y2, vis2 = WorldToScreen(pos2)
            if vis1 and vis2 then
                draw.Line(x1, y1, x2, y2, { 0, 0, 0, 0.78 }, 3.0)
                draw.Line(x1, y1, x2, y2, color, 1.5)
            end
        end
    end
end

local function get_entity_bounds_fallback(root_pos)
    local top_x, top_y, top_ok = WorldToScreen(root_pos + Vector3.new(0, HEAD_OFFSET, 0))
    local bot_x, bot_y, bot_ok = WorldToScreen(root_pos - Vector3.new(0, FOOT_OFFSET, 0))

    if not (top_ok and bot_ok) then
        return { valid = false }
    end

    local height = math.abs(bot_y - top_y)
    if height < 1 then height = 1 end
    local width = height * 0.5

    return { x = top_x - width * 0.5, y = top_y, w = width, h = height, valid = true }
end

local function draw_esp(bounds, name_str, dist_val, opts)
    if not bounds.valid then return end

    if opts.box then
        draw.CornerBox(bounds.x, bounds.y, bounds.w, bounds.h, opts.box_color)
    end

    if opts.health_bar then
        draw.HealthBar(bounds.x, bounds.y, bounds.h, opts.health, opts.max_health)
    end

    if opts.name then
        local tw = draw.GetTextSize(name_str, TEXT_SIZE)
        draw.Text(bounds.x + (bounds.w - tw) * 0.5, bounds.y - TEXT_SIZE - 4, name_str, opts.name_color, TEXT_SIZE)
    end

    local below_y = bounds.y + bounds.h + 4

    if opts.held_item then
        local tw = draw.GetTextSize(opts.held_item, TEXT_SIZE)
        draw.Text(bounds.x + (bounds.w - tw) * 0.5, below_y, opts.held_item, opts.held_item_color, TEXT_SIZE)
        below_y = below_y + TEXT_SIZE + 2
    end

    if opts.dist then
        local dist_str = string.format("%dm", math.floor(dist_val))
        local tw = draw.GetTextSize(dist_str, TEXT_SIZE)
        draw.Text(bounds.x + (bounds.w - tw) * 0.5, below_y, dist_str, opts.dist_color, TEXT_SIZE)
    end
end

local function run_entity_visuals(cam_pos)
    if not UI.GetValue("havoc_entity_enabled") then return end

    local opts = {
        box = UI.GetValue("havoc_entity_box"),
        box_color = { 1.0, 0.31, 0.31, 1.0 },
        name = UI.GetValue("havoc_entity_name"),
        name_color = { 0.92, 0.92, 0.92, 1.0 },
        dist = UI.GetValue("havoc_entity_distance"),
        dist_color = { 0.67, 0.67, 0.67, 1.0 },
        health_bar = UI.GetValue("havoc_entity_health_bar"),
        health_text = UI.GetValue("havoc_entity_health_text"),
        health_text_color = { 0.3, 1.0, 0.4, 1.0 },
    }

    local skeleton_on = UI.GetValue("havoc_entity_skeleton")
    local skeleton_color = { 1.0, 1.0, 1.0, 1.0 }
    local held_item_on = UI.GetValue("havoc_entity_held_item")
    local held_item_color = { 1.0, 0.85, 0.4, 1.0 }
    local hide_dead = UI.GetValue("havoc_entity_hide_dead")
    local max_dist = UI.GetValue("havoc_entity_max_distance")

    for i = 1, #entity_cache do
        local ent = entity_cache[i]
        local health = ent.humanoid.Health or 0
        local max_health = ent.humanoid.MaxHealth or 100

        if not (hide_dead and health <= 0) then
            local root_pos = ent.root.Position
            if root_pos then
                local dist = (cam_pos - root_pos).Magnitude
                if dist <= max_dist then
                    local part_pos = {}
                    for name, part in pairs(ent.parts) do
                        local pos = part.Position
                        if pos then part_pos[name] = pos end
                    end

                    if skeleton_on then draw_entity_skeleton(part_pos, skeleton_color) end

                    local bounds = get_entity_bounds_fallback(root_pos)
                    if bounds.valid then
                        local name_str = ent.model.Name
                        if opts.health_text then
                            name_str = name_str .. string.format(" [%d/%d]", math.max(0, math.floor(health)), math.floor(max_health))
                        end

                        opts.health = health
                        opts.max_health = max_health
                        opts.held_item = held_item_on and get_held_item_name(ent) or nil
                        opts.held_item_color = held_item_color

                        draw_esp(bounds, name_str, dist, opts)
                    end
                end
            end
        end
    end
end

local function loot_passes_filter(filter_idx, is_open_val, is_locked_val)
    if filter_idx == 1 then return is_locked_val == true end
    if filter_idx == 2 then return is_locked_val ~= true end
    if filter_idx == 3 then return is_open_val == true end
    if filter_idx == 4 then return is_open_val ~= true end
    return true
end

local LOOT_MARKER_RADIUS = 3
local LOOT_MARKER_GAP = 8

local function draw_loot_label(x, y, display_name, locked, dist, show_dist, color, dist_pos, show_marker)
    local name_text = display_name
    if locked then
        name_text = name_text .. " [Locked]"
    end

    local dist_text = nil
    if show_dist then
        dist_text = string.format("%dm", math.floor(dist))
        if dist_pos == 0 then
            name_text = name_text .. " [" .. dist_text .. "]"
            dist_text = nil
        end
    end

    local name_w = draw.GetTextSize(name_text, TEXT_SIZE)
    local name_x = x - name_w * 0.5
    local name_y = y - TEXT_SIZE * 0.5

    if show_marker then
        draw.CircleFilled(x, name_y - LOOT_MARKER_GAP, LOOT_MARKER_RADIUS, color, 12)
    end

    if dist_text then
        local dist_w = draw.GetTextSize(dist_text, TEXT_SIZE)
        if dist_pos == 1 then
            draw.Text(x - dist_w * 0.5, name_y + TEXT_SIZE + 2, dist_text, color, TEXT_SIZE)
        elseif dist_pos == 2 then
            draw.Text(name_x - dist_w - 4, name_y, dist_text, color, TEXT_SIZE)
        elseif dist_pos == 3 then
            draw.Text(name_x + name_w + 4, name_y, dist_text, color, TEXT_SIZE)
        end
    end

    draw.Text(name_x, name_y, name_text, color, TEXT_SIZE)
end

local function run_loot_visuals(cam_pos)
    if not UI.GetValue("havoc_loot_enabled") then return end

    local show_dist = UI.GetValue("havoc_loot_distance")
    local dist_pos = UI.GetValue("havoc_loot_distance_pos")
    local show_marker = UI.GetValue("havoc_loot_marker")
    local max_dist = UI.GetValue("havoc_loot_max_distance")
    local filter_idx = UI.GetValue("havoc_loot_filter")

    for i = 1, #loot_cache do
        local loot = loot_cache[i]

        if loot.pos and UI.GetValue(loot.category.key) then
            if loot_passes_filter(filter_idx, loot.is_open, loot.is_locked) then
                local dist = (cam_pos - loot.pos).Magnitude
                if dist <= max_dist then
                    local sx, sy, sok = WorldToScreen(loot.pos)
                    if sok then
                        local color = loot.category.color
                        draw_loot_label(sx, sy, loot.category.display, loot.is_locked, dist, show_dist, color,
                            dist_pos, show_marker)
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- UI Setup
-- ============================================================================

if UI and UI.AddTab then
    pcall(function()
        UI.AddTab("HAVOC ESP", function(tab)
            -- Aimbot Section
            local aim_sec = tab:Section("Aimbot", "Left", {"Main", "Visuals"})
            
            if aim_sec.page == 0 then
                aim_sec:Toggle("havoc_aimbot_enabled", "Enable Entity Aimbot", false)
                aim_sec:Combo("havoc_aimbot_bone", "Aimbot Bone", {"Head", "Torso"}, 0)
                aim_sec:Combo("havoc_aimbot_target_type", "Target Type", {"Closest To Crosshair", "Closest Distance"}, 0)
                aim_sec:SliderInt("havoc_aimbot_fov", "FOV", 10, 500, 150)
                aim_sec:SliderInt("havoc_aimbot_max_distance", "Max Distance", 0, 3000, 3000)
            elseif aim_sec.page == 1 then
                aim_sec:Toggle("havoc_aimbot_draw_fov", "Draw FOV Circle", true)
                aim_sec:Toggle("havoc_aimbot_target_line", "Target Line", false)
            end

            -- Entity Visuals Section
            local entity_sec = tab:Section("Entity Visuals", "Right")
            entity_sec:Toggle("havoc_entity_enabled", "Enable Entity Visuals", true)
            entity_sec:Toggle("havoc_entity_box", "Enable Box", true)
            entity_sec:Toggle("havoc_entity_name", "Enable Name", true)
            entity_sec:Toggle("havoc_entity_distance", "Enable Distance", true)
            entity_sec:Toggle("havoc_entity_held_item", "Enable Held Item", true)
            entity_sec:Toggle("havoc_entity_health_bar", "Enable Health Bar", true)
            entity_sec:Toggle("havoc_entity_health_text", "Enable Health Text", true)
            entity_sec:Toggle("havoc_entity_skeleton", "Enable Skeleton", false)
            entity_sec:Toggle("havoc_entity_hide_dead", "Hide Dead Entities", true)
            entity_sec:SliderInt("havoc_entity_max_distance", "Max Render Distance", 0, 3000, 3000)

            -- Loot Section
            local loot_sec = tab:Section("Loot Visuals", "Left", nil, 400)
            loot_sec:Toggle("havoc_loot_enabled", "Enable Loot Visuals", true)
            for i = 1, #LOOT_TYPES do
                local entry = LOOT_TYPES[i]
                loot_sec:Toggle(entry.key, "Enable " .. entry.display, true)
            end
            loot_sec:Toggle(LOOT_FALLBACK.key, "Enable " .. LOOT_FALLBACK.display, true)
            loot_sec:Toggle(BODY_BAG_TYPE.key, "Enable " .. BODY_BAG_TYPE.display, true)

            -- Loot Options Section
            local loot_opts = tab:Section("Loot Options", "Right")
            loot_opts:Toggle("havoc_loot_distance", "Show Distance", true)
            loot_opts:Combo("havoc_loot_distance_pos", "Distance Position", {"Same Line", "Below Name", "Left Of Name", "Right Of Name"}, 0)
            loot_opts:Toggle("havoc_loot_marker", "Show Position Marker", true)
            loot_opts:Combo("havoc_loot_filter", "Loot Filter", {"Show All", "Show Locked Only", "Show Unlocked Only", "Show Opened Only", "Show Unopened Only"}, 0)
            loot_opts:SliderInt("havoc_loot_max_distance", "Max Render Distance", 0, 5000, 5000)
        end)
    end)
end

-- ============================================================================
-- Main Loop
-- ============================================================================

local aimbot_thread_id = nil

local function main_loop()
    refresh_entity_cache()
    refresh_loot_cache()
    refresh_loot_live()

    local cam_pos = Camera.Position

    run_entity_visuals(cam_pos)
    run_loot_visuals(cam_pos)
    draw_aimbot_visuals()

    local aimbot_enabled = UI.GetValue("havoc_aimbot_enabled")
    if aimbot_enabled and not aimbot_thread_id then
        aimbot_thread_id = RunService.RenderStepped:Connect(aimbot_tick)
    elseif not aimbot_enabled and aimbot_thread_id then
        aimbot_thread_id:Disconnect()
        aimbot_thread_id = nil
    end
end

RunService.RenderStepped:Connect(main_loop)

print("[HAVOC ESP + AIMBOT + LOOT] Loaded successfully!")
