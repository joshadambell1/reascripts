--[[
ReaScript name: joshadambell_Envelope LFO Tool.lua
Version: 3.00
Author: joshadambell (very heavily inspired by juliansader/Xenakios original)
Website: https://joshadambell.com
Dependencies: ReaImGui extension
About:
  # LFO Generator for REAPER Envelopes
  
  LFO generator with ReaImGui interface for REAPER automation envelopes.
  Very very heavily inspired by the classic juliansader LFO Tool.
  
  ## Requirements
  - ReaImGui extension (install via ReaPack)
  - REAPER v6.0 or higher
  
  ## Features
  - ReaImGui interface
  - Envelope editing
  - Multiple LFO shapes
  - Auto-apply option
]]

-- ReaImGui setup
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

-- Check for ReaImGui
if not ImGui then
    reaper.MB('ReaImGui extension is required for this script.\n\nInstall it via Extensions → ReaPack → Browse packages', 'Missing Dependency', 0)
    return
end

-- Create ImGui context
local ctx = ImGui.CreateContext('LFO Generator v3.0')

-- Global state
local LFO = {
    -- Core parameters
    rate = 5.0, -- Hz
    amplitude = 0.5,
    center = 0.5,
    phase = 0.0,
    
    -- Slider positions for power curve sliders (0.0-1.0) - calculated from actual values
    rate_slider_pos = nil, -- Will be calculated from rate value on first use
    amplitude_slider_pos = nil, -- Will be calculated from amplitude value on first use
    
    -- Randomness parameters
    rateRandomness = 0.0,
    amplitudeRandomness = 0.0,
    centerRandomness = 0.0,
    
    -- Resolution parameter
    resolution = 500, -- Points per second
    
    -- Bezier tension parameter
    bezierTension = 0.5, -- 0.0 = linear, 1.0 = maximum curve
    
    -- Shape selection
    currentShape = 1,
    
    -- Envelope data (0.0-1.0 multipliers)
    rateEnvelope = {{0.0, 1.0}, {1.0, 1.0}}, -- 1.0 = 100% of slider value
    amplitudeEnvelope = {{0.0, 1.0}, {1.0, 1.0}}, -- 1.0 = 100% of slider value
    centerEnvelope = {{0.0, 1.0}, {1.0, 1.0}}, -- 1.0 = 100% of slider value
    
    -- Target envelope info
    targetEnv = nil,
    timeStart = 0,
    timeEnd = 0,
    
    -- GUI state
    showHelp = false,
    autoApply = true, -- Auto apply changes to envelope
    currentEnvelopeEdit = 'rate', -- 'rate', 'amplitude', 'center'
    draggedNode = nil -- For envelope editor mouse interaction
}

-- Shape definitions (simplified from original)
local shapes = {
    "Bézier",
    "Saw Down", 
    "Saw Up",
    "Square",
    "Triangle",
    "Sine-ish"
}

-- Original shape functions (preserved from LFO_Tool.lua)
local phaseStepsDefault = 100

-- Shape function table (simplified versions of originals)
local shape_function = {}

shape_function[1] = function(cnt) -- Bezier
    if cnt % phaseStepsDefault == 0 then return phaseStepsDefault, 1, 5, 1, false end
    if cnt % phaseStepsDefault == phaseStepsDefault/4 then return phaseStepsDefault, 0, 5, -1, false end
    if cnt % phaseStepsDefault == phaseStepsDefault/2 then return phaseStepsDefault, -1, 5, 1, false end
    if cnt % phaseStepsDefault == phaseStepsDefault*3/4 then return phaseStepsDefault, 0, 5, -1, false end
    return phaseStepsDefault, false, 5, -1, false
end

shape_function[2] = function(cnt) -- Saw Down
    if cnt % phaseStepsDefault == 0 then return phaseStepsDefault, -1, 0, 1, true end
    return phaseStepsDefault, false, 0, 1, false
end

shape_function[3] = function(cnt) -- Saw Up
    if cnt % phaseStepsDefault == 0 then return phaseStepsDefault, 1, 0, 1, true end
    return phaseStepsDefault, false, 0, 1, false
end

shape_function[4] = function(cnt) -- Square
    if cnt % phaseStepsDefault == 0.25*phaseStepsDefault then return phaseStepsDefault, -1, 1, 1, false end  
    if cnt % phaseStepsDefault == 0.75*phaseStepsDefault then return phaseStepsDefault, 1, 1, 1, false end
    return phaseStepsDefault, false, 1, 1, false
end

shape_function[5] = function(cnt) -- Triangle
    if cnt % phaseStepsDefault == 0 then return phaseStepsDefault, 1, 0, 1, false end
    if cnt % phaseStepsDefault == 0.5*phaseStepsDefault then return phaseStepsDefault, -1, 0, 1, false end
    return phaseStepsDefault, false, 0, 1, false
end

shape_function[6] = function(cnt) -- Sine-ish
    if cnt % phaseStepsDefault == 0 then return phaseStepsDefault, 1, 2, 1, false end
    if cnt % phaseStepsDefault == 0.5*phaseStepsDefault then return phaseStepsDefault, -1, 2, 1, false end
    return phaseStepsDefault, false, 2, 1, false
end

-- Power curve scaling utilities
function value_to_slider_pos(value, min_val, max_val, power)
    -- Convert actual value to slider position (0-1) using power curve
    local normalized = (value - min_val) / (max_val - min_val)
    return normalized ^ (1.0 / power)
end

function slider_pos_to_value(pos, min_val, max_val, power)
    -- Convert slider position (0-1) to actual value using power curve
    local powered = pos ^ power
    return min_val + powered * (max_val - min_val)
end

