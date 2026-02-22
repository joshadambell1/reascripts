--[[
ReaScript name: joshadambell_Folder Track Amplitude Envelope Watchdog.lua
Version: 1.00
Author: joshadambell
Website: https://joshadambell.com
Dependencies: ReaImGui extension
About:
  # Folder Track Amplitude Envelope Watchdog
  
  Generates amplitude-following automation items from folder track audio,
  with a watchdog system that auto-updates linked AIs when source changes.
  
  ## Requirements
  - ReaImGui extension (install via ReaPack)
  - REAPER v7.0 or higher
  
  ## Features
  - Analyzes audio from folder tracks (sums all child track audio)
  - Generates automation items on volume envelopes
  - Links source track to destination AI with auto-update watchdog
  - Links persist across project save/load
  - Monitors child track volumes, item positions, fades, and mute states
]]

-- Init globals
for key in pairs(reaper) do _G[key]=reaper[key] end
local app_vrs = tonumber(GetAppVersion():match('[%d%.]+'))
if app_vrs < 7 then return reaper.MB('This script requires REAPER 7.0+','',0) end

-- ReaImGui setup
if not reaper.ImGui_GetBuiltinPath then 
  return reaper.MB('ReaImGui extension is required for this script.\n\nInstall it via Extensions > ReaPack > Browse packages', 'Missing Dependency', 0) 
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

local ctx = ImGui.CreateContext('Folder Track Amplitude Envelope Watchdog')

-- Settings
local EXT = {
  rms_window = 0.02,          -- analysis window in seconds
  overlap = 1,                -- window overlap multiplier
  gain = 1,                   -- output gain multiplier (1.0 = unity)
  invert = 0,                 -- invert envelope
  dedup_points = 1,           -- remove redundant same-value points
  clamp_edges = 1,            -- force silence at AI boundaries
  point_shape = 0,            -- envelope point shape
  time_offset = 0,            -- shift points in ms
}

local EXT_SECTION = 'FolderTrackAmplitudeWatchdog'

local DATA = {
  link = nil,
  link_fingerprint = nil,
  link_debounce_time = nil,
  link_debounce_sec = 1.5,
}

-- EXT save/load
function EXT:save()
  for key in pairs(EXT) do
    if type(EXT[key]) == 'string' or type(EXT[key]) == 'number' then
      SetExtState(EXT_SECTION, key, EXT[key], true)
    end
  end
end

function EXT:load()
  for key in pairs(EXT) do
    if type(EXT[key]) == 'string' or type(EXT[key]) == 'number' then
      if HasExtState(EXT_SECTION, key) then
        local val = GetExtState(EXT_SECTION, key)
        EXT[key] = tonumber(val) or val
      end
    end
  end
end

-- Audio math
function db2lin(x) return math.exp((x)*0.11512925464970228420089957273422) end
function lin2db(x)
  if not x or x < 0.0000000298023223876953125 then return -150.0 end
  local v = math.log(x)*8.6858896380650365530225783783321
  if v < -150.0 then return -150.0 end
  return v
end

