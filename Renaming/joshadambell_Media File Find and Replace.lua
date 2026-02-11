-- @description Media File Find & Replace
-- @version 1.0
-- @author joshadambell
-- @dependencies ReaImGui extension
-- @links Website https://joshadambell.com
-- @changelog
--   + First public release
-- @about
--   # Media File Find & Replace
--
--   Batch rename and manage media files in your project's media folder.
--   Renames files on disk and updates all item references in the open project.
--
--   ## Requirements
--   - ReaImGui extension (install via ReaPack)
--
--   ## Usage
--   1. Open your REAPER project
--   2. Run script to open GUI
--   3. Use Find/Replace, Prepend, Append, or Trim modes
--   4. Preview changes in the table below
--   5. Click "Apply Rename" to rename files and update project references
--   6. Save your project to persist changes

-- Dependency check
if not reaper.ImGui_GetBuiltinPath then
    reaper.MB(
        "This script requires the ReaImGui extension.\n\n" ..
        "Install it via ReaPack:\n" ..
        "  Extensions > ReaPack > Browse packages\n" ..
        "  Search for 'ReaImGui'\n" ..
        "  Install, then restart REAPER.",
        "Missing Dependency", 0)
    return
end

-- Import ReaImGui
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

-- Script state
local ctx = ImGui.CreateContext('Media File Find & Replace')
local find_text = ""
local replace_text = ""
local case_sensitive = false
local status_message = ""
local status_is_error = false
local media_files = {}
local rpp_dir = ""
local media_subdir = ""
local media_path = ""
local needs_scan = true
local needs_auto_detect = true

-- Rename modes
local MODE_FIND_REPLACE = 1
local MODE_PREPEND = 2
local MODE_APPEND = 3
local MODE_TRIM_START = 4
local MODE_TRIM_END = 5
local rename_mode = MODE_FIND_REPLACE
local prepend_text = ""
local append_text = ""
local trim_start_n = 0
local trim_end_n = 0
local update_take_names = true

local SEP = package.config:sub(1, 1)
local CHUNK_BUF = string.rep(" ", 10 * 1024 * 1024)

-- Normalize a path: collapse duplicate separators, strip trailing sep
local function NormalizePath(path)
    if not path or path == "" then return "" end
    path = path:gsub("[/\\]", SEP)
    if SEP == "\\" then
        local prefix = ""
        if path:match("^\\\\") then
            prefix = "\\\\"
            path = path:sub(3)
        end
        path = prefix .. path:gsub("\\\\+", "\\")
    else
        path = path:gsub("//+", "/")
    end
    if #path > 1 then
        path = path:gsub("[/\\]+$", "")
    end
    return path
end

-- Join path components safely
local function JoinPath(a, b)
    if a == "" then return NormalizePath(b) end
    if b == "" then return NormalizePath(a) end
    return NormalizePath(a .. SEP .. b)
end

local function DirExists(path)
    path = NormalizePath(path)
    local result = reaper.EnumerateFiles(path, 0)
    if result then return true end
    local subresult = reaper.EnumerateSubdirectories(path, 0)
    if subresult then return true end
    return false
end

local function FileExists(filepath)
    return reaper.file_exists(filepath)
end

-- Rename a file, with ExecProcess fallback
local function RenameFile(old_path, new_path)
    local ok, err = os.rename(old_path, new_path)
    if ok then return true end

    if SEP == "\\" then
        local cmd = string.format('cmd.exe /C move /Y "%s" "%s"', old_path, new_path)
        local ret = reaper.ExecProcess(cmd, 10000)
        if ret then
            local exit_code = tonumber(ret:match("^(%d+)"))
            if exit_code == 0 then return true end
        end
    else
        local cmd = string.format('/bin/mv -f "%s" "%s"', old_path, new_path)
        local ret = reaper.ExecProcess(cmd, 10000)
        if ret then
            local exit_code = tonumber(ret:match("^(%d+)"))
            if exit_code == 0 then return true end
        end
    end

    return false, err or "rename failed"
end