-- Utility functions
function get_selected_envelope()
    local env = reaper.GetSelectedEnvelope(0)
    if env then
        -- Try to get parent track
        local parent_track = reaper.Envelope_GetParentTrack(env)
        if parent_track then
            local track_number = math.floor(reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER"))
            local retval_track, track_name = reaper.GetSetMediaTrackInfo_String(parent_track, "P_NAME", "", false)
            
            if track_name ~= "" then
                return env, "Track " .. track_number .. ": " .. track_name
            else
                return env, "Track " .. track_number
            end
        else
            -- Could be a take envelope or send envelope
            return env, "Envelope Selected"
        end
    end
    return nil, "NO ENVELOPE SELECTED"
end

function get_time_selection()
    local startTime, endTime = reaper.GetSet_LoopTimeRange(false, false, 0.0, 0.0, false)
    if endTime > startTime then
        return startTime, endTime
    end
    return 0, 0
end

-- GUI Drawing Functions
function draw_menu_bar()
    if ImGui.BeginMenuBar(ctx) then
        if ImGui.MenuItem(ctx, 'Help') then
            LFO.showHelp = not LFO.showHelp
        end
        ImGui.EndMenuBar(ctx)
    end
end

function draw_help_window()
    if LFO.showHelp then
        if ImGui.Begin(ctx, 'LFO Tool Help', true) then
            ImGui.Text(ctx, 'joshadambell - LFO Generator Help')
            ImGui.Separator(ctx)
            
            -- Setup instructions
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Setup:')
            ImGui.Text(ctx, '1. Select an automation envelope in REAPER')
            ImGui.Text(ctx, '2. Set time selection (where LFO will be applied)')
            ImGui.Text(ctx, '3. Adjust parameters and envelopes')
            ImGui.Text(ctx, '4. Choose LFO shape')
            ImGui.Text(ctx, '5. Enable Auto Apply or click "Apply LFO"')
            
            ImGui.Separator(ctx)
            
            -- Parameter controls
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Parameter Controls:')
            ImGui.Text(ctx, 'Rate: LFO frequency (0.01-50.0 Hz)')
            ImGui.Text(ctx, 'Amplitude: LFO intensity (0.0-2.0)')
            ImGui.Text(ctx, 'Center: Oscillation center point (0.0-1.0)')
            ImGui.Text(ctx, 'Phase: Starting phase offset (0.0-1.0)')
            ImGui.Text(ctx, 'Randomness: Add variation to each parameter')
            ImGui.Text(ctx, 'Resolution: Points per second (20-2000)')
            ImGui.Text(ctx, 'Bezier Tension: Curve smoothing (Bezier shape only)')
            
            ImGui.Separator(ctx)
            
            -- Envelope editors
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Envelope Editors (0.0-2.0 Multipliers):')
            ImGui.TextColored(ctx, 0x952E2B7F, '• Rate Multiplier:') 
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, ' Modulates frequency over time')
            ImGui.TextColored(ctx, 0x66B2007F, '• Amplitude Multiplier:')
            ImGui.SameLine(ctx) 
            ImGui.Text(ctx, ' Modulates intensity over time')
            ImGui.TextColored(ctx, 0x0091B27F, '• Center Multiplier:')
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, ' Modulates center point over time')
            
            ImGui.Separator(ctx)
            
            -- Mouse controls
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Envelope Editor Controls:')
            ImGui.Text(ctx, '• Left-click: Add node or drag existing')
            ImGui.Text(ctx, '• Shift+left-click+drag: Draw multiple points quickly')
            ImGui.Text(ctx, '• Right-click: Delete single node')
            ImGui.Text(ctx, '• Shift+right-click+drag: Delete multiple points')
            ImGui.Text(ctx, '• Hover over node: View time/value tooltip')
            ImGui.Text(ctx, '• First and last nodes are fixed at timeline edges')
            
            ImGui.Separator(ctx)
            
            -- Multiplier explanation
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Multiplier Values:')
            ImGui.Text(ctx, '0.0 = 0% of slider value (parameter disabled)')
            ImGui.Text(ctx, '1.0 = 100% of slider value (default, no change)')
            ImGui.Text(ctx, '2.0 = 200% of slider value (double the setting)')
            
            ImGui.Separator(ctx)
            
            -- Features
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Features:')
            ImGui.Text(ctx, '• Auto Apply: Real-time LFO updates')
            ImGui.Text(ctx, '• Color-coded parameters for easy identification')
            ImGui.Text(ctx, '• 6 LFO shapes: Bezier, Saw Down/Up, Square, Triangle, Sine')
            ImGui.Text(ctx, '• Undo support: Ctrl+Z to revert changes')
            ImGui.Text(ctx, '• Reset: Restore all parameters to defaults')
            
            if ImGui.Button(ctx, 'Close') then
                LFO.showHelp = false
            end
        end
        ImGui.End(ctx)
    end
end

function draw_target_info()
    -- Just handle the envelope and time selection logic without displaying envelope info
    local env, envName = get_selected_envelope()
    LFO.targetEnv = env
    
    -- Time selection info
    local startTime, endTime = get_time_selection()
    if endTime > startTime then
        ImGui.Text(ctx, string.format('Time selection: %.3f - %.3f sec', startTime, endTime))
        LFO.timeStart, LFO.timeEnd = startTime, endTime
    else
        ImGui.TextColored(ctx, 0xFFFFFF00, 'No time selection')
        LFO.timeStart, LFO.timeEnd = 0, 0
    end
end

