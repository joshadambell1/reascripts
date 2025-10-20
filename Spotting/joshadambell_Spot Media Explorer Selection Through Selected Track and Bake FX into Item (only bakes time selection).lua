-- @description Spot Media Explorer Selection Through Selected Track and Bake FX into Item (only bakes time selection)
-- @version 1.2
-- @author joshadambell
-- @links Website https://joshadambell.com
-- @changelog
--   + Added validation warnings: SWS check, FX bypass check, render failure detection
-- @about
--   # Media Explorer Spotting Scripts
--
--   Replaces Soundminer's "Spot through DSP Rack" functionality.
--   Preview audio through FX and spot processed files onto your timeline.
--
--   Takes the last played file from Media Explorer, processes it through FX on a preview track,
--   then places the final item on your selected track at the cursor.
--
--   Two versions available:
--   - "only bakes time selection" - Trims to Media Explorer selection first, then processes
--     (more efficient, bakes only the time selection from Media Explorer)
--   - "bakes whole file" - Processes entire file through FX, then trims to selection
--     (bakes full file for more flexibility later)
--
--   ## Setup
--   1. Create track named "Media Explorer Preview"
--   2. Add FX to that track
--   3. In Media Explorer Options, set playback to
--      "Play through first track named 'Media Explorer Preview' or first selected track"
--   4. Install scripts: Actions → Show Action List → Load → select .lua files
--   5. (Optional) Install SWS Extension for sample rate preservation
--
--   ## Usage
--   1. Preview files in Media Explorer (plays through FX track)
--   2. Move cursor to where you want the sound
--   3. Select destination track
--   4. Run script
--   5. Processed audio appears on selected track
--
--   ## What it does
--   - Bakes FX from preview track into final audio
--   - Respects Media Explorer time selections
--   - Keeps Media Explorer rate/pitch/volume settings
--   - Preserves source file sample rate (with SWS)
--   - Validates FX are active and render succeeded
--   - Resets playback params after baking
--   - Undoable
--
--   ## Issues
--   - "Please select a track first" = select a track first
--   - "No file selected in Media Explorer" = preview a file first
--   - No FX processing = add FX to preview track

-- Check if SWS extension is available
function check_sws_available()
    if not reaper.SNM_GetIntConfigVar then
        local result = reaper.ShowMessageBox(
            "SWS Extension not detected.\n\n" ..
            "Sample rate preservation requires SWS Extension.\n" ..
            "The script will continue but may not preserve the source file's sample rate.\n\n" ..
            "Install SWS from: www.sws-extension.org\n\n" ..
            "Continue anyway?",
            "SWS Extension Not Found",
            4  -- Yes/No buttons
        )
        return result == 6  -- 6 = Yes
    end
    return true
end

-- Check if preview track has active (non-bypassed) FX
function check_preview_track_fx(preview_track)
    local fx_count = reaper.TrackFX_GetCount(preview_track)

    if fx_count == 0 then
        local result = reaper.ShowMessageBox(
            "Preview track has no FX loaded.\n\n" ..
            "The spotted audio will be dry (no processing).\n\n" ..
            "Continue anyway?",
            "No FX Detected",
            4  -- Yes/No buttons
        )
        return result == 6  -- 6 = Yes
    end

    local active_fx_count = 0
    for i = 0, fx_count - 1 do
        if reaper.TrackFX_GetEnabled(preview_track, i) then
            active_fx_count = active_fx_count + 1
        end
    end

    if active_fx_count == 0 then
        local result = reaper.ShowMessageBox(
            "All FX on preview track are bypassed.\n\n" ..
            "The spotted audio will be dry (no processing).\n\n" ..
            "Continue anyway?",
            "All FX Bypassed",
            4  -- Yes/No buttons
        )
        return result == 6  -- 6 = Yes
    end

    return true
end