-- Track/folder helpers
function DATA:GetTrackAndChildren(track)
  local tracks = {}
  local track_idx = GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER') - 1
  local track_depth = reaper.GetTrackDepth(track)
  tracks[#tracks+1] = track
  local folder_depth = GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
  if folder_depth == 1 then
    for i = track_idx + 1, CountTracks(0) - 1 do
      local child = GetTrack(0, i)
      local child_depth = reaper.GetTrackDepth(child)
      if child_depth <= track_depth then break end
      tracks[#tracks+1] = child
    end
  end
  return tracks
end

-- Audio data reading
function DATA:Process_GetAudioData(track, boundary_start, boundary_end)
  local window_sec = EXT.rms_window
  if not (track and window_sec) then return end
  if not (boundary_start and boundary_end) then return end
  if boundary_end - boundary_start < 0.01 then return end

  local SR_spls = tonumber(reaper.format_timestr_pos(1 - reaper.GetProjectTimeOffset(0, false), '', 4))
  local bufsz = math.ceil(window_sec * SR_spls)
  local data = {}
  local id = 0

  local tracks_to_read = DATA:GetTrackAndChildren(track)

  local accessors = {}
  for _, tr in ipairs(tracks_to_read) do
    if CountTrackMediaItems(tr) > 0 then
      accessors[#accessors+1] = CreateTrackAudioAccessor(tr)
    end
  end
  if #accessors == 0 then return end

  -- retry if any accessor state is stale
  for retry = 1, 10 do
    local all_valid = true
    for _, accessor in ipairs(accessors) do
      if AudioAccessorValidateState(accessor) then
        all_valid = false
      end
    end
    if all_valid then break end
    -- recreate stale accessors
    for _, accessor in ipairs(accessors) do
      reaper.DestroyAudioAccessor(accessor)
    end
    accessors = {}
    for _, tr in ipairs(tracks_to_read) do
      if CountTrackMediaItems(tr) > 0 then
        accessors[#accessors+1] = CreateTrackAudioAccessor(tr)
      end
    end
  end

  local any_nonsilent = false
  for pos = boundary_start, boundary_end, window_sec / EXT.overlap do
    local sum = 0
    for _, accessor in ipairs(accessors) do
      local samplebuffer = new_array(bufsz)
      GetAudioAccessorSamples(accessor, SR_spls, 1, pos, bufsz, samplebuffer)
      for i = 1, bufsz do
        sum = sum + math.abs(samplebuffer[i])
      end
      samplebuffer.clear()
    end
    id = id + 1
    local db_val = lin2db(sum / bufsz)
    data[id] = db_val
    if db_val > -140 then any_nonsilent = true end
  end

  for _, accessor in ipairs(accessors) do
    reaper.DestroyAudioAccessor(accessor)
  end

  if not any_nonsilent then return nil end

  return data
end

-- AI generation
function DATA:FindOverlappingAI(env, AIpos, AIend)
  local qerr = 0.1
  for AI_idx = 1, CountAutomationItems(env) do
    local pos = GetSetAutomationItemInfo(env, AI_idx-1, 'D_POSITION', 0, 0)
    local len = GetSetAutomationItemInfo(env, AI_idx-1, 'D_LENGTH', 0, 0)
    if (pos > AIpos-qerr and pos < AIend+qerr)
        or (pos+len > AIpos-qerr and pos+len < AIend+qerr)
        or (pos < AIpos-qerr and pos+len > AIend+qerr) then
      GetSetAutomationItemInfo(env, AI_idx-1, 'D_POSITION', AIpos, 1)
      GetSetAutomationItemInfo(env, AI_idx-1, 'D_LENGTH', AIend-AIpos, 1)
      GetSetAutomationItemInfo(env, AI_idx-1, 'D_POOL_QNLEN', TimeMap_timeToQN_abs(0, AIend) - TimeMap_timeToQN_abs(0, AIpos), 1)
      return AI_idx-1
    end
  end
end

function DATA:Process_GenerateAI(track, boundary_start, boundary_end)
  local env = GetTrackEnvelopeByName(track, 'Volume')
  if not ValidatePtr2(-1, env, 'TrackEnvelope*') then
    SetOnlyTrackSelected(track)
    Main_OnCommand(40406, 0)
    env = GetTrackEnvelopeByName(track, 'Volume')
  end
  if not env then return end
  local AI_idx = DATA:FindOverlappingAI(env, boundary_start, boundary_end)
  if not AI_idx then AI_idx = InsertAutomationItem(env, -1, boundary_start, boundary_end - boundary_start) end
  return true, env, AI_idx
end

-- Data insertion
function DATA:Process_BuildPoints(t, boundary_start, boundary_end, offs, env, AI_idx)
  local output = {}
  local window_sec = EXT.rms_window / EXT.overlap
  local scale = EXT.gain

  for i = 1, #t do
    local tpos = (i-1) * window_sec + boundary_start - offs
    local db_val = t[i]
    if EXT.invert == 1 then db_val = -db_val end
    local linear = db2lin(db_val)
    local scaled_db = lin2db(linear * scale)
    output[#output+1] = {tpos = tpos, val = scaled_db}
  end

  return output
end

function DATA:Process_DedupPoints(output)
  local sz = #output
  if EXT.dedup_points == 1 then
    local last_val = 0
    for i = 1, sz-1 do
      local val = output[i].val
      local valnext = output[i+1].val
      if last_val == val and valnext == val then output[i].ignore = true end
      last_val = val
    end
  end
end

function DATA:Process_InsertData(boundary_start, boundary_end, env, AI_idx, t)
  local scaling_mode = GetEnvelopeScalingMode(env)
  local offs = 0

  DeleteEnvelopePointRangeEx(env, AI_idx, boundary_start - offs, boundary_end - offs)

  local output = DATA:Process_BuildPoints(t, boundary_start, boundary_end, offs, env, AI_idx)

  if output then
    DATA:Process_DedupPoints(output)
    local sz = #output
    local valout
    for i = 1, sz do
      if output[i] and (not output[i].ignore or output[i].ignore == false) then
        valout = output[i].val
        valout = ScaleToEnvelopeMode(scaling_mode, db2lin(valout))
        InsertEnvelopePointEx(env, AI_idx, output[i].tpos + EXT.time_offset, valout, EXT.point_shape, 0, 0, true)
      end
    end
  end

  if EXT.clamp_edges == 1 then
    local ptidx = GetEnvelopePointByTimeEx(env, AI_idx, #t * EXT.rms_window + boundary_start - offs)
    if ptidx then
      local _, _, value = GetEnvelopePointEx(env, AI_idx, ptidx)
      InsertEnvelopePointEx(env, AI_idx, boundary_end - offs - 0.0001, value or 0, EXT.point_shape, 0, 0, true)
    end
    InsertEnvelopePointEx(env, AI_idx, boundary_end - offs, ScaleToEnvelopeMode(scaling_mode, db2lin(-150)), EXT.point_shape, 0, 0, true)
    InsertEnvelopePointEx(env, AI_idx, boundary_start - offs, ScaleToEnvelopeMode(scaling_mode, db2lin(-150)), EXT.point_shape, 0, 0, true)
  end

  Envelope_SortPointsEx(env, AI_idx)
end

function DATA:Process()
  local track = GetSelectedTrack(0, 0)
  if not track then reaper.MB('Please select a track.', 'Error', 0) return end
  local tsstart, tsend = GetSet_LoopTimeRange2(0, false, 0, 0, 0, 0)
  if tsend - tsstart < 0.1 then reaper.MB('Please set a time selection.', 'Error', 0) return end

  Undo_BeginBlock()
  local t0 = DATA:Process_GetAudioData(track, tsstart, tsend)
  local ret, env, AI_idx = DATA:Process_GenerateAI(track, tsstart, tsend)
  if ret and t0 then DATA:Process_InsertData(tsstart, tsend, env, AI_idx, t0) end
  Undo_EndBlock('Folder Track Amplitude Envelope Watchdog - generate', 0)
end

-- Link system
function DATA:Link_GetTrackByGUID(guid)
  for i = 0, CountTracks(0) - 1 do
    local tr = GetTrack(0, i)
    if GetTrackGUID(tr) == guid then return tr end
  end
  return nil
end

function DATA:Link_GetSourceFingerprint()
  if not DATA.link then return nil end
  local track = DATA:Link_GetTrackByGUID(DATA.link.src_track_guid)
  if not track then return nil end

  local parts = {}
  local tracks_to_watch = DATA:GetTrackAndChildren(track)

  for ti, tr in ipairs(tracks_to_watch) do
    local vol = GetMediaTrackInfo_Value(tr, 'D_VOL')
    parts[#parts+1] = string.format('t%d:%.6f', ti, vol)
    local item_count = CountTrackMediaItems(tr)
    parts[#parts+1] = 'ic'..ti..':'..item_count
    for i = 0, item_count - 1 do
      local item = GetTrackMediaItem(tr, i)
      local pos = GetMediaItemInfo_Value(item, 'D_POSITION')
      local len = GetMediaItemInfo_Value(item, 'D_LENGTH')
      local gain = GetMediaItemInfo_Value(item, 'D_VOL')
      local fadein = GetMediaItemInfo_Value(item, 'D_FADEINLEN')
      local fadeout = GetMediaItemInfo_Value(item, 'D_FADEOUTLEN')
      local mute = GetMediaItemInfo_Value(item, 'B_MUTE')
      parts[#parts+1] = string.format('i%d_%d:%.4f,%.4f,%.4f,%.4f,%.4f,%.0f', ti, i, pos, len, gain, fadein, fadeout, mute)
    end
  end

  return table.concat(parts, '|')
end

function DATA:Link_FindDestAI()
  if not DATA.link then return nil, nil end
  local dest_track = DATA:Link_GetTrackByGUID(DATA.link.dest_track_guid)
  if not dest_track then return nil, nil end

  local env_count = CountTrackEnvelopes(dest_track)
  if DATA.link.dest_env_idx >= env_count then return nil, nil end
  local env = GetTrackEnvelope(dest_track, DATA.link.dest_env_idx)
  if not env then return nil, nil end

  if DATA.link.dest_AI_pool_id then
    local ai_count = CountAutomationItems(env)
    for ai = 0, ai_count - 1 do
      local pool_id = GetSetAutomationItemInfo(env, ai, 'D_POOL_ID', 0, 0)
      if pool_id == DATA.link.dest_AI_pool_id then
        DATA.link.dest_AI_pos = GetSetAutomationItemInfo(env, ai, 'D_POSITION', 0, 0)
        DATA.link.dest_AI_len = GetSetAutomationItemInfo(env, ai, 'D_LENGTH', 0, 0)
        return env, ai
      end
    end
  end

  local qerr = 0.01
  local ai_count = CountAutomationItems(env)
  for ai = 0, ai_count - 1 do
    local pos = GetSetAutomationItemInfo(env, ai, 'D_POSITION', 0, 0)
    local len = GetSetAutomationItemInfo(env, ai, 'D_LENGTH', 0, 0)
    if math.abs(pos - DATA.link.dest_AI_pos) < qerr and math.abs(len - DATA.link.dest_AI_len) < qerr then
      DATA.link.dest_AI_pool_id = GetSetAutomationItemInfo(env, ai, 'D_POOL_ID', 0, 0)
      return env, ai
    end
  end

  return nil, nil
end

function DATA:Link_GetSelectedAIInfo()
  local env = GetSelectedEnvelope(0)
  if not env then return nil end
  local track = Envelope_GetParentTrack(env)
  if not track then return nil end

  local env_idx = -1
  for i = 0, CountTrackEnvelopes(track) - 1 do
    if GetTrackEnvelope(track, i) == env then env_idx = i break end
  end
  if env_idx == -1 then return nil end

  local ai_count = CountAutomationItems(env)
  for ai = 0, ai_count - 1 do
    local sel = GetSetAutomationItemInfo(env, ai, 'D_UISEL', 0, 0)
    if sel > 0 then
      local pos = GetSetAutomationItemInfo(env, ai, 'D_POSITION', 0, 0)
      local len = GetSetAutomationItemInfo(env, ai, 'D_LENGTH', 0, 0)
      return track, env, env_idx, ai, pos, len
    end
  end

  return nil
end

function DATA:Link_Create()
  local src_track = GetSelectedTrack(0, 0)
  if not src_track then
    reaper.MB('Please select the source track.', 'Link Error', 0)
    return
  end
  local src_track_guid = GetTrackGUID(src_track)

  local tsstart, tsend = GetSet_LoopTimeRange2(0, false, 0, 0, 0, 0)
  if tsend - tsstart < 0.1 then
    reaper.MB('Please set a time selection for the analysis range.', 'Link Error', 0)
    return
  end

  local dest_track, dest_env, dest_env_idx, dest_ai, dest_ai_pos, dest_ai_len = DATA:Link_GetSelectedAIInfo()
  if not dest_track then
    reaper.MB('Please select the destination automation item (click on it in arrange view).', 'Link Error', 0)
    return
  end

  DATA.link = {
    src_track_guid = src_track_guid,
    dest_track_guid = GetTrackGUID(dest_track),
    dest_env_idx = dest_env_idx,
    dest_AI_pos = dest_ai_pos,
    dest_AI_len = dest_ai_len,
    dest_AI_pool_id = GetSetAutomationItemInfo(dest_env, dest_ai, 'D_POOL_ID', 0, 0),
    boundary_start = tsstart,
    boundary_end = tsend,
  }

  DATA.link_fingerprint = DATA:Link_GetSourceFingerprint()
  DATA.link_debounce_time = nil

  local _, src_name = GetTrackName(src_track)
  local _, dest_name = GetTrackName(dest_track)
  local _, env_name = GetEnvelopeName(dest_env)
  DATA.link_status = 'Linked: '..src_name..' → '..dest_name..' ('..env_name..')'

  DATA:Link_Save()
end

function DATA:Link_Save()
  if not DATA.link then
    reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'active', '')
    return
  end
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'active', '1')
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'src_track_guid', DATA.link.src_track_guid)
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'dest_track_guid', DATA.link.dest_track_guid)
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'dest_env_idx', tostring(DATA.link.dest_env_idx))
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'dest_AI_pos', tostring(DATA.link.dest_AI_pos))
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'dest_AI_len', tostring(DATA.link.dest_AI_len))
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'boundary_start', tostring(DATA.link.boundary_start))
  reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'boundary_end', tostring(DATA.link.boundary_end))
  if DATA.link.dest_AI_pool_id then
    reaper.SetProjExtState(0, 'JAB_Watchdog_Link', 'dest_AI_pool_id', tostring(DATA.link.dest_AI_pool_id))
  end
  reaper.MarkProjectDirty(0)