function draw_parameters()
    ImGui.SeparatorText(ctx, 'LFO Parameters')
    
    -- Calculate slider width
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local slider_width = math.max(200, content_width - 130) -- Leave 130px padding for labels, minimum 200px
    
    -- Define background colors for parameter groups
    local rate_bg_color = 0x952E2B7F     -- Deep red background (semi-transparent)
    local amplitude_bg_color = 0x66B2007F  -- Deep green background (semi-transparent)
    local center_bg_color = 0x0091B27F    -- Deep blue background (semi-transparent)
    
    -- Rate parameters
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Rate')
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, rate_bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, rate_bg_color | 0x22000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, rate_bg_color | 0x44000000)
    local rate_changed
    -- Power curve for Rate slider (power = 1.8 for gentler logarithmic feel)
    local rate_power = 1.8
    local rate_min, rate_max = 0.01, 50.0
    
    -- Initialize slider position if needed
    if not LFO.rate_slider_pos then
        LFO.rate_slider_pos = value_to_slider_pos(LFO.rate, rate_min, rate_max, rate_power)
    end
    
    rate_changed, LFO.rate_slider_pos = ImGui.SliderDouble(ctx, 'Rate (Hz)', LFO.rate_slider_pos, 0.0, 1.0, string.format('%.2f Hz', LFO.rate))
    
    if rate_changed then
        LFO.rate = slider_pos_to_value(LFO.rate_slider_pos, rate_min, rate_max, rate_power)
    end
    ImGui.PopStyleColor(ctx, 3)
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, rate_bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, rate_bg_color | 0x22000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, rate_bg_color | 0x44000000)
    local rate_rand_changed
    rate_rand_changed, LFO.rateRandomness = ImGui.SliderDouble(ctx, 'Rate Randomness', LFO.rateRandomness, 0.0, 1.0, '%.3f')
    ImGui.PopStyleColor(ctx, 3)
    
    -- Amplitude parameters
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Amplitude')
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, amplitude_bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, amplitude_bg_color | 0x22000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, amplitude_bg_color | 0x44000000)
    local amplitude_changed
    -- Power curve for Amplitude slider (power = 1.8 for gentler logarithmic feel)
    local amplitude_power = 1.8
    local amplitude_min, amplitude_max = 0.0, 2.0
    
    -- Initialize slider position if needed
    if not LFO.amplitude_slider_pos then
        LFO.amplitude_slider_pos = value_to_slider_pos(LFO.amplitude, amplitude_min, amplitude_max, amplitude_power)
    end
    
    amplitude_changed, LFO.amplitude_slider_pos = ImGui.SliderDouble(ctx, 'Amplitude', LFO.amplitude_slider_pos, 0.0, 1.0, string.format('%.3f', LFO.amplitude))
    
    if amplitude_changed then
        LFO.amplitude = slider_pos_to_value(LFO.amplitude_slider_pos, amplitude_min, amplitude_max, amplitude_power)
    end
    ImGui.PopStyleColor(ctx, 3)
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, amplitude_bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, amplitude_bg_color | 0x22000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, amplitude_bg_color | 0x44000000)
    local amp_rand_changed
    amp_rand_changed, LFO.amplitudeRandomness = ImGui.SliderDouble(ctx, 'Amplitude Randomness', LFO.amplitudeRandomness, 0.0, 1.0, '%.3f')
    ImGui.PopStyleColor(ctx, 3)
    
    -- Center parameters
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Center')
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, center_bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, center_bg_color | 0x22000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, center_bg_color | 0x44000000)
    local center_changed
    center_changed, LFO.center = ImGui.SliderDouble(ctx, 'Center', LFO.center, 0.0, 1.0, '%.3f')
    ImGui.PopStyleColor(ctx, 3)
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, center_bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, center_bg_color | 0x22000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, center_bg_color | 0x44000000)
    local center_rand_changed
    center_rand_changed, LFO.centerRandomness = ImGui.SliderDouble(ctx, 'Center Randomness', LFO.centerRandomness, 0.0, 1.0, '%.3f')
    ImGui.PopStyleColor(ctx, 3)
    
    -- Phase parameter (keep default color)
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Phase')
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    local phase_changed
    phase_changed, LFO.phase = ImGui.SliderDouble(ctx, 'Phase', LFO.phase, 0.0, 1.0, '%.3f')
    
    -- Resolution parameter
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Resolution')
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    local resolution_changed
    resolution_changed, LFO.resolution = ImGui.SliderInt(ctx, 'Points per Second', LFO.resolution, 20, 2000, '%d pts/sec')
    
    -- Bezier tension parameter (only show when Bezier shape is selected)
    local bezier_changed = false
    if LFO.currentShape == 1 then -- Bezier shape
        ImGui.Separator(ctx)
        ImGui.Text(ctx, 'Bezier Shape')
        
        ImGui.SetNextItemWidth(ctx, slider_width)
        bezier_changed, LFO.bezierTension = ImGui.SliderDouble(ctx, 'Bezier Tension', LFO.bezierTension, 0.0, 1.0, '%.3f')
    end
    
    -- Auto Apply checkbox and buttons on same line
    ImGui.Separator(ctx)
    local auto_changed
    auto_changed, LFO.autoApply = ImGui.Checkbox(ctx, 'Auto Apply Changes', LFO.autoApply)
    
    -- Add buttons horizontally next to checkbox
    ImGui.SameLine(ctx)
    
    -- Only show Apply LFO button if auto apply is disabled
    if not LFO.autoApply then
        if ImGui.Button(ctx, 'Apply LFO', 120, 30) then
            apply_lfo()
        end
        ImGui.SameLine(ctx)
    end
    
    if ImGui.Button(ctx, 'Reset', 120, 30) then
        reset_parameters()
    end
    
    -- If any parameter changed and auto apply is on, apply the LFO
    if LFO.autoApply and (rate_changed or amplitude_changed or center_changed or phase_changed or rate_rand_changed or amp_rand_changed or center_rand_changed or resolution_changed or bezier_changed or auto_changed) then
        apply_lfo()
    end
end