-- Validate render succeeded by checking take count
function validate_render(item, take_count_before)
    reaper.UpdateArrange()
    local take_count_after = reaper.CountTakes(item)

    if take_count_after > take_count_before then
        return true
    else
        reaper.ShowMessageBox(
            "Render failed - no new take was created.\n\n" ..
            "This may indicate a problem with the FX chain or REAPER's render system.\n" ..
            "Script will abort.",
            "Render Failed",
            0  -- OK button
        )
        return false
    end
end

function main()
    -- Check if SWS extension is available
    if not check_sws_available() then
        return  -- User chose to cancel
    end

    -- Get the currently selected track (destination for final item)
    local destination_track = reaper.GetSelectedTrack(0, 0)
    if not destination_track then
        reaper.ShowMessageBox("Please select a track first", "Error", 0)
        return
    end
    
    -- Find or create "Media Explorer Preview" track
    local preview_track = nil
    local track_count = reaper.CountTracks(0)
    
    -- Search for existing "Media Explorer Preview" track
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local retval, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == "Media Explorer Preview" then
            preview_track = track
            break
        end
    end
    
    -- Create the track if it doesn't exist
    if not preview_track then
        reaper.InsertTrackAtIndex(track_count, false)
        preview_track = reaper.GetTrack(0, track_count)
        reaper.GetSetMediaTrackInfo_String(preview_track, "P_NAME", "Media Explorer Preview", true)
    end

    -- Check if preview track has active FX
    if not check_preview_track_fx(preview_track) then
        return  -- User chose to cancel
    end

    -- Get media explorer last played file info using correct API documentation
    local retval, filename, filemode, selstart, selend, pitchshift, voladj, rateadj, sourcebpm, extrainfo = reaper.MediaExplorerGetLastPlayedFileInfo()

    if not retval then
        reaper.ShowMessageBox("No file selected in Media Explorer", "Error", 0)
        return
    end
    
    -- Begin undo block
    reaper.Undo_BeginBlock()
    
    -- Get current edit cursor position
    local cursor_pos = reaper.GetCursorPosition()
    
    -- Create new media item on the preview track at cursor position
    local item = reaper.AddMediaItemToTrack(preview_track)
    local take = reaper.AddTakeToMediaItem(item)
    
    -- Set the source file for the take
    local source = reaper.PCM_Source_CreateFromFile(filename)
    if source then
        reaper.SetMediaItemTake_Source(take, source)
    else
        reaper.ShowMessageBox("Failed to create source from file", "Error", 0)
        return
    end
    
    -- Set item position at cursor
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", cursor_pos)
    
    -- Set item length to full source length
    reaper.UpdateItemInProject(item)

    local auto_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if auto_length > 0 then
    else
        local retval, chunk = reaper.GetItemStateChunk(item, "", false)
        if retval then
            local file_path = chunk:match('FILE "([^"]+)"')
            if file_path then
                local temp_source = reaper.PCM_Source_CreateFromFile(file_path)
                if temp_source then
                    local success, length = pcall(reaper.GetMediaSourceLength, temp_source)
                    if success and length > 0 then
                        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
                    else
                        reaper.ShowMessageBox("Still cannot get source length", "Error", 0)
                        return
                    end
                    reaper.PCM_Source_Destroy(temp_source)
                end
            end
        end
    end
    
    -- Set item name to just the filename (without path)
    local just_filename = filename:match("([^\\]+)$")
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", just_filename, true)
    
    -- Apply Media Explorer rate and volume settings to the take
    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rateadj)
    reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", voladj)
    reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitchshift)
    
    -- Store original position for later restoration
    local original_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    
    -- Get original source length for accurate percentage calculations
    local full_source_length
    local temp_source = reaper.PCM_Source_CreateFromFile(filename)
    if temp_source then
        local success, length = pcall(reaper.GetMediaSourceLength, temp_source)
        if not success or not length or length <= 0 then
            reaper.ShowMessageBox("Could not get original source length for calculations", "Error", 0)
            reaper.PCM_Source_Destroy(temp_source)
            return
        end
        full_source_length = length
        reaper.PCM_Source_Destroy(temp_source)
    else
        reaper.ShowMessageBox("Could not create temporary source for length calculation", "Error", 0)
        return
    end
    local current_take = reaper.GetActiveTake(item)

    -- Convert Media Explorer percentage-based selection to actual time values
    local actual_start_time = selstart * full_source_length
    local actual_end_time = selend * full_source_length
    local selection_length = actual_end_time - actual_start_time
    
    -- Adjust for playback rate: faster rate = shorter rendered duration
    local rate_adjusted_start_time = actual_start_time / rateadj
    local rate_adjusted_selection_length = selection_length / rateadj

    -- Trim item to Media Explorer time selection if one exists
    if selection_length > 0 and selection_length < full_source_length then
        -- reaper.ShowConsoleMsg("Trimming item to selection\n") -- Debug
        if current_take then
            -- Set item length to original selection (before rate adjustment)
            reaper.SetMediaItemInfo_Value(item, "D_LENGTH", selection_length)
            
            -- Set take start offset to selection start
            reaper.SetMediaItemTakeInfo_Value(current_take, "D_STARTOFFS", actual_start_time)
            
            -- Restore item to original position
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", original_position)
        end
    end
    
    -- Preserve source sample rate during FX rendering
    -- Get source file's sample rate
    local take_source = reaper.GetMediaItemTake_Source(current_take)
    local source_samplerate = reaper.GetMediaSourceSampleRate(take_source)

    -- Store current project sample rate (only if SWS is available)
    local original_project_sr = nil
    if reaper.SNM_GetIntConfigVar then
        original_project_sr = reaper.SNM_GetIntConfigVar("projsrate", 0)

        -- Temporarily set project sample rate to match source file
        if source_samplerate and source_samplerate > 0 then
            reaper.SNM_SetIntConfigVar("projsrate", math.floor(source_samplerate))
        end
    end

    -- Store take count before rendering for validation
    local take_count_before = reaper.CountTakes(item)

    -- Now render the trimmed item through track/take FX
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(40209, 0) -- Item: Apply track/take FX to items

    -- Validate render succeeded
    if not validate_render(item, take_count_before) then
        -- Restore project sample rate before aborting
        if original_project_sr and original_project_sr > 0 then
            reaper.SNM_SetIntConfigVar("projsrate", original_project_sr)
        end
        reaper.Undo_EndBlock("Spot Media Explorer selection (failed)", -1)
        return
    end

    -- Restore original project sample rate (only if SWS is available)
    if original_project_sr and original_project_sr > 0 then
        reaper.SNM_SetIntConfigVar("projsrate", original_project_sr)
    end
    
    -- Remove the original take, keeping only the rendered one
    local original_take = reaper.GetMediaItemTake(item, 0)
    if original_take then
        reaper.GetSetMediaItemTakeInfo_String(original_take, "P_NAME", "", false)
        reaper.Main_OnCommand(40131, 0) -- Take: Delete active take from items
    end
    
    -- Get the final rendered take and reset rate/volume since they're baked in
    local final_take = reaper.GetActiveTake(item)
    if final_take then
        reaper.SetMediaItemTakeInfo_Value(final_take, "D_PLAYRATE", 1.0)
        reaper.SetMediaItemTakeInfo_Value(final_take, "D_VOL", 1.0)
        reaper.SetMediaItemTakeInfo_Value(final_take, "D_PITCH", 0.0)
    end
    
    -- Move the item to the destination track
    reaper.MoveMediaItemToTrack(item, destination_track)
    
    -- Update the timeline
    reaper.UpdateTimeline()
    
    -- End undo block
    reaper.Undo_EndBlock("Spot Media Explorer selection through track with FX (selection only)", -1)
end

-- Run the script
main()