end

function DATA:Link_Load()
  local _, active = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'active')
  if active ~= '1' then return end

  local _, src_guid = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'src_track_guid')
  local _, dest_guid = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'dest_track_guid')
  local _, env_idx = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'dest_env_idx')
  local _, ai_pos = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'dest_AI_pos')
  local _, ai_len = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'dest_AI_len')
  local _, b_start = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'boundary_start')
  local _, b_end = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'boundary_end')
  local _, pool_id = reaper.GetProjExtState(0, 'JAB_Watchdog_Link', 'dest_AI_pool_id')

  if src_guid == '' or dest_guid == '' then return end

  DATA.link = {
    src_track_guid = src_guid,
    dest_track_guid = dest_guid,
    dest_env_idx = tonumber(env_idx) or 0,
    dest_AI_pos = tonumber(ai_pos) or 0,
    dest_AI_len = tonumber(ai_len) or 0,
    dest_AI_pool_id = tonumber(pool_id),
    boundary_start = tonumber(b_start) or 0,
    boundary_end = tonumber(b_end) or 0,
  }

  local src_track = DATA:Link_GetTrackByGUID(src_guid)
  local dest_env, dest_ai = DATA:Link_FindDestAI()
  if not src_track or not dest_env then
    DATA.link = nil
    DATA.link_status = 'Link restored but tracks/AI not found'
    return
  end

  DATA.link_fingerprint = DATA:Link_GetSourceFingerprint()
  DATA.link_debounce_time = nil

  local _, src_name = GetTrackName(src_track)
  local _, dest_name = GetTrackName(DATA:Link_GetTrackByGUID(dest_guid))
  local _, env_name = GetEnvelopeName(dest_env)
  DATA.link_status = 'Link restored: '..src_name..' → '..dest_name..' ('..env_name..')'