function draw_shape_selector()
    ImGui.SeparatorText(ctx, 'LFO Shape')
    
    -- Calculate width to match sliders
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local dropdown_width = math.max(200, content_width - 130)
    
    ImGui.SetNextItemWidth(ctx, dropdown_width)
    if ImGui.BeginCombo(ctx, 'Shape', shapes[LFO.currentShape]) then
        for i, shapeName in ipairs(shapes) do
            local is_selected = (LFO.currentShape == i)
            if ImGui.Selectable(ctx, shapeName, is_selected) then
                LFO.currentShape = i
                -- Auto apply if enabled
                if LFO.autoApply then
                    apply_lfo()
                end
            end
            
            -- Set the initial focus when opening the combo
            if is_selected then
                ImGui.SetItemDefaultFocus(ctx)
            end
        end
        ImGui.EndCombo(ctx)
    end
end

-- Draw a single envelope editor with specified parameters
function draw_single_envelope_editor(envelope_type, envelope_data, canvas_size, title, editor_id)
    if title and title ~= '' then
        ImGui.Text(ctx, title)
    end
    
    local canvas_pos = {ImGui.GetCursorScreenPos(ctx)}
    local draw_list = ImGui.GetWindowDrawList(ctx)
    
    if not envelope_data then return end
    
    -- Draw canvas background with grid
    ImGui.DrawList_AddRectFilled(draw_list, 
        canvas_pos[1], canvas_pos[2],
        canvas_pos[1] + canvas_size[1], canvas_pos[2] + canvas_size[2],
        0xFF1A1A1A)
    
    -- Draw grid lines
    local grid_color = 0xFFFFFF41
    for i = 1, 4 do
        local x = canvas_pos[1] + (i / 5) * canvas_size[1]
        ImGui.DrawList_AddLine(draw_list, x, canvas_pos[2], x, canvas_pos[2] + canvas_size[2], grid_color, 1.0)
    end
    for i = 1, 4 do
        local y = canvas_pos[2] + (i / 5) * canvas_size[2]
        ImGui.DrawList_AddLine(draw_list, canvas_pos[1], y, canvas_pos[1] + canvas_size[1], y, grid_color, 1.0)
    end
    
    -- Create invisible button for canvas interaction (unique ID for each editor)
    ImGui.InvisibleButton(ctx, 'envelope_canvas_' .. editor_id, canvas_size[1], canvas_size[2])
    local canvas_hovered = ImGui.IsItemHovered(ctx)
    local canvas_active = ImGui.IsItemActive(ctx)
    
    -- Get mouse info
    local mouse_pos = {ImGui.GetMousePos(ctx)}
    local mouse_clicked = ImGui.IsMouseClicked(ctx, 0)
    local mouse_released = ImGui.IsMouseReleased(ctx, 0)
    local right_mouse_clicked = ImGui.IsMouseClicked(ctx, 1)
    local right_mouse_released = ImGui.IsMouseReleased(ctx, 1)
    
    -- Get value range for current envelope type
    local function get_envelope_range()
        -- All envelopes use 0.0-2.0 range as they are multipliers
        return 0.0, 2.0
    end
    
    -- Convert mouse position to envelope coordinates
    local function screen_to_env(screen_x, screen_y)
        local env_x = (screen_x - canvas_pos[1]) / canvas_size[1]
        local screen_y_norm = 1.0 - (screen_y - canvas_pos[2]) / canvas_size[2]
        
        -- Convert screen Y to actual value range
        local min_val, max_val = get_envelope_range()
        local env_y = min_val + screen_y_norm * (max_val - min_val)
        
        return math.max(0, math.min(1, env_x)), math.max(min_val, math.min(max_val, env_y))
    end
    
    -- Convert envelope coordinates to screen position
    local function env_to_screen(env_x, env_y)
        local screen_x = canvas_pos[1] + env_x * canvas_size[1]
        
        -- Convert value to screen Y coordinate
        local min_val, max_val = get_envelope_range()
        local y_norm = (env_y - min_val) / (max_val - min_val)
        local screen_y = canvas_pos[2] + (1.0 - y_norm) * canvas_size[2]
        
        return screen_x, screen_y
    end
    
    -- Find closest node to mouse
    local function find_closest_node(mx, my)
        local closest_idx = nil
        local closest_dist = math.huge
        
        for i, point in ipairs(envelope_data) do
            local sx, sy = env_to_screen(point[1], point[2])
            local dist = math.sqrt((mx - sx)^2 + (my - sy)^2)
            if dist < 10 and dist < closest_dist then
                closest_idx = i
                closest_dist = dist
            end
        end
        
        return closest_idx
    end
    
    -- Use separate drag state for each envelope
    local drag_key = 'draggedNode_' .. envelope_type
    if not LFO[drag_key] then LFO[drag_key] = nil end
    
    -- Handle mouse interaction
    if canvas_hovered then
        local mx, my = mouse_pos[1], mouse_pos[2]
        local closest_node = find_closest_node(mx, my)
        local shift_held = ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift) or ImGui.IsKeyDown(ctx, ImGui.Key_RightShift)
        
        -- Left click handling
        if mouse_clicked then
            if shift_held then
                -- Shift+click: start multi-point drawing mode
                local env_x, env_y = screen_to_env(mx, my)
                
                -- Find insertion point to keep envelope sorted by x
                local insert_idx = #envelope_data + 1
                for i, point in ipairs(envelope_data) do
                    if env_x < point[1] then
                        insert_idx = i
                        break
                    end
                end
                
                table.insert(envelope_data, insert_idx, {env_x, env_y})
                LFO[drag_key] = insert_idx
                LFO[drag_key .. '_multi_draw'] = true -- Flag for multi-draw mode
                -- Auto apply if enabled
                if LFO.autoApply then
                    apply_lfo()
                end
            elseif closest_node then
                -- Start dragging existing node
                LFO[drag_key] = closest_node
                LFO[drag_key .. '_multi_draw'] = false
            else
                -- Add new node at mouse position
                local env_x, env_y = screen_to_env(mx, my)
                
                -- Find insertion point to keep envelope sorted by x
                local insert_idx = #envelope_data + 1
                for i, point in ipairs(envelope_data) do
                    if env_x < point[1] then
                        insert_idx = i
                        break
                    end
                end
                
                table.insert(envelope_data, insert_idx, {env_x, env_y})
                LFO[drag_key] = insert_idx
                LFO[drag_key .. '_multi_draw'] = false
                -- Auto apply if enabled
                if LFO.autoApply then
                    apply_lfo()
                end
            end
        end
        
        -- Right click handling
        if right_mouse_clicked then
            if shift_held then
                -- Shift+right-click: start multi-delete mode
                local closest_node = find_closest_node(mx, my)
                if closest_node and closest_node > 1 and closest_node < #envelope_data then
                    table.remove(envelope_data, closest_node)
                    LFO[drag_key .. '_multi_delete'] = true -- Flag for multi-delete mode
                    -- Auto apply if enabled
                    if LFO.autoApply then
                        apply_lfo()
                    end
                end
            else
                -- Normal right-click: delete single node
                local closest_node = find_closest_node(mx, my)
                if closest_node and closest_node > 1 and closest_node < #envelope_data then
                    table.remove(envelope_data, closest_node)
                    -- Auto apply if enabled
                    if LFO.autoApply then
                        apply_lfo()
                    end
                end
            end
        end
    end
    
    -- Handle node dragging (left mouse)
    if LFO[drag_key] and canvas_active and ImGui.IsMouseDown(ctx, 0) then
        local mx, my = mouse_pos[1], mouse_pos[2]
        local env_x, env_y = screen_to_env(mx, my)
        
        if LFO[drag_key .. '_multi_draw'] then
            -- Multi-draw mode: add points as we drag
            local shift_held = ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift) or ImGui.IsKeyDown(ctx, ImGui.Key_RightShift)
            
            if shift_held then
                -- Check if we should add a new point (based on distance from last point)
                local last_point = envelope_data[#envelope_data]
                local distance = math.sqrt((env_x - last_point[1])^2 + (env_y - last_point[2])^2)
                
                -- Add point if moved far enough
                if distance > 0.02 then -- Adjust threshold as needed
                    -- Find insertion point to keep envelope sorted by x
                    local insert_idx = #envelope_data + 1
                    for i, point in ipairs(envelope_data) do
                        if env_x < point[1] then
                            insert_idx = i
                            break
                        end
                    end
                    
                    table.insert(envelope_data, insert_idx, {env_x, env_y})
                    LFO[drag_key] = insert_idx
                end
            else
                -- Shift released, switch to normal drag mode
                LFO[drag_key .. '_multi_draw'] = false
            end
        else
            -- Normal single node dragging
            -- Update dragged node position
            envelope_data[LFO[drag_key]][1] = env_x
            envelope_data[LFO[drag_key]][2] = env_y
            
            -- Keep envelope sorted by x (but allow first and last to stay at edges)
            if LFO[drag_key] > 1 and LFO[drag_key] < #envelope_data then
                -- Make sure this node stays between its neighbors
                local prev_x = envelope_data[LFO[drag_key] - 1][1]
                local next_x = envelope_data[LFO[drag_key] + 1][1]
                envelope_data[LFO[drag_key]][1] = math.max(prev_x + 0.01, math.min(next_x - 0.01, env_x))
            elseif LFO[drag_key] == 1 then
                -- First node: clamp to left edge
                envelope_data[LFO[drag_key]][1] = 0.0
            elseif LFO[drag_key] == #envelope_data then
                -- Last node: clamp to right edge  
                envelope_data[LFO[drag_key]][1] = 1.0
            end
        end
    end
    
    -- Handle multi-delete dragging (right mouse)
    if LFO[drag_key .. '_multi_delete'] and ImGui.IsMouseDown(ctx, 1) then
        local mx, my = mouse_pos[1], mouse_pos[2]
        local shift_held = ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift) or ImGui.IsKeyDown(ctx, ImGui.Key_RightShift)
        
        if shift_held then
            -- Check for nodes to delete under mouse cursor
            local closest_node = find_closest_node(mx, my)
            if closest_node and closest_node > 1 and closest_node < #envelope_data then
                -- Track last deleted position
                local last_delete_key = drag_key .. '_last_delete_pos'
                if not LFO[last_delete_key] then LFO[last_delete_key] = {-1, -1} end
                
                -- Only delete if we've moved far enough from last deletion point
                local last_mx, last_my = LFO[last_delete_key][1], LFO[last_delete_key][2]
                local delete_distance = math.sqrt((mx - last_mx)^2 + (my - last_my)^2)
                
                if delete_distance > 15 then -- Minimum distance before deleting again
                    table.remove(envelope_data, closest_node)
                    LFO[last_delete_key] = {mx, my} -- Update last delete position
                    -- Auto apply if enabled
                    if LFO.autoApply then
                        apply_lfo()
                    end
                end
            end
        else
            -- Shift released, stop multi-delete mode
            LFO[drag_key .. '_multi_delete'] = false
        end
    end
    
    -- Stop dragging on mouse release
    if mouse_released then
        if LFO[drag_key] then
            -- Auto apply if enabled when finishing drag
            if LFO.autoApply then
                apply_lfo()
            end
        end
        LFO[drag_key] = nil
        LFO[drag_key .. '_multi_draw'] = nil
    end
    
    -- Stop multi-delete on right mouse release
    if right_mouse_released then
        LFO[drag_key .. '_multi_delete'] = nil
        LFO[drag_key .. '_last_delete_pos'] = nil
    end
    
    
    -- Draw envelope lines
    for i = 1, #envelope_data - 1 do
        local x1, y1 = env_to_screen(envelope_data[i][1], envelope_data[i][2])
        local x2, y2 = env_to_screen(envelope_data[i+1][1], envelope_data[i+1][2])
        ImGui.DrawList_AddLine(draw_list, x1, y1, x2, y2, 0xFFFFFFFF, 2.0)
    end
    
    -- Draw envelope nodes
    for i, point in ipairs(envelope_data) do
        local sx, sy = env_to_screen(point[1], point[2])
        local node_color = 0xFF00FFFF
        local is_hovered = false
        
        -- Highlight dragged node
        if LFO[drag_key] == i then
            node_color = 0xFF00FF00
        -- Highlight hovered node
        elseif canvas_hovered then
            local mx, my = mouse_pos[1], mouse_pos[2]
            local dist = math.sqrt((mx - sx)^2 + (my - sy)^2)
            if dist < 10 then
                node_color = 0xFFFFFF00
                is_hovered = true
            end
        end
        
        ImGui.DrawList_AddCircleFilled(draw_list, sx, sy, 4.0, node_color)
        ImGui.DrawList_AddCircle(draw_list, sx, sy, 4.0, 0xFFFFFFFF, 0, 1.0)
        
        -- Show tooltip when hovering over node
        if is_hovered then
            local time_percent = point[1] * 100
            local multiplier_value = point[2]
            ImGui.SetTooltip(ctx, string.format('Time: %.1f%%\nValue: %.2f', time_percent, multiplier_value))
        end
    end
    
    -- Value range labels (all envelopes now use 0.0-2.0 multiplier range)
    local label_color = 0xFF888888
    
    -- Top value (2.0)
    ImGui.DrawList_AddText(draw_list, canvas_pos[1] - 30, canvas_pos[2] - 5, label_color, '2.0')
    
    -- Middle value (1.0)
    ImGui.DrawList_AddText(draw_list, canvas_pos[1] - 30, canvas_pos[2] + canvas_size[2]/2 - 5, label_color, '1.0')
    
    -- Bottom value (0.0)
    ImGui.DrawList_AddText(draw_list, canvas_pos[1] - 30, canvas_pos[2] + canvas_size[2] - 5, label_color, '0.0')