-- Case-insensitive plain-text find/replace
local function FindReplaceText(original, find_str, replace_str, is_case_sensitive)
    if find_str == "" then return original end
    if is_case_sensitive then
        local escaped_find = find_str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local escaped_replace = replace_str:gsub("%%", "%%%%")
        return original:gsub(escaped_find, escaped_replace)
    else
        local lower_original = original:lower()
        local lower_find = find_str:lower()
        local result = ""
        local start_pos = 1
        while true do
            local find_start, find_end = lower_original:find(lower_find, start_pos, true)
            if not find_start then
                result = result .. original:sub(start_pos)
                break
            end
            result = result .. original:sub(start_pos, find_start - 1) .. replace_str
            start_pos = find_end + 1
        end
        return result
    end
end

-- Recursively scan a directory using REAPER APIs
local function ScanDirectory(dir, file_list)
    dir = NormalizePath(dir)
    local idx = 0
    while true do
        local filename = reaper.EnumerateFiles(dir, idx)
        if not filename then break end
        table.insert(file_list, {dir = dir, name = filename})
        idx = idx + 1
    end
    idx = 0
    while true do
        local subdir = reaper.EnumerateSubdirectories(dir, idx)
        if not subdir then break end
        ScanDirectory(JoinPath(dir, subdir), file_list)
        idx = idx + 1
    end
end

-- Build a map of filename -> {items, takes} from all project items
local function BuildReferenceMap()
    local ref_map = {}
    local item_count = reaper.CountMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetMediaItem(0, i)
        local take_count = reaper.CountTakes(item)
        for t = 0, take_count - 1 do
            local take = reaper.GetTake(item, t)
            if take then
                local source = reaper.GetMediaItemTake_Source(take)
                if source then
                    local filepath = reaper.GetMediaSourceFileName(source, "")
                    if filepath and filepath ~= "" then
                        local fn = filepath:match("[/\\]([^/\\]+)$") or filepath
                        local key = fn:lower()
                        if not ref_map[key] then
                            ref_map[key] = { items = {}, takes = {} }
                        end
                        table.insert(ref_map[key].items, item)
                        table.insert(ref_map[key].takes, take)
                    end
                end
            end
        end
    end
    return ref_map
end

