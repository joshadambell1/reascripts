-- @description JBSFX - Reaper Item & Track Renamer
-- @version 1.1
-- @author Josh Adam Bell
-- @changelog
--   + Initial release
-- @about
--   Batch rename items and tracks with live preview. 
--   GUI-based tool with find/replace, prefix/suffix, character removal, and auto-numbering.
--
-- @requirements
--   - ReaImGui extension (install via ReaPack)
--
-- @setup
--   1. Install ReaImGui via ReaPack
--   2. Install script: Actions → Show Action List → Load → select .lua file
--   3. Assign keyboard shortcut if desired
--
-- @usage
--   1. Select items/tracks in Reaper
--   2. Run script to open GUI
--   3. Check "Enable Item Renaming" or "Enable Track Renaming" (or both)
--   4. Use any combination of tools:
--      - Find & Replace for text changes
--      - Prefix/Suffix for adding text to start/end
--      - Character removal for trimming
--      - Numbering for sequential numbers
--   5. Watch live preview update
--   6. Click action buttons to apply
--
-- @tools
--   Find & Replace:
--     - Replace all/first/last instances
--     - Case sensitive option
--
--   Prefix & Suffix:
--     - Add text to beginning or end of names
--
--   Character Removal:
--     - Remove X characters from start or end
--
--   Numbering:
--     - Add sequential numbers with separator (space/underscore/hyphen)
--     - Zero padding options (none/01/001/0001)
--     - Custom starting number
--     - Items and tracks numbered separately
--
-- @example
--   Original: "Guitar.wav", "Bass.wav"
--   - Add prefix "SONG_"
--   - Remove ".wav"
--   - Add numbering with underscore, 2-digit padding
--   Result: "SONG_Guitar_01", "SONG_Bass_02"
--
-- @options
--   - Auto-refresh when selection changes
--   - Live preview shows before/after names
--   - All operations are undoable

-- Import ReaImGui
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

-- Script variables
local ctx = ImGui.CreateContext('Item Take Find & Replace')
local find_text = ""
local replace_text = ""
local case_sensitive = false
local replace_mode = 0  -- 0 = All, 1 = First only, 2 = Last only
local prefix_text = ""
local suffix_text = ""
local remove_start_count = 0
local remove_end_count = 0
local status_message = ""
local preview_items = {}
local last_item_count = 0
local last_track_count = 0
local auto_refresh = true
local enable_item_renaming = true
local enable_track_renaming = false
local enable_numbering = false -- Numbering disabled by default
local numbering_separator = 0  -- 0 = space, 1 = underscore, 2 = hyphen
local numbering_padding = 1    -- 0 = none, 1 = one zero, 2 = two zeros, 3 = three zeros
local numbering_start = 1      -- Starting number (1-99)

-- Initialize the script
function Init()
    RefreshPreview()
end

-- Refresh the preview list
function RefreshPreview()
    preview_items = {}
    local item_count = reaper.CountSelectedMediaItems(0)
    local track_count = reaper.CountSelectedTracks(0)
    local added_items = 0
    local added_tracks = 0
    
    -- Add selected items if enabled
    if enable_item_renaming then
        for i = 0, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local take = reaper.GetActiveTake(item)
            
            if take then
                local retval, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                
                table.insert(preview_items, {
                    type = "item",
                    item = item,
                    take = take,
                    original_name = take_name,
                    new_name = take_name
                })
                added_items = added_items + 1
            else
                -- Item with no take
                table.insert(preview_items, {
                    type = "item",
                    item = item,
                    take = nil,
                    original_name = "[No active take]",
                    new_name = "[No active take]"
                })
                added_items = added_items + 1
            end
        end
    end
    
    -- Add selected tracks if enabled
    if enable_track_renaming then
        for i = 0, track_count - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            local retval, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            
            table.insert(preview_items, {
                type = "track",
                track = track,
                original_name = track_name,
                new_name = track_name
            })
            added_tracks = added_tracks + 1
        end
    end
    
    -- Update status message
    local status_parts = {}
    if enable_item_renaming and added_items > 0 then
        table.insert(status_parts, string.format("%d items", added_items))
    end
    if enable_track_renaming and added_tracks > 0 then
        table.insert(status_parts, string.format("%d tracks", added_tracks))
    end
    
    if #status_parts == 0 then
        if not enable_item_renaming and not enable_track_renaming then
            status_message = "Both item and track renaming are disabled!"
        else
            status_message = "No enabled items or tracks selected!"
        end
    else
        status_message = "Loaded " .. table.concat(status_parts, " and ")
    end
    
    UpdatePreview()