end

-- Draw all three envelope editors side by side
function draw_envelope_editors()
    ImGui.SeparatorText(ctx, 'Envelope Editors')
    
    -- Calculate envelope editor sizes
    local content_width, content_height = ImGui.GetContentRegionAvail(ctx)
    local spacing = 10
    local available_width = content_width - (2 * spacing) -- Account for spacing between 3 editors
    local single_width = math.max(200, math.floor(available_width / 3)) -- Minimum 200px per editor
    
    -- Calculate height
    local envelope_height = math.max(150, content_height - 40) -- Min 150px, no max limit, leave 40px padding
    local single_canvas_size = {single_width, envelope_height}
    
    -- Check minimum window size
    if single_width < 150 or envelope_height < 100 then
        ImGui.Text(ctx, 'Window too small - resize to see envelope editors')
        return
    end
    
    -- Child windows for layout
    local child_height = single_canvas_size[2] + 40 -- Extra height for title
    
    -- Define matching background colors for envelope editors
    local rate_bg_color = 0x952E2B30     -- Deep red background (semi-transparent)
    local amplitude_bg_color = 0x66B20070  -- Deep green background (semi-transparent)
    local center_bg_color = 0x0091B260    -- Deep blue background (semi-transparent)
    
    -- Rate envelope
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, rate_bg_color)
    if ImGui.BeginChild(ctx, 'rate_child', single_width, child_height) then
        draw_single_envelope_editor('rate', LFO.rateEnvelope, single_canvas_size, 'Rate Multiplier', 'rate')
    end
    ImGui.EndChild(ctx)
    ImGui.PopStyleColor(ctx, 1)
    
    ImGui.SameLine(ctx, 0, spacing)
    
    -- Amplitude envelope
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, amplitude_bg_color)
    if ImGui.BeginChild(ctx, 'amplitude_child', single_width, child_height) then
        draw_single_envelope_editor('amplitude', LFO.amplitudeEnvelope, single_canvas_size, 'Amplitude Multiplier', 'amplitude')
    end
    ImGui.EndChild(ctx)
    ImGui.PopStyleColor(ctx, 1)
    
    ImGui.SameLine(ctx, 0, spacing)
    
    -- Center envelope
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, center_bg_color)
    if ImGui.BeginChild(ctx, 'center_child', single_width, child_height) then
        draw_single_envelope_editor('center', LFO.centerEnvelope, single_canvas_size, 'Center Multiplier', 'center')
    end
    ImGui.EndChild(ctx)
    ImGui.PopStyleColor(ctx, 1)
    
    -- Instructions moved to Help section for cleaner layout