end

function DATA:Link_Unlink()
  DATA.link = nil
  DATA.link_fingerprint = nil
  DATA.link_debounce_time = nil
  DATA.link_status = nil
  DATA:Link_Save()
end

function DATA:Link_ProcessUpdate()
  if not DATA.link then return end

  local src_track = DATA:Link_GetTrackByGUID(DATA.link.src_track_guid)
  if not src_track then
    DATA.link_status = 'Link error: source track not found'
    return
  end

  local dest_track = DATA:Link_GetTrackByGUID(DATA.link.dest_track_guid)
  if not dest_track then
    DATA.link_status = 'Link error: destination track not found'
    return
  end

  local dest_env, dest_ai = DATA:Link_FindDestAI()
  if not dest_env then
    DATA.link_status = 'Link error: destination AI not found'
    return
  end

  local boundary_start = DATA.link.boundary_start
  local boundary_end = DATA.link.boundary_end

  local tsstart, tsend = GetSet_LoopTimeRange2(0, false, 0, 0, 0, 0)
  if tsend - tsstart >= 0.1 then
    boundary_start = tsstart
    boundary_end = tsend
    DATA.link.boundary_start = boundary_start
    DATA.link.boundary_end = boundary_end
  end

  local t0 = DATA:Process_GetAudioData(src_track, boundary_start, boundary_end)
  if not t0 then
    DATA.link_status = 'Link warning: no audio data from source'
    DATA.link_fingerprint = DATA:Link_GetSourceFingerprint()
    return
  end

  Undo_BeginBlock()

  GetSetAutomationItemInfo(dest_env, dest_ai, 'D_POSITION', boundary_start, 1)
  GetSetAutomationItemInfo(dest_env, dest_ai, 'D_LENGTH', boundary_end - boundary_start, 1)
  GetSetAutomationItemInfo(dest_env, dest_ai, 'D_POOL_QNLEN',
    TimeMap_timeToQN_abs(0, boundary_end) - TimeMap_timeToQN_abs(0, boundary_start), 1)

  DATA.link.dest_AI_pos = boundary_start
  DATA.link.dest_AI_len = boundary_end - boundary_start

  DATA:Process_InsertData(boundary_start, boundary_end, dest_env, dest_ai, t0)

  Undo_EndBlock('Folder Track Amplitude Envelope Watchdog - link auto-update', 0)

  -- update fingerprint so we don't re-trigger
  DATA.link_fingerprint = DATA:Link_GetSourceFingerprint()

  local _, src_name = GetTrackName(src_track)
  DATA.link_status = 'Linked (updated): '..src_name
