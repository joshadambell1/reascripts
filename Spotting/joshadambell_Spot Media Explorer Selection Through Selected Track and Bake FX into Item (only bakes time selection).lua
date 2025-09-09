-- @description Spot Media Explorer Selection Through Selected Track and Bake FX into Item (only bakes time selection)
-- @version 1.0
-- @author joshadambell
-- @links Website https://joshadambell.com
-- @changelog
--   + First public release
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
--   - Resets playback params after baking
--   - Undoable
--
--   ## Issues
--   - "Please select a track first" = select a track first
--   - "No file selected in Media Explorer" = preview a file first  
--   - No FX processing = add FX to preview track

function main()
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
    local source_length = reaper.GetMediaSourceLength(source, false)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", source_length)
    
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
    local original_source = reaper.PCM_Source_CreateFromFile(filename)
    local full_source_length = reaper.GetMediaSourceLength(original_source, false)
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
    
    -- Now render the trimmed item through track/take FX
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(40209, 0) -- Item: Apply track/take FX to items
    
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