end

-- Controls are now integrated with parameters section

-- Utility function to evaluate envelope at given position
function evaluate_envelope(envelope, pos)
    if not envelope or #envelope == 0 then return 0.5 end
    if pos <= envelope[1][1] then return envelope[1][2] end
    if pos >= envelope[#envelope][1] then return envelope[#envelope][2] end
    
    -- Find interpolation points
    for i = 1, #envelope - 1 do
        if pos >= envelope[i][1] and pos <= envelope[i+1][1] then
            local x1, y1 = envelope[i][1], envelope[i][2]
            local x2, y2 = envelope[i+1][1], envelope[i+1][2]
            local t = (pos - x1) / (x2 - x1)
            return y1 + t * (y2 - y1) -- Linear interpolation
        end
    end
    return 0.5 -- Fallback
end

-- Generate LFO points based on current settings
function generate_lfo_points(duration)
    local points = {}
    
    -- Use user-defined resolution for accurate shape representation
    local points_per_second = LFO.resolution -- User-controllable resolution
    local total_steps = math.max(20, math.floor(duration * points_per_second))
    
    -- Phase tracking
    local current_phase = LFO.phase * 2 * math.pi -- Use radians for cleaner math
    
    for i = 0, total_steps - 1 do
        local time_pos = i / (total_steps - 1) -- 0 to 1 across entire duration
        
        -- Evaluate parameter envelopes at this time position
        local rate_env = evaluate_envelope(LFO.rateEnvelope, time_pos)
        local amp_env = evaluate_envelope(LFO.amplitudeEnvelope, time_pos)
        local center_env = evaluate_envelope(LFO.centerEnvelope, time_pos)
        
        -- For smooth rate changes, interpolate between slider and envelope
        -- If rate envelope is nearly flat, use slider value, otherwise interpolate
        local rate_variation = math.abs(rate_env - LFO.rate)
        if rate_variation < 0.1 then
            -- Rate envelope is basically flat, use slider value
            current_frequency = LFO.rate  
        else
            -- Rate envelope has been modified, use smooth interpolation
            local envelope_baseline = evaluate_envelope(LFO.rateEnvelope, 0.0) -- Get baseline
            local envelope_multiplier = rate_env / math.max(0.1, envelope_baseline)
            current_frequency = LFO.rate * envelope_multiplier
        end
        
        -- Apply rate randomness BEFORE phase calculation
        if LFO.rateRandomness > 0 then
            local rate_random = (math.random() * 2 - 1) * LFO.rateRandomness -- -randomness to +randomness
            local rate_multiplier = 1.0 + rate_random
            current_frequency = current_frequency * rate_multiplier
        end
        
        -- Frequency bounds check
        if current_frequency < 0.01 or current_frequency > 100 then
            current_frequency = LFO.rate
        end
        
        -- For smooth rate modulation, phase must accumulate continuously
        local time_step = duration / (total_steps - 1)
        local phase_increment = current_frequency * time_step * 2 * math.pi
        
        -- Generate LFO value based on shape and current phase
        local lfo_amplitude = 1.0 -- Start with full amplitude
        
        -- Apply shape function
        if LFO.currentShape == 1 then -- Bezier curve
            local phase_norm = (current_phase % (2 * math.pi)) / (2 * math.pi) -- 0 to 1
            -- Create Bezier curve using tension parameter
            -- Low tension = more linear, high tension = more curved
            local t = phase_norm
            local tension = LFO.bezierTension
            
            -- Bezier control points for a wave from -1 to 1 and back
            local p0 = -1.0  -- Start point
            local p1 = -1.0 + tension * 4.0  -- First control point (influenced by tension)
            local p2 = 1.0 - tension * 4.0   -- Second control point (influenced by tension)
            local p3 = 1.0   -- End point
            
            if t <= 0.5 then
                -- First half: -1 to 1
                local t_half = t * 2 -- 0 to 1
                lfo_amplitude = (1-t_half)^3*p0 + 3*(1-t_half)^2*t_half*p1 + 3*(1-t_half)*t_half^2*p3 + t_half^3*1.0
            else
                -- Second half: 1 to -1
                local t_half = (t - 0.5) * 2 -- 0 to 1
                lfo_amplitude = (1-t_half)^3*1.0 + 3*(1-t_half)^2*t_half*p2 + 3*(1-t_half)*t_half^2*p0 + t_half^3*(-1.0)
            end
        elseif LFO.currentShape == 2 then -- Saw Down
            lfo_amplitude = 1.0 - 2.0 * (current_phase % (2 * math.pi)) / (2 * math.pi)
        elseif LFO.currentShape == 3 then -- Saw Up
            lfo_amplitude = -1.0 + 2.0 * (current_phase % (2 * math.pi)) / (2 * math.pi)
        elseif LFO.currentShape == 4 then -- Square
            lfo_amplitude = math.sin(current_phase) > 0 and 1.0 or -1.0
        elseif LFO.currentShape == 5 then -- Triangle
            local phase_norm = (current_phase % (2 * math.pi)) / (2 * math.pi)
            if phase_norm < 0.5 then
                lfo_amplitude = -1.0 + 4.0 * phase_norm
            else
                lfo_amplitude = 3.0 - 4.0 * phase_norm
            end
        else -- Default to sine
            lfo_amplitude = math.sin(current_phase)
        end
        
        -- Clamp LFO amplitude to expected range
        lfo_amplitude = math.max(-1.0, math.min(1.0, lfo_amplitude))
        
        -- Combine with envelope modulation
        local final_amplitude = LFO.amplitude * amp_env
        local final_center = LFO.center * center_env
        
        -- Apply randomness to amplitude and center parameters (per-point randomization)
        if LFO.amplitudeRandomness > 0 then
            local amp_random = (math.random() * 2 - 1) * LFO.amplitudeRandomness -- -randomness to +randomness
            local amp_multiplier = 1.0 + amp_random
            final_amplitude = final_amplitude * amp_multiplier
        end
        
        if LFO.centerRandomness > 0 then
            local center_random = (math.random() * 2 - 1) * LFO.centerRandomness -- -randomness to +randomness
            local center_multiplier = 1.0 + center_random
            final_center = final_center * center_multiplier
        end
        
        -- Calculate final value: Center ± (amplitude/2 * LFO_wave)
        -- Center=0.5, Amp=0.8 should give range 0.1 to 0.9 (0.5 ± 0.4)
        -- Symmetric oscillation around center point
        local half_amplitude = final_amplitude * 0.5
        local lfo_value = final_center + (lfo_amplitude * half_amplitude)
        
        -- No clamping here - let envelope range detection handle it later
        -- Envelope range detection handles clamping
        
        table.insert(points, {
            time = LFO.timeStart + time_pos * duration,
            value = lfo_value,
            shape = 0, -- Linear for now
            tension = 0
        })
        
        -- Advance phase based on current frequency for smooth transitions
        current_phase = current_phase + phase_increment
    end
    
    return points
end

-- Core LFO application function
function apply_lfo()
    if not LFO.targetEnv then
        reaper.MB('Please select an envelope first', 'No Target', 0)
        return
    end
    
    if LFO.timeEnd <= LFO.timeStart then
        reaper.MB('Please make a time selection first', 'No Time Range', 0)
        return
    end
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Clear existing points in time range
    reaper.DeleteEnvelopePointRange(LFO.targetEnv, LFO.timeStart, LFO.timeEnd)
    
    -- Generate and insert new LFO points
    local duration = LFO.timeEnd - LFO.timeStart
    local lfo_points = generate_lfo_points(duration) -- Steps calculated based on rate
    
    -- Detect envelope's actual value range
    local env_min, env_max = 0, 1 -- Default range
    if LFO.targetEnv then
        -- Try to get envelope scaling info from REAPER
        local br_env = reaper.BR_EnvAlloc(LFO.targetEnv, false)
        if br_env then
            local _, _, _, _, _, _, detected_min, detected_max = reaper.BR_EnvGetProperties(br_env)
            if detected_min and detected_max and detected_min ~= detected_max then
                env_min, env_max = detected_min, detected_max
            end
            reaper.BR_EnvFree(br_env, false)
        end
    end
    
    for _, point in ipairs(lfo_points) do
        -- Map point.value (0-1 range) to envelope's actual range
        local env_value = env_min + point.value * (env_max - env_min)
        
        -- Clamp to envelope range
        env_value = math.max(env_min, math.min(env_max, env_value))
        
        -- Insert point with appropriate shape
        local curve_shape = 0 -- Linear by default
        if point.shape == 1 then curve_shape = 1 -- Square
        elseif point.shape == 2 then curve_shape = 2 -- Slow start/end (sine-ish)
        elseif point.shape == 5 then curve_shape = 5 -- Bezier
        end
        
        reaper.InsertEnvelopePoint(LFO.targetEnv, point.time, env_value, curve_shape, point.tension or 0, true, true)
    end
    
    -- Update display and finish
    reaper.Envelope_SortPoints(LFO.targetEnv)
    reaper.UpdateArrange()
    
    reaper.Undo_EndBlock('Apply LFO: ' .. shapes[LFO.currentShape], -1)
    
end

function reset_parameters()
    LFO.rate = 5.0 -- Hz
    LFO.amplitude = 0.5
    LFO.center = 0.5
    LFO.phase = 0.0
    LFO.currentShape = 1
    
    -- Reset power curve slider positions
    LFO.rate_slider_pos = value_to_slider_pos(LFO.rate, 0.01, 50.0, 1.8)
    LFO.amplitude_slider_pos = value_to_slider_pos(LFO.amplitude, 0.0, 2.0, 1.8)
    
    -- Reset randomness parameters
    LFO.rateRandomness = 0.0
    LFO.amplitudeRandomness = 0.0
    LFO.centerRandomness = 0.0
    
    -- Reset resolution
    LFO.resolution = 500
    
    -- Reset Bezier tension
    LFO.bezierTension = 0.5
    
    -- Reset envelope editors to default flat lines (1.0 = 100% multiplier)
    LFO.rateEnvelope = {{0.0, 1.0}, {1.0, 1.0}}
    LFO.amplitudeEnvelope = {{0.0, 1.0}, {1.0, 1.0}}
    LFO.centerEnvelope = {{0.0, 1.0}, {1.0, 1.0}}
    
    -- Clear any drag states
    LFO.draggedNode_rate = nil
    LFO.draggedNode_amplitude = nil
    LFO.draggedNode_center = nil
    LFO.draggedNode_rate_multi_draw = nil
    LFO.draggedNode_amplitude_multi_draw = nil
    LFO.draggedNode_center_multi_draw = nil
    LFO.draggedNode_rate_multi_delete = nil
    LFO.draggedNode_amplitude_multi_delete = nil
    LFO.draggedNode_center_multi_delete = nil
    LFO.draggedNode_rate_last_delete_pos = nil
    LFO.draggedNode_amplitude_last_delete_pos = nil
    LFO.draggedNode_center_last_delete_pos = nil
    
    -- Apply reset values to envelope if auto-apply is enabled
    if LFO.autoApply then
        apply_lfo()
    end
end

-- Main GUI loop
function main_loop()
    -- Window size constraints
    -- Minimum: 1080 x 850, allow unlimited growth
    ImGui.SetNextWindowSizeConstraints(ctx, 1080, 850, math.huge, math.huge)
    
    -- Set window background to be opaque
    ImGui.SetNextWindowBgAlpha(ctx, 1.0)
    
    local visible, open = ImGui.Begin(ctx, 'joshadambell - LFO Generator', true, ImGui.WindowFlags_MenuBar)
    
    if visible then
        draw_menu_bar()
        draw_target_info()
        draw_parameters()
        draw_shape_selector()
        draw_envelope_editors()
    end
    
    ImGui.End(ctx)
    
    -- Help window
    draw_help_window()
    
    if open then
        reaper.defer(main_loop)
    else
        -- Context cleanup handled automatically
    end
end

-- Initialize power curve slider positions from actual values
function init_slider_positions()
    if not LFO.rate_slider_pos then
        LFO.rate_slider_pos = value_to_slider_pos(LFO.rate, 0.01, 50.0, 1.8)
    end
    if not LFO.amplitude_slider_pos then
        LFO.amplitude_slider_pos = value_to_slider_pos(LFO.amplitude, 0.0, 2.0, 1.8)
    end
end

-- Initialize and start
function init()
    -- Initialize slider positions to match default values
    init_slider_positions()
    
    -- Set initial window size to accommodate three envelope editors side by side
    -- Width: 3 envelope editors (400 each) + 2 spacings (10 each) + padding + slider labels = ~1350
    -- Height: 850
    ImGui.SetNextWindowSize(ctx, 1350, 850, ImGui.Cond_FirstUseEver)
    main_loop()
end

-- Start the script
init()