-- Auto-detect the media subfolder relative to the .rpp directory
local function AutoDetectMediaSubdir()
    local retval, proj_path = reaper.EnumProjects(-1)
    if not proj_path or proj_path == "" then return nil end
    local dir = NormalizePath(proj_path:match("^(.*)[/\\]") or "")
    local rpp_name = proj_path:match("([^/\\]+)%.[rR][pP][pP]$") or ""

    if rpp_name ~= "" then
        local candidate = rpp_name .. "_media"
        if DirExists(JoinPath(dir, candidate)) then return candidate end
    end

    local common = {"Media Files", "media", "Audio", "audio", "Media"}
    for _, name in ipairs(common) do
        if DirExists(JoinPath(dir, name)) then return name end
    end

    local proj_rec_path = reaper.GetProjectPath("")
    if proj_rec_path ~= "" and DirExists(proj_rec_path) then
        proj_rec_path = NormalizePath(proj_rec_path)
        local prefix = dir .. SEP
        if proj_rec_path:sub(1, #prefix):lower() == prefix:lower() then
            return proj_rec_path:sub(#prefix + 1)
        end
        return proj_rec_path
    end
    return nil
end

-- Scan the project media folder and collect file info + references
local function ScanMediaFiles()
    media_files = {}

    local retval, proj_path = reaper.EnumProjects(-1)
    if not proj_path or proj_path == "" then
        status_message = "No project is open or project is not saved!"
        status_is_error = true
        return
    end

    rpp_dir = NormalizePath(proj_path:match("^(.*)[/\\]") or "")

    if needs_auto_detect then
        needs_auto_detect = false
        local detected = AutoDetectMediaSubdir()
        if detected then media_subdir = detected end
    end

    local clean_subdir = media_subdir:gsub("^[/\\%s]+", ""):gsub("[/\\%s]+$", "")
    if clean_subdir == "" then
        status_message = "Enter a media folder path relative to the project file."
        status_is_error = true
        media_path = ""
        return
    end

    local resolved
    if clean_subdir:match("^[A-Za-z]:") or clean_subdir:match("^[/\\][/\\]") then
        resolved = NormalizePath(clean_subdir)
    else
        resolved = JoinPath(rpp_dir, clean_subdir)
    end

    if not DirExists(resolved) then
        status_message = "Media folder not found: " .. resolved
        status_is_error = true
        media_path = ""
        return
    end
    media_path = resolved

    local all_files = {}
    ScanDirectory(media_path, all_files)

    local non_peak_files = {}
    for _, entry in ipairs(all_files) do
        if not entry.name:lower():match("%.reapeaks$") then
            table.insert(non_peak_files, entry)
        end
    end

    local ref_map = BuildReferenceMap()

    local seen = {}
    for _, entry in ipairs(non_peak_files) do
        local key = (entry.dir .. SEP .. entry.name):lower()
        if not seen[key] then
            seen[key] = true
            local fn = entry.name
            local stem, ext = fn:match("^(.+)(%.%w+)$")
            if not stem then stem = fn; ext = "" end
            local refs = {}
            local ref_takes = {}
            local ref_entry = ref_map[fn:lower()]
            if ref_entry then
                refs = ref_entry.items
                ref_takes = ref_entry.takes
            end

            table.insert(media_files, {
                filedir  = entry.dir,
                stem = stem,
                ext = ext,
                new_stem = stem,
                refs = refs,
                takes = ref_takes,
                excluded = false,
            })
        end
    end

    table.sort(media_files, function(a, b)
        return (a.stem .. a.ext):lower() < (b.stem .. b.ext):lower()
    end)

    status_message = string.format("Scanned %d media files (%s)", #media_files, media_path)
    status_is_error = false
end

-- Apply the current rename mode to a stem
local function ApplyRenameMode(stem)
    if rename_mode == MODE_FIND_REPLACE then
        return FindReplaceText(stem, find_text, replace_text, case_sensitive)
    elseif rename_mode == MODE_PREPEND then
        if prepend_text == "" then return stem end
        return prepend_text .. stem
    elseif rename_mode == MODE_APPEND then
        if append_text == "" then return stem end
        return stem .. append_text
    elseif rename_mode == MODE_TRIM_START then
        if trim_start_n <= 0 or trim_start_n >= #stem then return stem end
        return stem:sub(trim_start_n + 1)
    elseif rename_mode == MODE_TRIM_END then
        if trim_end_n <= 0 or trim_end_n >= #stem then return stem end
        return stem:sub(1, #stem - trim_end_n)
    end
    return stem
end

-- Update preview
local function UpdatePreview()
    local change_count = 0
    for _, f in ipairs(media_files) do
        f.new_stem = ApplyRenameMode(f.stem)
        if f.new_stem ~= f.stem and not f.excluded then
            change_count = change_count + 1
        end
    end
    return change_count
end

-- Check for naming conflicts
local function CheckConflicts()
    local targets = {}
    local conflicts = {}
    for i, f in ipairs(media_files) do
        if f.new_stem ~= f.stem and not f.excluded then
            local target_fn = (f.new_stem .. f.ext):lower()
            if targets[target_fn] then
                table.insert(conflicts, string.format(
                    "'%s%s' and '%s%s' both rename to '%s%s'",
                    media_files[targets[target_fn]].stem, media_files[targets[target_fn]].ext,
                    f.stem, f.ext, f.new_stem, f.ext))
            else
                targets[target_fn] = i
            end
        end
    end
    return conflicts
end

-- Replace a filename within FILE directives in a REAPER state chunk
local function ReplaceInChunk(chunk, old_filename, new_filename)
    local escaped_old = old_filename:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local escaped_new = new_filename:gsub("%%", "%%%%")
    local new_chunk = chunk:gsub(
        '(FILE%s+"[^"]*[/\\])' .. escaped_old .. '(")',
        '%1' .. escaped_new .. '%2')
    if new_chunk == chunk then
        new_chunk = chunk:gsub(
            '(FILE%s+")' .. escaped_old .. '(")',
            '%1' .. escaped_new .. '%2')
    end
    return new_chunk
end

-- Delete a file, with ExecProcess fallback
local function DeleteFile(path)
    local ok, err = os.remove(path)
    if ok then return true end

    if SEP == "\\" then
        local cmd = string.format('cmd.exe /C del /F /Q "%s"', path)
        local ret = reaper.ExecProcess(cmd, 10000)
        if ret then
            local exit_code = tonumber(ret:match("^(%d+)"))
            if exit_code == 0 then return true end
        end
    else
        local cmd = string.format('/bin/rm -f "%s"', path)
        local ret = reaper.ExecProcess(cmd, 10000)
        if ret then
            local exit_code = tonumber(ret:match("^(%d+)"))
            if exit_code == 0 then return true end
        end
    end

    return false, err or "delete failed"
end

-- Remove unreferenced media files from the media folder
local function RemoveUnreferencedMedia()
    local unreferenced = {}
    for _, f in ipairs(media_files) do
        if #f.refs == 0 then
            table.insert(unreferenced, f)
        end
    end

    if #unreferenced == 0 then
        status_message = "No unreferenced media files found."
        status_is_error = false
        return
    end

    local msg = string.format(
        "This will permanently delete %d unreferenced media file%s from:\n%s\n\n",
        #unreferenced,
        #unreferenced == 1 and "" or "s",
        media_path)

    local max_show = 15
    for i, f in ipairs(unreferenced) do
        if i > max_show then
            msg = msg .. string.format("  ... and %d more\n", #unreferenced - max_show)
            break
        end
        msg = msg .. "  " .. f.stem .. f.ext .. "\n"
    end

    msg = msg .. "\nThis cannot be undone. Continue?"

    local confirm = reaper.MB(msg, "Remove Unreferenced Media", 1)
    if confirm ~= 1 then
        status_message = "Cancelled."
        status_is_error = false
        return
    end

    local deleted_count = 0
    local errors = {}

    for _, f in ipairs(unreferenced) do
        local filepath = JoinPath(f.filedir, f.stem .. f.ext)
        local ok, err = DeleteFile(filepath)
        if ok then
            deleted_count = deleted_count + 1
            local peak_path = filepath .. ".reapeaks"
            if FileExists(peak_path) then
                DeleteFile(peak_path)
            end
        else
            table.insert(errors, string.format("'%s': %s", f.stem .. f.ext, err or "unknown"))
        end
    end

    ScanMediaFiles()

    if #errors > 0 then
        status_message = string.format("Deleted %d files. ERRORS: %s",
            deleted_count, errors[1])
        status_is_error = true
    else
        status_message = string.format("Deleted %d unreferenced file%s.",
            deleted_count, deleted_count == 1 and "" or "s")
        status_is_error = false
    end
end

-- Apply the rename
-- Order: update chunks first (releases file handles), then rename on disk
local function ApplyRename()
    if rename_mode == MODE_FIND_REPLACE and find_text == "" then
        status_message = "Find text cannot be empty!"
        status_is_error = true
        return
    end

    local change_count = UpdatePreview()
    if change_count == 0 then
        status_message = "No files would be changed."
        status_is_error = true
        return
    end

    local conflicts = CheckConflicts()
    if #conflicts > 0 then
        status_message = "CONFLICT: " .. conflicts[1]
        status_is_error = true
        return
    end

    for _, f in ipairs(media_files) do
        if f.new_stem ~= f.stem and not f.excluded then
            local old_fn = f.stem .. f.ext
            local new_fn = f.new_stem .. f.ext
            local old_path = JoinPath(f.filedir, old_fn)
            local new_path = JoinPath(f.filedir, new_fn)

            if old_path:lower() ~= new_path:lower() then
                if FileExists(new_path) then
                    status_message = string.format("Target already exists: %s", new_fn)
                    status_is_error = true
                    return
                end
            end
        end
    end

    reaper.Undo_BeginBlock()

    local renamed_count = 0
    local ref_updated_count = 0
    local peak_warnings = 0
    local errors = {}

    local renames = {}
    for _, f in ipairs(media_files) do
        if f.new_stem ~= f.stem and not f.excluded then
            local old_fn = f.stem .. f.ext
            local new_fn = f.new_stem .. f.ext
            table.insert(renames, {
                old_fn = old_fn,
                new_fn = new_fn,
                new_stem = f.new_stem,
                old_path = JoinPath(f.filedir, old_fn),
                new_path = JoinPath(f.filedir, new_fn),
                filedir = f.filedir,
                refs = f.refs,
                takes = f.takes,
            })
        end
    end

    -- PASS 1: Update item state chunks (releases file handles)
    local updated_items = {}
    for _, r in ipairs(renames) do
        for _, item in ipairs(r.refs) do
            local item_id = tostring(item)
            if not updated_items[item_id] then
                updated_items[item_id] = true
                local retval, chunk = reaper.GetItemStateChunk(item, CHUNK_BUF, false)
                if retval and #chunk < #CHUNK_BUF then
                    local new_chunk = ReplaceInChunk(chunk, r.old_fn, r.new_fn)
                    if new_chunk ~= chunk then
                        reaper.SetItemStateChunk(item, new_chunk, false)
                        ref_updated_count = ref_updated_count + 1
                    end
                end
            end
        end
    end

    reaper.UpdateArrange()

    -- PASS 2: Rename files on disk
    for _, r in ipairs(renames) do
        if not FileExists(r.old_path) then
            reaper.ShowConsoleMsg(string.format(
                "[Media F&R] File not found (already renamed?):\n  %s\n", r.old_path))
            table.insert(errors, string.format(
                "Skipped: '%s' — not found", r.old_fn))
        else
            local ok, err
            if r.old_path:lower() == r.new_path:lower() then
                local tmp_path = r.old_path .. ".rename_tmp"
                ok, err = RenameFile(r.old_path, tmp_path)
                if ok then
                    ok, err = RenameFile(tmp_path, r.new_path)
                    if not ok then RenameFile(tmp_path, r.old_path) end
                end
            else
                ok, err = RenameFile(r.old_path, r.new_path)
            end

            if not ok then
                reaper.ShowConsoleMsg(string.format(
                    "[Media F&R] RENAME FAILED:\n  from: %s\n  to:   %s\n  err:  %s\n",
                    r.old_path, r.new_path, err or "unknown"))
                table.insert(errors, string.format(
                    "Failed: '%s' -> '%s' (%s)", r.old_fn, r.new_fn, err or "unknown"))
                for _, item in ipairs(r.refs) do
                    local retval, chunk = reaper.GetItemStateChunk(item, CHUNK_BUF, false)
                    if retval and #chunk < #CHUNK_BUF then
                        local reverted = ReplaceInChunk(chunk, r.new_fn, r.old_fn)
                        if reverted ~= chunk then
                            reaper.SetItemStateChunk(item, reverted, false)
                        end
                    end
                end
            else
                renamed_count = renamed_count + 1

                if update_take_names then
                    for _, take in ipairs(r.takes) do
                        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", r.new_stem, true)
                    end
                end

                local old_peak = r.old_path .. ".reapeaks"
                local new_peak = r.new_path .. ".reapeaks"
                if FileExists(old_peak) then
                    if not RenameFile(old_peak, new_peak) then
                        peak_warnings = peak_warnings + 1
                    end
                end
            end
        end
    end

    reaper.Undo_EndBlock("Media File Find & Replace", -1)
    reaper.UpdateArrange()

    local result_msg, result_err
    if #errors > 0 then
        result_msg = string.format("Renamed %d files (%d refs updated). ERRORS: %s",
            renamed_count, ref_updated_count, errors[1])
        result_err = true
    else
        result_msg = string.format("Renamed %d files, updated %d item references.",
            renamed_count, ref_updated_count)
        if peak_warnings > 0 then
            result_msg = result_msg .. string.format(
                " (%d peak files locked — will regenerate on reload.)", peak_warnings)
        end
        result_msg = result_msg .. " Save your project, then minimise and maximise REAPER!"
        result_err = false
    end

    ScanMediaFiles()
    status_message = result_msg
    status_is_error = result_err
end

-- Main GUI loop
local function Loop()
    if needs_scan then
        needs_scan = false
        ScanMediaFiles()
    end

    ImGui.SetNextWindowSize(ctx, 1225, 875, ImGui.Cond_FirstUseEver)
    local visible, open = ImGui.Begin(ctx, 'Media File Find & Replace', true,
        ImGui.WindowFlags_NoCollapse)

    if visible then
        ImGui.Text(ctx, 'Project:')
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, 0xAAAAAAFF, rpp_dir ~= "" and rpp_dir or "(no project saved)")

        ImGui.Text(ctx, 'Media folder:')
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 300)
        local subdir_changed, new_subdir = ImGui.InputText(ctx, '##media_subdir', media_subdir,
            ImGui.InputTextFlags_EnterReturnsTrue)
        ImGui.PopItemWidth(ctx)
        if subdir_changed then
            media_subdir = new_subdir
            needs_scan = true
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, 'Scan') then
            needs_scan = true
        end
        ImGui.SameLine(ctx, 0, 20)
        if ImGui.Button(ctx, 'Delete unreferenced media from the media folder') then RemoveUnreferencedMedia() end
        if media_path ~= "" then
            ImGui.TextColored(ctx, 0x888888FF, media_path)
        end

        ImGui.Separator(ctx)

        -- Mode selector
        local mode_names = {"Find/Replace", "Prepend", "Append", "Trim Start", "Trim End"}
        for m = 1, #mode_names do
            if m > 1 then ImGui.SameLine(ctx) end
            local is_active = (rename_mode == m)
            if is_active then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x4080FFFF)
            end
            if ImGui.Button(ctx, mode_names[m]) then rename_mode = m end
            if is_active then
                ImGui.PopStyleColor(ctx)
            end
        end

        -- Mode-specific inputs
        if rename_mode == MODE_FIND_REPLACE then
            ImGui.Text(ctx, 'Find:')
            ImGui.SameLine(ctx, 70)
            ImGui.PushItemWidth(ctx, -1)
            local find_changed, new_find = ImGui.InputText(ctx, '##find', find_text)
            ImGui.PopItemWidth(ctx)
            if find_changed then find_text = new_find end

            ImGui.Text(ctx, 'Replace:')
            ImGui.SameLine(ctx, 70)
            ImGui.PushItemWidth(ctx, -1)
            local replace_changed, new_replace = ImGui.InputText(ctx, '##replace', replace_text)
            ImGui.PopItemWidth(ctx)
            if replace_changed then replace_text = new_replace end

            local case_changed, new_case = ImGui.Checkbox(ctx, 'Case Sensitive', case_sensitive)
            if case_changed then case_sensitive = new_case end

        elseif rename_mode == MODE_PREPEND then
            ImGui.Text(ctx, 'Prepend:')
            ImGui.SameLine(ctx, 70)
            ImGui.PushItemWidth(ctx, -1)
            local changed, val = ImGui.InputText(ctx, '##prepend', prepend_text)
            ImGui.PopItemWidth(ctx)
            if changed then prepend_text = val end

        elseif rename_mode == MODE_APPEND then
            ImGui.Text(ctx, 'Append:')
            ImGui.SameLine(ctx, 70)
            ImGui.PushItemWidth(ctx, -1)
            local changed, val = ImGui.InputText(ctx, '##append', append_text)
            ImGui.PopItemWidth(ctx)
            if changed then append_text = val end

        elseif rename_mode == MODE_TRIM_START then
            ImGui.Text(ctx, 'Remove:')
            ImGui.SameLine(ctx, 70)
            ImGui.PushItemWidth(ctx, 100)
            local changed, val = ImGui.InputInt(ctx, '##trim_start', trim_start_n)
            ImGui.PopItemWidth(ctx)
            if changed then trim_start_n = math.max(0, val) end
            ImGui.SameLine(ctx)
            ImGui.TextColored(ctx, 0x888888FF, 'characters from start')

        elseif rename_mode == MODE_TRIM_END then
            ImGui.Text(ctx, 'Remove:')
            ImGui.SameLine(ctx, 70)
            ImGui.PushItemWidth(ctx, 100)
            local changed, val = ImGui.InputInt(ctx, '##trim_end', trim_end_n)
            ImGui.PopItemWidth(ctx)
            if changed then trim_end_n = math.max(0, val) end
            ImGui.SameLine(ctx)
            ImGui.TextColored(ctx, 0x888888FF, 'characters from end')
        end

        ImGui.Separator(ctx)

        if ImGui.Button(ctx, 'Apply Rename') then ApplyRename() end
        ImGui.SameLine(ctx, 0, 20)
        local take_changed, take_val = ImGui.Checkbox(ctx, 'Update item names to match', update_take_names)
        if take_changed then update_take_names = take_val end

        if status_message ~= "" then
            ImGui.SameLine(ctx)
            if status_is_error then
                ImGui.TextColored(ctx, 0xFF4040FF, status_message)
            else
                ImGui.TextColored(ctx, 0x00FF00C8, status_message)
            end
        end

        ImGui.Separator(ctx)

        local change_count = UpdatePreview()

        local excluded_count = 0
        for _, f in ipairs(media_files) do
            if f.excluded and f.new_stem ~= f.stem then excluded_count = excluded_count + 1 end
        end
        ImGui.Text(ctx, string.format('Files: %d total, %d will change', #media_files, change_count))
        if excluded_count > 0 then
            ImGui.SameLine(ctx)
            ImGui.TextColored(ctx, 0xFFA500FF,
                string.format('(%d excluded)', excluded_count))
        end
        ImGui.TextColored(ctx, 0x888888FF, 'Click a highlighted row to exclude it from renaming.')

        local table_flags = ImGui.TableFlags_Borders
            | ImGui.TableFlags_ScrollY
            | ImGui.TableFlags_RowBg
            | ImGui.TableFlags_Resizable

        local avail_x, avail_y = ImGui.GetContentRegionAvail(ctx)
        local table_height = math.max(avail_y - 50, 150)

        if ImGui.BeginTable(ctx, 'FilePreview', 3, table_flags, 0, table_height) then
            ImGui.TableSetupColumn(ctx, 'Current Name', ImGui.TableColumnFlags_WidthStretch, 1.0)
            ImGui.TableSetupColumn(ctx, 'New Name', ImGui.TableColumnFlags_WidthStretch, 1.0)
            ImGui.TableSetupColumn(ctx, 'Refs', ImGui.TableColumnFlags_WidthFixed, 40)
            ImGui.TableSetupScrollFreeze(ctx, 0, 1)
            ImGui.TableHeadersRow(ctx)

            for i, f in ipairs(media_files) do
                local changed = f.new_stem ~= f.stem
                ImGui.TableNextRow(ctx)

                local dim = f.excluded
                local text_color = dim and 0x666666FF or (changed and 0xFF4040FF or nil)

                ImGui.TableNextColumn(ctx)
                ImGui.PushID(ctx, i)
                if changed then
                    if text_color then ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color) end
                    local clicked = ImGui.Selectable(ctx, f.stem .. f.ext,
                        f.excluded, ImGui.SelectableFlags_SpanAllColumns)
                    if clicked then f.excluded = not f.excluded end
                    if text_color then ImGui.PopStyleColor(ctx) end
                else
                    ImGui.Text(ctx, f.stem .. f.ext)
                end

                ImGui.TableNextColumn(ctx)
                if dim then
                    ImGui.TextColored(ctx, 0x666666FF, '(excluded)')
                elseif changed then
                    ImGui.TextColored(ctx, 0x00FF00C8, f.new_stem .. f.ext)
                else
                    ImGui.TextColored(ctx, 0x888888FF, '-')
                end

                ImGui.TableNextColumn(ctx)
                local ref_count = #f.refs
                if dim then
                    ImGui.TextColored(ctx, 0x666666FF, tostring(ref_count))
                elseif ref_count > 0 then
                    ImGui.Text(ctx, tostring(ref_count))
                else
                    ImGui.TextColored(ctx, 0x888888FF, '0')
                end
                ImGui.PopID(ctx)
            end

            ImGui.EndTable(ctx)
        end

        ImGui.TextColored(ctx, 0xFFA500FF,
            'WARNING: This script is destructive. Back up your project before using.')
        ImGui.TextColored(ctx, 0x888888FF,
            'After renaming, minimise and maximise REAPER to bring files back online.')

        ImGui.End(ctx)
    end

    if open then reaper.defer(Loop) end
end

ScanMediaFiles()
reaper.defer(Loop)