end

function DATA:Link_CheckAndUpdate()
  if not DATA.link then return end

  local current_fp = DATA:Link_GetSourceFingerprint()
  if not current_fp then return end

  if current_fp ~= DATA.link_fingerprint then
    if not DATA.link_debounce_time then
      DATA.link_debounce_time = os.clock()
    end
    if os.clock() - DATA.link_debounce_time >= DATA.link_debounce_sec then
      DATA:Link_ProcessUpdate()
      DATA.link_debounce_time = nil
      DATA:Link_Save()
    end
  else
    DATA.link_debounce_time = nil
  end
end

-- GUI
function draw_controls()
  local content_width = ImGui.GetContentRegionAvail(ctx)
  local slider_width = math.max(200, content_width - 130)
  
  -- Generate button
  ImGui.SeparatorText(ctx, 'Generate')
  
  if ImGui.Button(ctx, 'Generate from Selection', -1, 28) then
    DATA:Process()
  end
  
  -- Link controls
  ImGui.SeparatorText(ctx, 'Watchdog Link')
  
  if not DATA.link then
    if ImGui.Button(ctx, 'Link Source → Dest AI', -1, 28) then
      DATA:Link_Create()
    end
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then
      ImGui.SetItemTooltip(ctx, 'Select source track, set time selection, click on destination AI, then press this button')
    end
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x993333FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xBB4444FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xDD5555FF)
    if ImGui.Button(ctx, 'Unlink', content_width * 0.5 - 4, 28) then DATA:Link_Unlink() end
    ImGui.PopStyleColor(ctx, 3)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Force Update', -1, 28) then DATA:Link_ProcessUpdate() end
  end
  
  if DATA.link_status then
    ImGui.TextWrapped(ctx, DATA.link_status)
  end
  
  -- Settings
  ImGui.SeparatorText(ctx, 'Settings')
  
  ImGui.Text(ctx, 'Analysis')
  
  ImGui.SetNextItemWidth(ctx, slider_width)
  local w_changed, w_val = ImGui.SliderDouble(ctx, 'Window Size', EXT.rms_window, 0.001, 0.4, string.format('%.3fs', EXT.rms_window))
  if w_changed then EXT.rms_window = w_val; EXT:save() end
  
  ImGui.SetNextItemWidth(ctx, slider_width)
  local o_changed, o_val = ImGui.SliderInt(ctx, 'Precision', math.floor(EXT.overlap), 1, 16)
  if o_changed then EXT.overlap = o_val; EXT:save() end
  
  ImGui.SetNextItemWidth(ctx, slider_width)
  local scale_pct = math.floor(EXT.gain * 100 + 0.5)
  local s_changed, s_val = ImGui.SliderInt(ctx, 'Gain', scale_pct, 0, 200, '%d%%')
  if s_changed then EXT.gain = s_val / 100; EXT:save() end
  
  local inv_changed, inv_val = ImGui.Checkbox(ctx, 'Invert', EXT.invert == 1)
  if inv_changed then EXT.invert = inv_val and 1 or 0; EXT:save() end
  
  -- Envelope
  ImGui.Separator(ctx)
  ImGui.Text(ctx, 'Envelope')
  
  local rsv_changed, rsv_val = ImGui.Checkbox(ctx, 'Deduplicate points', EXT.dedup_points == 1)
  if rsv_changed then EXT.dedup_points = rsv_val and 1 or 0; EXT:save() end
  
  local zb_changed, zb_val = ImGui.Checkbox(ctx, 'Silence at edges', EXT.clamp_edges == 1)
  if zb_changed then EXT.clamp_edges = zb_val and 1 or 0; EXT:save() end
  
  ImGui.SetNextItemWidth(ctx, slider_width)
  local shape_labels = {[0] = 'Linear', [1] = 'Square', [2] = 'Slow start/end', [5] = 'Bezier'}
  local current_shape_label = shape_labels[EXT.point_shape] or 'Linear'
  if ImGui.BeginCombo(ctx, 'Interpolation', current_shape_label) then
    for _, id in ipairs({0, 1, 2, 5}) do
      if ImGui.Selectable(ctx, shape_labels[id], EXT.point_shape == id) then
        EXT.point_shape = id
        EXT:save()
      end
    end
    ImGui.EndCombo(ctx)
  end
  
  ImGui.SetNextItemWidth(ctx, slider_width)
  local sh_changed, sh_val = ImGui.SliderDouble(ctx, 'Time Offset', EXT.time_offset, -0.1, 0.1, string.format('%.2fms', EXT.time_offset))
  if sh_changed then EXT.time_offset = sh_val; EXT:save() end
end

-- Main loop
function main_loop()
  ImGui.SetNextWindowSizeConstraints(ctx, 350, 400, 600, math.huge)
  ImGui.SetNextWindowBgAlpha(ctx, 1.0)
  
  local visible, open = ImGui.Begin(ctx, 'joshadambell - Folder Track Amplitude Envelope Watchdog', true)
  
  if visible then
    draw_controls()
    ImGui.End(ctx)
  end
  
  -- Run watchdog
  DATA:Link_CheckAndUpdate()
  
  if open then
    reaper.defer(main_loop)
  end
end

-- Init
function init()
  EXT:load()
  DATA:Link_Load()
  ImGui.SetNextWindowSize(ctx, 400, 520, ImGui.Cond_FirstUseEver)
  main_loop()
end

init()