end

-- Perform find and replace with different modes
function PerformFindReplaceOnText(original, find_str, replace_str, mode, is_case_sensitive)
    if find_str == "" then
        return original
    end
    
    local new_name = original
    
    if is_case_sensitive then
        if mode == 0 then -- All instances
            new_name = string.gsub(original, find_str, replace_str)
        elseif mode == 1 then -- First instance only
            new_name = string.gsub(original, find_str, replace_str, 1)
        elseif mode == 2 then -- Last instance only
            local matches = {}
            local start_pos = 1
            
            -- Find all matches
            while true do
                local find_start, find_end = string.find(original, find_str, start_pos, true)
                if not find_start then break end
                table.insert(matches, {find_start, find_end})
                start_pos = find_end + 1
            end
            
            -- Replace only the last match
            if #matches > 0 then
                local last_match = matches[#matches]
                new_name = string.sub(original, 1, last_match[1] - 1) .. 
                          replace_str .. 
                          string.sub(original, last_match[2] + 1)
            end
        end
    else
        -- Case insensitive
        local pattern = string.gsub(find_str, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local lower_original = string.lower(original)
        local lower_find = string.lower(pattern)
        
        if mode == 0 then -- All instances
            local result = ""
            local start_pos = 1
            
            while true do
                local find_start, find_end = string.find(lower_original, lower_find, start_pos, true)
                if not find_start then
                    result = result .. string.sub(original, start_pos)
                    break
                end
                
                result = result .. string.sub(original, start_pos, find_start - 1) .. replace_str
                start_pos = find_end + 1
            end
            
            new_name = result
        elseif mode == 1 then -- First instance only
            local find_start, find_end = string.find(lower_original, lower_find, 1, true)
            if find_start then
                new_name = string.sub(original, 1, find_start - 1) .. 
                          replace_str .. 
                          string.sub(original, find_end + 1)
            end
        elseif mode == 2 then -- Last instance only
            local matches = {}
            local start_pos = 1
            
            -- Find all matches
            while true do
                local find_start, find_end = string.find(lower_original, lower_find, start_pos, true)
                if not find_start then break end
                table.insert(matches, {find_start, find_end})
                start_pos = find_end + 1
            end
            
            -- Replace only the last match
            if #matches > 0 then
                local last_match = matches[#matches]
                new_name = string.sub(original, 1, last_match[1] - 1) .. 
                          replace_str .. 
                          string.sub(original, last_match[2] + 1)
            end
        end
    end
    
    return new_name
end

-- Update preview with find/replace results
function UpdatePreview()
    -- Get separator character for numbering preview
    local separators = {" ", "_", "-"}
    local separator = separators[numbering_separator + 1]
    
    -- Count items and tracks separately for numbering preview
    local item_number = numbering_start
    local track_number = numbering_start
    
    for i, item_data in ipairs(preview_items) do
        -- Skip items with no take and tracks with empty names for processing
        if (item_data.type == "item" and item_data.take == nil and item_data.original_name == "[No active take]") then
            item_data.new_name = item_data.original_name
        else
            local original = item_data.original_name
            local new_name = original
            
            -- Apply find/replace if enabled
            if find_text ~= "" then
                new_name = PerformFindReplaceOnText(original, find_text, replace_text, replace_mode, case_sensitive)
            end
            
            -- Show what it would look like with character removal applied
            if remove_start_count > 0 then
                if string.len(new_name) > remove_start_count then
                    new_name = string.sub(new_name, remove_start_count + 1)
                else
                    new_name = ""
                end
            end
            
            if remove_end_count > 0 then
                if string.len(new_name) > remove_end_count then
                    new_name = string.sub(new_name, 1, string.len(new_name) - remove_end_count)
                else
                    new_name = ""
                end
            end
            
            -- Show what it would look like with prefix/suffix applied to the result
            if prefix_text ~= "" or suffix_text ~= "" then
                new_name = prefix_text .. new_name .. suffix_text
            end
            
            -- Show what it would look like with numbering applied (if enabled)
            if enable_numbering then
                local current_number = 0
                local should_add_number = false
                
                if item_data.type == "item" and enable_item_renaming and item_data.take then
                    current_number = item_number
                    item_number = item_number + 1
                    should_add_number = true
                elseif item_data.type == "track" and enable_track_renaming and item_data.track then
                    current_number = track_number
                    track_number = track_number + 1
                    should_add_number = true
                end
                
                if should_add_number then
                    -- Format number with padding for preview
                    local number_str = tostring(current_number)
                    if numbering_padding == 1 then
                        number_str = string.format("%02d", current_number)
                    elseif numbering_padding == 2 then
                        number_str = string.format("%03d", current_number)
                    elseif numbering_padding == 3 then
                        number_str = string.format("%04d", current_number)
                    end
                    
                    new_name = new_name .. separator .. number_str
                end
            end
            
            item_data.new_name = new_name
        end
    end
end

-- Apply prefix to items and tracks
function ApplyPrefix()
    local total_count = #preview_items
    local changed_count = 0
    
    if total_count == 0 then
        status_message = "No items or tracks to process!"
        return
    end
    
    if prefix_text == "" then
        status_message = "Prefix text cannot be empty!"
        return
    end
    
    reaper.Undo_BeginBlock()
    
    for i, item_data in ipairs(preview_items) do
        if item_data.type == "item" and enable_item_renaming and item_data.take then
            local new_name = prefix_text .. item_data.original_name
            reaper.GetSetMediaItemTakeInfo_String(item_data.take, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        elseif item_data.type == "track" and enable_track_renaming and item_data.track then
            local new_name = prefix_text .. item_data.original_name
            reaper.GetSetMediaTrackInfo_String(item_data.track, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        end
    end
    
    reaper.Undo_EndBlock("Add prefix to item and track names", -1)
    reaper.UpdateArrange()
    
    status_message = string.format("Added prefix to %d out of %d items/tracks", changed_count, total_count)
    
    -- Refresh items after changes to show updated names
    RefreshPreview()
end

-- Apply suffix to items and tracks
function ApplySuffix()
    local total_count = #preview_items
    local changed_count = 0
    
    if total_count == 0 then
        status_message = "No items or tracks to process!"
        return
    end
    
    if suffix_text == "" then
        status_message = "Suffix text cannot be empty!"
        return
    end
    
    reaper.Undo_BeginBlock()
    
    for i, item_data in ipairs(preview_items) do
        if item_data.type == "item" and enable_item_renaming and item_data.take then
            local new_name = item_data.original_name .. suffix_text
            reaper.GetSetMediaItemTakeInfo_String(item_data.take, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        elseif item_data.type == "track" and enable_track_renaming and item_data.track then
            local new_name = item_data.original_name .. suffix_text
            reaper.GetSetMediaTrackInfo_String(item_data.track, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        end
    end
    
    reaper.Undo_EndBlock("Add suffix to item and track names", -1)
    reaper.UpdateArrange()
    
    status_message = string.format("Added suffix to %d out of %d items/tracks", changed_count, total_count)
    
    -- Refresh items after changes to show updated names
    RefreshPreview()
end

-- Remove characters from start of items and tracks
function RemoveFromStart()
    local total_count = #preview_items
    local changed_count = 0
    
    if total_count == 0 then
        status_message = "No items or tracks to process!"
        return
    end
    
    if remove_start_count <= 0 then
        status_message = "Remove start count must be greater than 0!"
        return
    end
    
    reaper.Undo_BeginBlock()
    
    for i, item_data in ipairs(preview_items) do
        local original_name = item_data.original_name
        local new_name = original_name
        
        if string.len(original_name) > remove_start_count then
            new_name = string.sub(original_name, remove_start_count + 1)
        else
            new_name = "" -- Remove all characters if count is greater than or equal to name length
        end
        
        if item_data.type == "item" and enable_item_renaming and item_data.take then
            reaper.GetSetMediaItemTakeInfo_String(item_data.take, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        elseif item_data.type == "track" and enable_track_renaming and item_data.track then
            reaper.GetSetMediaTrackInfo_String(item_data.track, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        end
    end
    
    reaper.Undo_EndBlock("Remove characters from start of item and track names", -1)
    reaper.UpdateArrange()
    
    status_message = string.format("Removed %d characters from start of %d items/tracks", remove_start_count, changed_count)
    
    -- Refresh items after changes to show updated names
    RefreshPreview()
end

-- Remove characters from end of items and tracks
function RemoveFromEnd()
    local total_count = #preview_items
    local changed_count = 0
    
    if total_count == 0 then
        status_message = "No items or tracks to process!"
        return
    end
    
    if remove_end_count <= 0 then
        status_message = "Remove end count must be greater than 0!"
        return
    end
    
    reaper.Undo_BeginBlock()
    
    for i, item_data in ipairs(preview_items) do
        local original_name = item_data.original_name
        local new_name = original_name
        
        if string.len(original_name) > remove_end_count then
            new_name = string.sub(original_name, 1, string.len(original_name) - remove_end_count)
        else
            new_name = "" -- Remove all characters if count is greater than or equal to name length
        end
        
        if item_data.type == "item" and enable_item_renaming and item_data.take then
            reaper.GetSetMediaItemTakeInfo_String(item_data.take, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        elseif item_data.type == "track" and enable_track_renaming and item_data.track then
            reaper.GetSetMediaTrackInfo_String(item_data.track, "P_NAME", new_name, true)
            changed_count = changed_count + 1
        end
    end
    
    reaper.Undo_EndBlock("Remove characters from end of item and track names", -1)
    reaper.UpdateArrange()
    
    status_message = string.format("Removed %d characters from end of %d items/tracks", remove_end_count, changed_count)
    
    -- Refresh items after changes to show updated names
    RefreshPreview()
end

-- Perform the actual find and replace operation
function PerformFindReplace()
    local total_count = #preview_items
    local changed_count = 0
    
    if total_count == 0 then
        status_message = "No items or tracks to process!"
        return
    end
    
    if find_text == "" then
        status_message = "Find text cannot be empty!"
        return
    end
    
    reaper.Undo_BeginBlock()
    
    for i, item_data in ipairs(preview_items) do
        if item_data.original_name ~= item_data.new_name then
            if item_data.type == "item" and enable_item_renaming and item_data.take then
                reaper.GetSetMediaItemTakeInfo_String(item_data.take, "P_NAME", item_data.new_name, true)
                changed_count = changed_count + 1
            elseif item_data.type == "track" and enable_track_renaming and item_data.track then
                reaper.GetSetMediaTrackInfo_String(item_data.track, "P_NAME", item_data.new_name, true)
                changed_count = changed_count + 1
            end
        end
    end
    
    reaper.Undo_EndBlock("Find and replace item and track names", -1)
    reaper.UpdateArrange()
    
    status_message = string.format("Find/replace applied to %d out of %d items/tracks", changed_count, total_count)
    
    -- Refresh preview after changes
    RefreshPreview()
end

-- Apply numbering to items and tracks
function ApplyNumbering()
    local total_count = #preview_items
    local changed_count = 0
    
    if total_count == 0 then
        status_message = "No items or tracks to process!"
        return
    end
    
    reaper.Undo_BeginBlock()
    
    -- Get separator character
    local separators = {" ", "_", "-"}
    local separator = separators[numbering_separator + 1]
    
    -- Count items and tracks separately for numbering
    local item_number = numbering_start
    local track_number = numbering_start
    
    for i, item_data in ipairs(preview_items) do
        local current_number = 0
        local should_process = false
        
        if item_data.type == "item" and enable_item_renaming and item_data.take then
            current_number = item_number
            item_number = item_number + 1
            should_process = true
        elseif item_data.type == "track" and enable_track_renaming and item_data.track then
            current_number = track_number
            track_number = track_number + 1
            should_process = true
        end
        
        if should_process then
            -- Format number with padding
            local number_str = tostring(current_number)
            if numbering_padding == 1 then
                number_str = string.format("%02d", current_number)
            elseif numbering_padding == 2 then
                number_str = string.format("%03d", current_number)
            elseif numbering_padding == 3 then
                number_str = string.format("%04d", current_number)
            end
            
            local new_name = item_data.original_name .. separator .. number_str
            
            if item_data.type == "item" then
                reaper.GetSetMediaItemTakeInfo_String(item_data.take, "P_NAME", new_name, true)
            else -- track
                reaper.GetSetMediaTrackInfo_String(item_data.track, "P_NAME", new_name, true)
            end
            
            changed_count = changed_count + 1
        end
    end
    
    reaper.Undo_EndBlock("Add numbering to item and track names", -1)
    reaper.UpdateArrange()
    
    status_message = string.format("Added numbering to %d out of %d items/tracks", changed_count, total_count)
    
    -- Refresh items after changes to show updated names
    RefreshPreview()
end

-- Main GUI loop
function Loop()
    -- Check if selection has changed and auto-refresh (if enabled)
    if auto_refresh then
        local current_item_count = reaper.CountSelectedMediaItems(0)
        local current_track_count = reaper.CountSelectedTracks(0)
        
        if current_item_count ~= last_item_count or current_track_count ~= last_track_count then
            last_item_count = current_item_count
            last_track_count = current_track_count
            RefreshPreview()
        end
    end
    
    local visible, open = ImGui.Begin(ctx, 'JBSFX Reaper Item & Track Renamer', true, ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse)
    
    if visible then
        -- Enable/Disable options
        local item_changed, new_item_enabled = ImGui.Checkbox(ctx, 'Enable Item Renaming', enable_item_renaming)
        if item_changed then
            enable_item_renaming = new_item_enabled
            RefreshPreview()
        end
        
        ImGui.SameLine(ctx)
        
        local track_changed, new_track_enabled = ImGui.Checkbox(ctx, 'Enable Track Renaming', enable_track_renaming)
        if track_changed then
            enable_track_renaming = new_track_enabled
            RefreshPreview()
        end
        
        ImGui.Separator(ctx)
        
        -- Find/Replace section
        ImGui.Text(ctx, '-- Find & Replace --')
        
        ImGui.Text(ctx, 'Find:')
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 300)
        local find_changed, new_find = ImGui.InputText(ctx, '##find', find_text)
        ImGui.PopItemWidth(ctx)
        if find_changed then
            find_text = new_find
            UpdatePreview()
        end
        
        ImGui.Text(ctx, 'Replace:')
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 300)
        local replace_changed, new_replace = ImGui.InputText(ctx, '##replace', replace_text)
        ImGui.PopItemWidth(ctx)
        if replace_changed then
            replace_text = new_replace
            UpdatePreview()
        end
        
        -- Replace mode options
        ImGui.Text(ctx, 'Replace Mode:')
        local mode_labels = {'All instances', 'First instance only', 'Last instance only'}
        for i = 0, 2 do
            local is_selected = (replace_mode == i)
            if ImGui.RadioButton(ctx, mode_labels[i + 1], is_selected) then
                replace_mode = i
                UpdatePreview()
            end
            if i < 2 then ImGui.SameLine(ctx) end
        end
        
        -- Find/Replace options
        local case_changed, new_case = ImGui.Checkbox(ctx, 'Case Sensitive', case_sensitive)
        if case_changed then
            case_sensitive = new_case
            UpdatePreview()
        end
        
        -- Find & Replace button
        if ImGui.Button(ctx, 'Find & Replace All') then
            PerformFindReplace()
        end
        
        ImGui.Separator(ctx)
        
        -- Prefix/Suffix section
        ImGui.Text(ctx, '-- Prefix & Suffix --')
        
        ImGui.Text(ctx, 'Prefix:')
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 250)
        local prefix_changed, new_prefix = ImGui.InputText(ctx, '##prefix', prefix_text)
        ImGui.PopItemWidth(ctx)
        if prefix_changed then
            prefix_text = new_prefix
            UpdatePreview()
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, 'Add Prefix') then
            ApplyPrefix()
        end
        
        ImGui.Text(ctx, 'Suffix:')
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 250)
        local suffix_changed, new_suffix = ImGui.InputText(ctx, '##suffix', suffix_text)
        ImGui.PopItemWidth(ctx)
        if suffix_changed then
            suffix_text = new_suffix
            UpdatePreview()
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, 'Add Suffix') then
            ApplySuffix()
        end
        
        ImGui.Separator(ctx)
        
        -- Remove Characters section
        ImGui.Text(ctx, '-- Remove Characters --')
        
        ImGui.Text(ctx, 'Remove from start:')
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 100)
        local start_changed, new_start = ImGui.InputInt(ctx, '##remove_start', remove_start_count)
        ImGui.PopItemWidth(ctx)
        if start_changed then
            remove_start_count = math.max(0, new_start) -- Ensure non-negative
            UpdatePreview()
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, 'Remove from Start') then
            RemoveFromStart()
        end
        
        ImGui.Text(ctx, 'Remove from end:')
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 100)
        local end_changed, new_end = ImGui.InputInt(ctx, '##remove_end', remove_end_count)
        ImGui.PopItemWidth(ctx)
        if end_changed then
            remove_end_count = math.max(0, new_end) -- Ensure non-negative
            UpdatePreview()
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, 'Remove from End') then
            RemoveFromEnd()
        end
        
        ImGui.Separator(ctx)
        
        -- Numbering section
        ImGui.Text(ctx, '-- Numbering --')
        
        local numbering_changed, new_numbering = ImGui.Checkbox(ctx, 'Enable Numbering', enable_numbering)
        if numbering_changed then
            enable_numbering = new_numbering
            UpdatePreview()
        end
        
        -- Only show numbering options if enabled
        if enable_numbering then
            ImGui.Text(ctx, 'Separator:')
            ImGui.SameLine(ctx)
            local separator_labels = {'Space', 'Underscore', 'Hyphen'}
            for i = 0, 2 do
                local is_selected = (numbering_separator == i)
                if ImGui.RadioButton(ctx, separator_labels[i + 1], is_selected) then
                    numbering_separator = i
                    UpdatePreview()
                end
                if i < 2 then ImGui.SameLine(ctx) end
            end
            
            ImGui.Text(ctx, 'Zero Padding:')
            ImGui.SameLine(ctx)
            local padding_labels = {'None', 'One', 'Two', 'Three'}
            for i = 0, 3 do
                local is_selected = (numbering_padding == i)
                if ImGui.RadioButton(ctx, padding_labels[i + 1], is_selected) then
                    numbering_padding = i
                    UpdatePreview()
                end
                if i < 3 then ImGui.SameLine(ctx) end
            end
            
            ImGui.Text(ctx, 'Starting Number:')
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 100)
            local start_changed, new_start = ImGui.InputInt(ctx, '##numbering_start', numbering_start)
            ImGui.PopItemWidth(ctx)
            if start_changed then
                numbering_start = math.max(1, math.min(99, new_start)) -- Clamp between 1 and 99
                UpdatePreview()
            end
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, 'Add Numbering') then
                ApplyNumbering()
            end
        end
        
        ImGui.Separator(ctx)
        
        -- Control buttons
        if ImGui.Button(ctx, 'Refresh Items') then
            RefreshPreview()
        end
        
        ImGui.SameLine(ctx)
        
        local auto_changed, new_auto = ImGui.Checkbox(ctx, 'Auto-refresh on selection change', auto_refresh)
        if auto_changed then
            auto_refresh = new_auto
            if auto_refresh then
                -- Refresh items and update selection counts when auto-refresh is enabled
                RefreshPreview()
                last_item_count = reaper.CountSelectedMediaItems(0)
                last_track_count = reaper.CountSelectedTracks(0)
            end
        end
        
        -- Status message
        if status_message ~= "" then
            ImGui.Separator(ctx)
            ImGui.Text(ctx, 'Status: ' .. status_message)
        end
        
        -- Preview section - always show
        if #preview_items > 0 then
            ImGui.Separator(ctx)
            ImGui.Text(ctx, string.format('Preview (%d items):', #preview_items))
            
            -- Use a table for better layout of long text
            -- Calculate height needed for all items (max 300px with scroll)
            local item_height = 20
            local needed_height = math.min(#preview_items * item_height + 10, 300)
            
            if ImGui.BeginTable(ctx, 'PreviewTable', 1, ImGui.TableFlags_Borders | ImGui.TableFlags_ScrollY, 0, needed_height) then
                for i, item_data in ipairs(preview_items) do
                    ImGui.TableNextRow(ctx)
                    ImGui.TableNextColumn(ctx)
                    
                    local changed = item_data.original_name ~= item_data.new_name
                    local type_prefix = item_data.type == "track" and "[TRACK] " or "[ITEM] "
                    
                    if changed then
                        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4040FF) -- Red for original
                        ImGui.Text(ctx, string.format("%d. %s%s", i, type_prefix, item_data.original_name))
                        ImGui.PopStyleColor(ctx)
                        
                        ImGui.SameLine(ctx)
                        ImGui.Text(ctx, ' → ')
                        ImGui.SameLine(ctx)
                        
                        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00C8) -- Green for final result
                        ImGui.Text(ctx, item_data.new_name)
                        ImGui.PopStyleColor(ctx)
                    else
                        ImGui.Text(ctx, string.format("%d. %s%s", i, type_prefix, item_data.original_name))
                    end
                end
                ImGui.EndTable(ctx)
            end
        end
        
        ImGui.End(ctx)
    end
    
    if open then
        reaper.defer(Loop)
    end
end

-- Start the script
Init()
reaper.defer(Loop)

