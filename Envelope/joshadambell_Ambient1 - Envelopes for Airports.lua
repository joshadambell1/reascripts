--[[
ReaScript name: joshadambell_Ambient1 Envelopes for Airports
Author: joshadambell
Website: https://joshadambell.com
Dependencies: ReaImGui extension
About:
  # Macro Modulator for REAPER Envelopes
  
  Organic, non-cyclical parameter modulation inspired by Brian Eno's ambient works.
  Creates subtle, organic parameter evolution over 15-60 second timeframes.
  
  ## Requirements
  - ReaImGui extension (install via ReaPack)
  - REAPER v6.0 or higher
  
  ## Features
  - Eno-inspired ambient modulation patterns
  - Non-cyclical, organic parameter evolution
  - Drift, evolution, and wandering algorithms
  - 15-60 second evolution cycles
  - Extremely subtle parameter changes
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
local ctx = ImGui.CreateContext('Macro Modulator v1.0')

-- Global state
local MACRO = {
    -- Core parameters
    intensity = 0.5,         -- How much change (0.0-1.0 for subtlety)
    duration = 30.0,         -- Evolution cycle length in seconds
    smoothness = 200,        -- Points per minute for ultra-smooth curves
    center = 0.5,           -- Center point for evolution
    min_value = 0.0,        -- Minimum clamp value
    max_value = 1.0,        -- Maximum clamp value
    
    -- Organic parameters (randomized on launch)
    complexity = 0.55,      -- Detail layers + amplitude drift over time
    flow = 1.5,             -- Transition smoothness and point-to-point blending (0.0-3.0)
    randomness = 1.5,       -- Random variations and fine-grain noise overlay (0.0-3.0)
    peak_irregularity = 0.35, -- Time warping + peak events for irregular peaks
    
    -- Random seed
    seed = 12345,
    
    -- Current algorithm
    currentAlgorithm = 1, -- Default to Fractal Curves
    
    -- Target envelope info
    targetEnv = nil,
    timeStart = 0,
    timeEnd = 0,
    
    -- GUI state
    showHelp = false,
    autoApply = true, -- Auto apply changes by default
    
    -- Algorithm-specific parameters (all set to midpoint of slider ranges)
    fractal = {
        octaves = 9,               -- 0 - 10 (default: 9)
        persistence = 0.4,         -- 0.0 - 1.0 (default: 0.4)
        frequency_scale = 10.0,    -- 1.0 - 20.0 (default: 10.0)
        lacunarity = 0.7,          -- 0.5 - 5.0 (default: 0.7)
        amplitude_bias = 1.9       -- 0.01 - 2.5 (default: 1.9)
    },
    
    cellular = {
        evolution_rate = 0.2025,   -- 0.005 - 0.4 (midpoint: 0.2025)
        random_activation = 0.405, -- 0.01 - 0.8 (midpoint: 0.405)
        smoothing_window = 21,     -- 2 - 40 (midpoint: 21)
        cell_count = 240,          -- 32 - 512 (midpoint: 272, rounded to 240)
        rule_variation = 2.0       -- 0.0 - 4.0 (midpoint: 2.0)
    },
    
    generative = {
        segment_length = 0.2,      -- 0.01 - 0.3 (default: 0.2)
        smoothing_factor = 21.0,   -- 0.01 - 50.0 (default: 21.0)
        variation_scale = 0.03,    -- 0.01 - 0.05 (default: 0.03)
        momentum = 0.075           -- 0.001 - 0.1 (default: 0.075)
    },
    
    -- Parameter locking system
    locked = {
        intensity = false,
        center = false,
        complexity = false,
        flow = false,
        randomness = false,
        peak_irregularity = false,
        -- Algorithm-specific locks
        algo_param1 = false,
        algo_param2 = false,
        algo_param3 = false,
        algo_param4 = false,
        algo_param5 = false
    }
}

-- Organic modulation algorithms
local algorithms = {
    "Fractal Curves", 
    "Cellular Automata",
    "Generative Walk"
}

-- Seeded random number generator for reproducible results
local function seeded_random(seed, min, max)
    -- Simple linear congruential generator
    seed = (seed * 1103515245 + 12345) % 4294967296
    local value = seed / 4294967296
    if min and max then
        return min + value * (max - min), seed
    end
    return value, seed
end

-- Perlin-like noise function for organic curves
local function smooth_noise(x, seed)
    local int_x = math.floor(x)
    local frac_x = x - int_x
    
    -- Get random values at integer points
    local v1, _ = seeded_random(seed + int_x, -1, 1)
    local v2, _ = seeded_random(seed + int_x + 1, -1, 1)
    
    -- Smooth interpolation (cosine interpolation for organic feel)
    local ft = frac_x * math.pi
    local f = (1 - math.cos(ft)) * 0.5
    
    return v1 * (1 - f) + v2 * f
end


-- Fractal curve generator with lacunarity and amplitude bias
local function fractal_noise(x, octaves, persistence, lacunarity, amplitude_bias, seed)
    local value = 0
    local amplitude = 1
    local frequency = 1
    local max_value = 0
    
    for i = 1, octaves do
        local octave_value = smooth_noise(x * frequency, seed + i * 1000)
        -- Apply amplitude bias - weights higher/lower frequencies differently
        local biased_amplitude = amplitude * (amplitude_bias ^ (i - 1))
        value = value + octave_value * biased_amplitude
        max_value = max_value + biased_amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity -- Use lacunarity instead of hardcoded 2
    end
    
    return value / max_value
end


-- Simple cellular automaton (1D Rule 30-inspired)
local ca_state = {
    cells = {},
    generation = 0,
    last_time = -1,
    history = {} -- For smoothing
}

-- Generative walk state for momentum
local generative_state = {
    last_value = 0,
    velocity = 0,
    last_time = -1
}

-- Initialize cellular automaton
local function init_cellular_automaton(cell_count, seed)
    ca_state.cells = {}
    ca_state.generation = 0
    
    -- Create initial random state
    for i = 1, cell_count do
        local random_val, _ = seeded_random(seed + i, 0, 1)
        ca_state.cells[i] = random_val > 0.5 and 1 or 0
    end
end

-- Evolve cellular automaton one step
local function evolve_cellular_automaton(cell_count, rule_variation, seed)
    local new_cells = {}
    
    for i = 1, cell_count do
        local left = ca_state.cells[i == 1 and cell_count or i-1] or 0
        local center = ca_state.cells[i] or 0
        local right = ca_state.cells[i == cell_count and 1 or i+1] or 0
        
        -- Simplified Rule 30: XOR left with (center OR right)
        local neighbor_sum = left + center + right
        local rule_result = 0
        
        -- Rule table for different neighbor counts (keeps some diversity)
        if neighbor_sum == 0 then
            rule_result = 0
        elseif neighbor_sum == 1 then
            rule_result = 1
        elseif neighbor_sum == 2 then
            rule_result = center == 1 and 0 or 1  -- Flip current state
        else -- neighbor_sum == 3
            rule_result = 0
        end
        
        -- Add rule variation for more organic behavior
        if rule_variation > 0 then
            local variation_random, _ = seeded_random(seed + ca_state.generation * 100 + i + 5000, 0, 1)
            if variation_random < rule_variation then
                rule_result = 1 - rule_result  -- Flip the rule result
            end
        end
        
        -- Add controlled randomness to prevent extinction
        local random_val, _ = seeded_random(seed + ca_state.generation * 100 + i, 0, 1)
        if random_val < MACRO.cellular.random_activation then -- User-controlled activation chance
            rule_result = 1
        end
        
        new_cells[i] = rule_result
    end
    
    ca_state.cells = new_cells
    ca_state.generation = ca_state.generation + 1
end

-- STEP 1: Generate base algorithm (-1 to +1 normalized)
function generate_base_algorithm(time_pos, current_seed)
    local base_value = 0
    
    if MACRO.currentAlgorithm == 1 then -- Fractal Curves
        -- Self-similar patterns using user-controlled fractal noise
        base_value = fractal_noise(time_pos * MACRO.fractal.frequency_scale, MACRO.fractal.octaves, MACRO.fractal.persistence, MACRO.fractal.lacunarity, MACRO.fractal.amplitude_bias, current_seed)
        
    elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
        -- Reset or evolve cellular automaton
        if ca_state.last_time > time_pos or ca_state.last_time == -1 then
            init_cellular_automaton(MACRO.cellular.cell_count, current_seed)
            ca_state.last_time = 0
            ca_state.history = {} -- Track recent values for smoothing
        end
        
        -- Evolve CA with user-controlled rate
        local target_generation = math.floor(time_pos / MACRO.cellular.evolution_rate)
        
        while ca_state.generation < target_generation do
            evolve_cellular_automaton(MACRO.cellular.cell_count, MACRO.cellular.rule_variation, current_seed)
        end
        
        -- Calculate output as weighted sum of cells with better distribution
        local cell_sum = 0
        local active_cells = 0
        for i, cell in ipairs(ca_state.cells) do
            if cell == 1 then
                active_cells = active_cells + 1
                -- Use position-based weighting for smoother patterns
                cell_sum = cell_sum + math.cos(i * 0.2) -- Smoother weighting function
            end
        end
        
        -- Normalize based on active cells to prevent intensity inversion
        local raw_value = 0
        if active_cells > 0 then
            raw_value = cell_sum / active_cells -- Average weighted value of active cells
        else
            raw_value = -0.5 -- Default when no cells active
        end
        
        -- Add to history for user-controlled smoothing
        if not ca_state.history then ca_state.history = {} end
        table.insert(ca_state.history, raw_value)
        if #ca_state.history > MACRO.cellular.smoothing_window then
            table.remove(ca_state.history, 1) -- Keep only last N values
        end
        
        -- Smooth output using moving average
        local smoothed_value = 0
        for _, val in ipairs(ca_state.history) do
            smoothed_value = smoothed_value + val
        end
        base_value = smoothed_value / #ca_state.history
        
        ca_state.last_time = time_pos
        
    elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
        -- Reset state if we're starting over
        if generative_state.last_time > time_pos or generative_state.last_time == -1 then
            generative_state.last_value = 0
            generative_state.velocity = 0
            generative_state.last_time = 0
        end
        
        -- Segment-based random walk with user-controlled parameters
        local segments = math.floor(1 / MACRO.generative.segment_length)
        local current_segment = math.floor(time_pos * segments)
        local segment_pos = (time_pos * segments) - current_segment
        
        local segment_seed = current_seed + current_segment * 1000
        local segment_start, _ = seeded_random(segment_seed, -MACRO.generative.variation_scale, MACRO.generative.variation_scale)
        local segment_end, _ = seeded_random(segment_seed + 1, -MACRO.generative.variation_scale, MACRO.generative.variation_scale)
        
        
        -- User-controlled interpolation smoothness
        local smooth_t
        if MACRO.generative.smoothing_factor > 0.5 then
            -- Smooth interpolation (smoothstep)
            local smooth_factor = (MACRO.generative.smoothing_factor - 0.5) * 2
            smooth_t = segment_pos * segment_pos * (3 - 2 * segment_pos) * smooth_factor + segment_pos * (1 - smooth_factor)
        else
            -- Linear to smooth interpolation
            local linear_factor = MACRO.generative.smoothing_factor * 2
            smooth_t = segment_pos * linear_factor + (segment_pos * segment_pos * (3 - 2 * segment_pos)) * (1 - linear_factor)
        end
        
        local raw_value = segment_start + (segment_end - segment_start) * smooth_t
        
        -- Apply momentum - carry some velocity from previous steps
        if MACRO.generative.momentum > 0 and generative_state.last_time >= 0 then
            local dt = math.max(0.001, time_pos - generative_state.last_time)
            local target_velocity = (raw_value - generative_state.last_value) / dt
            generative_state.velocity = generative_state.velocity * (1 - MACRO.generative.momentum) + target_velocity * MACRO.generative.momentum
            raw_value = generative_state.last_value + generative_state.velocity * dt
        end
        
        generative_state.last_value = raw_value
        generative_state.last_time = time_pos
        
        base_value = math.max(-1, math.min(1, raw_value))
    end
    
    -- Normalize to -1 to +1 range
    return math.max(-1, math.min(1, base_value))
end

-- Get algorithm-specific frequency multiplier using all 5 parameters
function get_algorithm_frequency_multiplier()
    if MACRO.currentAlgorithm == 1 then -- Fractal Curves
        -- Combine all 5 fractal parameters into frequency scaling
        local octaves_factor = MACRO.fractal.octaves / 10.0                    -- 0.0-1.0
        local persistence_factor = MACRO.fractal.persistence                   -- 0.0-1.0  
        local freq_factor = (MACRO.fractal.frequency_scale - 1.0) / 19.0       -- 0.0-1.0
        local lacunarity_factor = (MACRO.fractal.lacunarity - 0.5) / 4.5       -- 0.0-1.0
        local bias_factor = (MACRO.fractal.amplitude_bias - 0.01) / 2.49       -- 0.0-1.0
        
        -- Weight them differently for interesting interactions
        local composite = (octaves_factor * 0.3) + (persistence_factor * 0.2) + 
                         (freq_factor * 0.3) + (lacunarity_factor * 0.1) + (bias_factor * 0.1)
        return 0.3 + composite * 1.7  -- Range: 0.3x to 2.0x
        
    elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
        local evolution_factor = MACRO.cellular.evolution_rate / 0.4           -- 0.0125-1.0
        local activation_factor = (MACRO.cellular.random_activation - 0.01) / 0.79  -- 0.0-1.0
        local smoothing_factor = (MACRO.cellular.smoothing_window - 2) / 38    -- 0.0-1.0
        local cell_factor = (MACRO.cellular.cell_count - 32) / 480             -- 0.0-1.0
        local rule_factor = MACRO.cellular.rule_variation / 4.0                -- 0.0-1.0
        
        local composite = (evolution_factor * 0.3) + (activation_factor * 0.2) + 
                         (smoothing_factor * 0.2) + (cell_factor * 0.2) + (rule_factor * 0.1)
        return 0.4 + composite * 1.6  -- Range: 0.4x to 2.0x
        
    elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
        local segment_factor = (0.3 - MACRO.generative.segment_length) / 0.29    -- Inverted: shorter = higher
        local smooth_factor = MACRO.generative.smoothing_factor / 50.0           -- 0.0002-1.0
        local variation_factor = (MACRO.generative.variation_scale - 0.01) / 0.04 -- 0.0-1.0
        local momentum_factor = (MACRO.generative.momentum - 0.001) / 0.099      -- 0.0-1.0
        
        local composite = (segment_factor * 0.35) + (smooth_factor * 0.25) + 
                         (variation_factor * 0.2) + (momentum_factor * 0.2)
        return 0.5 + composite * 1.5  -- Range: 0.5x to 2.0x
    end
    
    return 1.0 -- Fallback
end

-- STEP 2: Apply character parameters that modify behavior
function apply_character_parameters(base_value, time_pos, current_seed)
    local modified_value = base_value
    local freq_multiplier = get_algorithm_frequency_multiplier()
    
    -- Complexity: Add detail layers (MUCH REDUCED)
    if MACRO.complexity > 0 then
        local detail1 = smooth_noise(time_pos * 1.618 * freq_multiplier, current_seed + 2000) * 0.08 * MACRO.complexity
        local detail2 = smooth_noise(time_pos * 7.389 * freq_multiplier, current_seed + 3000) * 0.05 * MACRO.complexity
        local detail3 = smooth_noise(time_pos * 13.42 * freq_multiplier, current_seed + 4000) * 0.03 * MACRO.complexity
        modified_value = modified_value + detail1 + detail2 + detail3
    end
    
    -- Peak Irregularity: Combines time warping + peak events (REDUCED)
    if MACRO.peak_irregularity > 0 then
        -- Time warping component (smaller)
        local warp_noise1 = smooth_noise(time_pos * 0.7 * freq_multiplier, current_seed + 5000)
        local warp_noise2 = smooth_noise(time_pos * 2.3 * freq_multiplier, current_seed + 6000) * 0.6
        local time_warp_factor = 1.0 + (warp_noise1 + warp_noise2) * MACRO.peak_irregularity * 0.2
        time_warp_factor = math.max(0.7, math.min(1.5, time_warp_factor))
        
        -- Apply warping (much smaller effect)
        local warped_interference = smooth_noise(time_pos * 5.196 * time_warp_factor * freq_multiplier, current_seed + 7000)
        modified_value = modified_value + warped_interference * MACRO.peak_irregularity * 0.1
        
        -- Peak events component (smaller)
        local event_wave1 = smooth_noise(time_pos * 2.718 * freq_multiplier, current_seed + 8000)
        local event_wave2 = smooth_noise(time_pos * 5.439 * freq_multiplier, current_seed + 9000) * 0.7
        
        -- Create gradual event modulation (smaller effect)
        local event_strength = (event_wave1 + event_wave2) * MACRO.peak_irregularity * 0.15
        local event_modifier = 1.0 + event_strength
        modified_value = modified_value * event_modifier
    end
    
    return math.max(-1, math.min(1, modified_value))
end

-- STEP 3: Apply scaling parameters for amplitude control
function apply_scaling_parameters(modified_value, time_pos, point_index, existing_points, current_seed)
    local scaled_value = modified_value
    local freq_multiplier = get_algorithm_frequency_multiplier()
    
    -- Complexity: Now includes drift amount - amplitude variation over time (REDUCED)
    if MACRO.complexity > 0 then
        -- Create drift multiplier that varies over time (smaller effect)
        local drift_envelope = smooth_noise(time_pos * 1.5 * freq_multiplier, current_seed + 10000) * 0.5 + 0.5 -- 0 to 1
        local drift_factor = 0.8 + (drift_envelope * MACRO.complexity * 0.2) -- 0.8 to 1.0 range (much smaller)
        scaled_value = scaled_value * drift_factor
    end
    
    -- Flow: Combines responsiveness (point-to-point) and flow smoothness (REDUCED)
    if MACRO.flow > 0 then
        -- Point-to-point smoothing (much less aggressive)
        if point_index > 0 and existing_points[point_index] then
            local prev_value = existing_points[point_index].scaled_value or 0
            local responsiveness_factor = 0.7 + (MACRO.flow * 0.3) -- Less smoothing
            scaled_value = prev_value + (scaled_value - prev_value) * responsiveness_factor
        end
        
        -- Flow smoothness noise (much smaller)
        local smoothing_noise = smooth_noise(time_pos * 20 * freq_multiplier, current_seed + 11000) * MACRO.flow * 0.05
        scaled_value = scaled_value + smoothing_noise
    end
    
    -- Randomness: Combines unpredictability and turbulence (MUCH REDUCED)
    if MACRO.randomness > 0 then
        -- Micro-variations (smaller)
        local micro_random = smooth_noise(time_pos * 25 * freq_multiplier, current_seed + 12000) * MACRO.randomness * 0.08
        
        -- Fine-grain noise overlay (much smaller)
        local turb1 = smooth_noise(time_pos * 40 * freq_multiplier, current_seed + 13000) * MACRO.randomness * 0.05
        local turb2 = smooth_noise(time_pos * 80 * freq_multiplier, current_seed + 14000) * MACRO.randomness * 0.03
        
        scaled_value = scaled_value + micro_random + turb1 + turb2
    end
    
    -- Apply Intensity scaling
    scaled_value = scaled_value * MACRO.intensity
    
    return scaled_value
end

-- STEP 4: Apply center positioning and final range clamping  
function apply_final_positioning(scaled_value)
    -- Position around center
    local final_value = MACRO.center + scaled_value
    
    -- Clamp to user-defined min/max range
    final_value = math.max(MACRO.min_value, math.min(MACRO.max_value, final_value))
    
    return final_value
end

-- Main generation function with clean architecture
function generate_organic_points(duration)
    local points = {}
    local points_per_minute = MACRO.smoothness
    local total_steps = math.max(30, math.floor(duration * points_per_minute / 60))
    
    -- Initialize random seed
    local current_seed = MACRO.seed
    
    -- Reset algorithm states at the beginning of generation
    ca_state = {cells = {}, generation = 0, last_time = -1, history = {}}
    generative_state = {last_value = 0, velocity = 0, last_time = -1}
    
    for i = 0, total_steps - 1 do
        local time_pos = i / (total_steps - 1) -- 0 to 1 across duration
        local actual_time = MACRO.timeStart + time_pos * duration
        
        -- STEP 1: Generate base algorithm (-1 to +1 normalized)
        local base_value = generate_base_algorithm(time_pos, current_seed)
        
        -- STEP 2: Apply character parameters that modify behavior
        local modified_value = apply_character_parameters(base_value, time_pos, current_seed)
        
        -- STEP 3: Apply scaling parameters for amplitude control  
        local scaled_value = apply_scaling_parameters(modified_value, time_pos, i, points, current_seed)
        
        -- STEP 4: Apply center positioning and final range clamping
        local final_value = apply_final_positioning(scaled_value)
        
        table.insert(points, {
            time = actual_time,
            value = final_value,
            shape = 2, -- Smooth curves
            tension = 0,
            scaled_value = final_value -- Store for responsiveness calculation
        })
    end
    
    return points
end

-- Utility functions (similar to LFO tool)
function get_selected_envelope()
    local env = reaper.GetSelectedEnvelope(0)
    if env then
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

-- Debug function to test raw algorithm outputs
function debug_algorithms()
    reaper.ShowConsoleMsg("=== Algorithm Debug Test ===\n")
    local test_seed = 12345
    
    for alg = 1, 6 do
        reaper.ShowConsoleMsg("Algorithm " .. alg .. " (" .. algorithms[alg] .. "):\n")
        
        -- Reset states for each algorithm test
        brownian_state = {position = 0, velocity = 0, last_time = -1}
        pendulum_state = {angle = 0, angular_velocity = 0, last_time = -1}
        ca_state = {cells = {}, generation = 0, last_time = -1}
        
        MACRO.currentAlgorithm = alg
        
        local values = {}
        for i = 1, 10 do
            local time_pos = (i-1) / 9  -- 0 to 1
            local raw_value = generate_base_algorithm(time_pos, test_seed)
            values[i] = raw_value
        end
        
        reaper.ShowConsoleMsg("  Raw values: " .. table.concat(values, ", ") .. "\n")
        reaper.ShowConsoleMsg("  Range: " .. math.min(table.unpack(values)) .. " to " .. math.max(table.unpack(values)) .. "\n\n")
    end
end

-- Apply macro modulation to envelope
function apply_macro_modulation()
    if not MACRO.targetEnv then
        reaper.MB('Please select an envelope first', 'No Target', 0)
        return
    end
    
    if MACRO.timeEnd <= MACRO.timeStart then
        reaper.MB('Please make a time selection first', 'No Time Range', 0)
        return
    end
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Clear existing points in time range
    local buffer = 0.001
    reaper.DeleteEnvelopePointRange(MACRO.targetEnv, MACRO.timeStart - buffer, MACRO.timeEnd + buffer)
    
    -- Generate organic modulation points
    local duration = MACRO.timeEnd - MACRO.timeStart
    local macro_points = generate_organic_points(duration)
    
    -- Detect envelope range
    local env_min, env_max = 0, 1
    if MACRO.targetEnv then
        local br_env = reaper.BR_EnvAlloc(MACRO.targetEnv, false)
        if br_env then
            local _, _, _, _, _, _, detected_min, detected_max = reaper.BR_EnvGetProperties(br_env)
            if detected_min and detected_max and detected_min ~= detected_max then
                env_min, env_max = detected_min, detected_max
            end
            reaper.BR_EnvFree(br_env, false)
        end
    end
    
    -- Insert points
    for _, point in ipairs(macro_points) do
        local env_value = env_min + point.value * (env_max - env_min)
        env_value = math.max(env_min, math.min(env_max, env_value))
        
        reaper.InsertEnvelopePoint(MACRO.targetEnv, point.time, env_value, point.shape, point.tension or 0, true, true)
    end
    
    -- Update display
    reaper.Envelope_SortPoints(MACRO.targetEnv)
    reaper.UpdateArrange()
    
    reaper.Undo_EndBlock('Apply Macro Modulation: ' .. algorithms[MACRO.currentAlgorithm], -1)
end

-- Reset parameters
function reset_macro_parameters()
    -- Reset core parameters (skip locked ones)
    if not MACRO.locked.intensity then
        MACRO.intensity = 0.5
    end
    if not MACRO.locked.center then
        MACRO.center = 0.5
    end
    
    -- These are always reset (not lockable)
    MACRO.duration = 30.0
    MACRO.smoothness = 200
    MACRO.min_value = 0.0
    MACRO.max_value = 1.0
    
    -- Reset organic parameters (skip locked ones)
    if not MACRO.locked.complexity then
        MACRO.complexity = math.random() * 0.6 + 0.2  -- 0.2-0.8
    end
    if not MACRO.locked.flow then
        MACRO.flow = math.random() * 2.5 + 0.5  -- 0.5-3.0
    end
    if not MACRO.locked.randomness then
        MACRO.randomness = 1.5  -- Default randomness value
    end
    if not MACRO.locked.peak_irregularity then
        MACRO.peak_irregularity = math.random() * 0.5 + 0.2  -- 0.2-0.7
    end
    
    MACRO.currentAlgorithm = 1 -- Default to Fractal Curves
    MACRO.seed = math.random(1, 999999)
    
    -- Reset algorithm-specific parameters to defaults (skip locked ones)
    if not MACRO.locked.algo_param1 then
        MACRO.fractal.octaves = 9
        MACRO.cellular.evolution_rate = 0.2025
        MACRO.generative.segment_length = 0.2
        MACRO.algo_param1 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param2 then
        MACRO.fractal.persistence = 0.4
        MACRO.cellular.random_activation = 0.405
        MACRO.generative.smoothing_factor = 21.0
        MACRO.algo_param2 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param3 then
        MACRO.fractal.frequency_scale = 10.0
        MACRO.cellular.smoothing_window = 21
        MACRO.generative.variation_scale = 0.03
        MACRO.algo_param3 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param4 then
        MACRO.fractal.lacunarity = 0.7
        MACRO.cellular.cell_count = 240
        MACRO.generative.momentum = 0.075
        MACRO.algo_param4 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param5 then
        MACRO.fractal.amplitude_bias = 1.9
        MACRO.cellular.rule_variation = 2.0
        MACRO.algo_param5 = nil -- Reset slider value
    end
end

-- Helper function for randomness power curve mapping
function map_randomness_value(slider_value)
    -- Map 0.0-10.0 slider range with power curve:
    -- First half (0.0-5.0) maps to 0.0-2.0
    -- Second half (5.0-10.0) maps to 2.0-10.0
    if slider_value <= 5.0 then
        return (slider_value / 5.0) * 2.0  -- Linear mapping for first half
    else
        local normalized = (slider_value - 5.0) / 5.0  -- 0.0-1.0 for second half
        return 2.0 + normalized * 8.0  -- 2.0-10.0 for second half
    end
end

-- Helper function to reverse map randomness value for display
function reverse_map_randomness_value(actual_value)
    -- Convert actual randomness value back to slider position
    if actual_value <= 2.0 then
        return (actual_value / 2.0) * 5.0  -- 0.0-2.0 maps to 0.0-5.0
    else
        local normalized = (actual_value - 2.0) / 8.0  -- 0.0-1.0 for values 2.0-10.0
        return 5.0 + normalized * 5.0  -- Maps to 5.0-10.0
    end
end

-- Helper function for randomness slider with power curve
function draw_randomness_slider(label, param_name, slider_width)
    ImGui.SetNextItemWidth(ctx, slider_width)
    
    -- Style locked parameters
    local is_locked = MACRO.locked[param_name]
    if is_locked then
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0xFF6B47AA)        -- Orange background for locked
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0xFF7B57BA) -- Slightly lighter on hover
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0xFF5B379A)  -- Slightly darker when active
    end
    
    -- Initialize parameter if it doesn't exist
    if MACRO[param_name] == nil then
        MACRO[param_name] = 1.5  -- Default randomness value
    end
    
    -- Convert actual randomness value to slider position for internal slider mechanics
    local slider_position = reverse_map_randomness_value(MACRO[param_name])
    
    -- Create a custom format string that shows the actual mapped value
    local display_value = MACRO[param_name]
    local format_string = string.format("%.1f", display_value)
    
    local changed, new_slider_value = ImGui.SliderDouble(ctx, label, slider_position, 0.0, 10.0, format_string)
    
    if changed then
        -- Convert slider position back to actual randomness value
        MACRO[param_name] = map_randomness_value(new_slider_value)
    end
    
    -- Pop style colors if we pushed them
    if is_locked then
        ImGui.PopStyleColor(ctx, 3)
    end
    
    -- Handle right-click for locking
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
        MACRO.locked[param_name] = not MACRO.locked[param_name]
    end
    
    return changed
end

-- Helper function for locked sliders
function draw_locked_slider(label, param_name, min_val, max_val, format, slider_width)
    ImGui.SetNextItemWidth(ctx, slider_width)
    
    -- Style locked parameters
    local is_locked = MACRO.locked[param_name]
    if is_locked then
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0xFF6B47AA)        -- Orange background for locked
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0xFF7B57BA) -- Slightly lighter on hover
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0xFF5B379A)  -- Slightly darker when active
    end
    
    -- Initialize parameter if it doesn't exist
    if MACRO[param_name] == nil then
        MACRO[param_name] = min_val
    end
    
    local changed, new_value = ImGui.SliderDouble(ctx, label, MACRO[param_name], min_val, max_val, format)
    MACRO[param_name] = new_value
    
    -- Pop style colors if we pushed them
    if is_locked then
        ImGui.PopStyleColor(ctx, 3)
    end
    
    -- Handle right-click for locking
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
        MACRO.locked[param_name] = not MACRO.locked[param_name]
    end
    
    return changed
end

-- GUI Functions
function draw_menu_bar()
    if ImGui.BeginMenuBar(ctx) then
        if ImGui.MenuItem(ctx, 'Help') then
            MACRO.showHelp = not MACRO.showHelp
        end
        ImGui.EndMenuBar(ctx)
    end
end

function draw_help_window()
    if MACRO.showHelp then
        if ImGui.Begin(ctx, 'Ambient 1 - Envelopes for Airports Help', true) then
            ImGui.Text(ctx, 'joshadambell - Ambient 1 - Envelopes for Airports Help')
            ImGui.Separator(ctx)
            
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Inspired by Brian Eno\'s Ambient Works')
            ImGui.Text(ctx, 'Creates organic, non-cyclical parameter evolution')
            ImGui.Text(ctx, 'Perfect for subtle filter sweeps, reverb breathing, texture shifts')
            
            ImGui.Separator(ctx)
            
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Setup:')
            ImGui.Text(ctx, '1. Select an automation envelope in REAPER')
            ImGui.Text(ctx, '2. Set time selection (15-60+ seconds recommended)')
            ImGui.Text(ctx, '3. Choose algorithm and adjust parameters')
            ImGui.Text(ctx, '4. Click "Generate Modulation"')
            
            ImGui.Separator(ctx)
            
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Algorithms:')
            ImGui.TextColored(ctx, 0xFF6666FF, '• Fractal Curves:')
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, ' Self-similar patterns using recursive noise')
            ImGui.TextColored(ctx, 0xFF6666FF, '• Cellular Automata:')
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, ' Emergent patterns from rule-based evolution')
            ImGui.TextColored(ctx, 0xFF6666FF, '• Generative Walk:')
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, ' Rule-based unpredictable movement')
            
            ImGui.Separator(ctx)
            
            ImGui.TextColored(ctx, 0xFF00FFFF, 'Parameters:')
            ImGui.Text(ctx, 'Intensity: How much the parameter changes (keep low for subtlety)')
            ImGui.Text(ctx, 'Center: Base value around which modulation occurs')
            ImGui.Text(ctx, 'Minimum Value: Lower clamp boundary for modulation')
            ImGui.Text(ctx, 'Maximum Value: Upper clamp boundary for modulation')
            ImGui.Text(ctx, 'Smoothness: Point density (higher = smoother curves)')
            ImGui.Text(ctx, 'Complexity: Detail layers + amplitude drift over time')
            ImGui.Text(ctx, 'Flow: Point-to-point blending and flow smoothness')
            ImGui.Text(ctx, 'Randomness: Random variations and fine-grain noise overlay')
            ImGui.Text(ctx, 'Peak Irregularity: Time warping + peak events for irregular peaks')
            
            if ImGui.Button(ctx, 'Close') then
                MACRO.showHelp = false
            end
        end
        ImGui.End(ctx)
    end
end

function draw_controls_bar()
    -- Auto Apply checkbox
    local auto_changed
    auto_changed, MACRO.autoApply = ImGui.Checkbox(ctx, 'Auto Apply Changes', MACRO.autoApply)
    
    -- Buttons on same line
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Generate Modulation', 150, 35) then
        apply_macro_modulation()
    end
    
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Reset', 80, 35) then
        reset_macro_parameters()
    end
    
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'New Seed', 80, 35) then
        MACRO.seed = math.random(1, 999999)
        if MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Randomize All', 100, 35) then
        -- Randomize all organic character parameters (skip locked ones)
        if not MACRO.locked.complexity then
            MACRO.complexity = math.random() * 0.6 + 0.2  -- 0.2-0.8
        end
        if not MACRO.locked.flow then
            MACRO.flow = math.random() * 2.5 + 0.5  -- 0.5-3.0
        end
        if not MACRO.locked.randomness then
            MACRO.randomness = math.random() * 3.0 + 0.5  -- 0.5-3.5 (will be mapped through power curve)
        end
        if not MACRO.locked.peak_irregularity then
            MACRO.peak_irregularity = math.random() * 0.5 + 0.2  -- 0.2-0.7
        end
        
        -- Also randomize core parameters within reasonable ranges (skip locked ones)
        if not MACRO.locked.intensity then
            MACRO.intensity = math.random() * 0.5 + 0.5  -- 0.5-1.0
        end
        if not MACRO.locked.center then
            MACRO.center = math.random() * 0.2 + 0.4  -- 0.4-0.6
        end
        
        -- Randomize algorithm-specific parameters (skip locked ones)
        if not MACRO.locked.algo_param1 then
            if MACRO.currentAlgorithm == 1 then -- Fractal Curves
                MACRO.fractal.octaves = math.random(1, 10)  -- 0-10
                MACRO.algo_param1 = MACRO.fractal.octaves
            elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
                MACRO.cellular.evolution_rate = math.random() * 0.395 + 0.005  -- 0.005-0.4
                MACRO.algo_param1 = MACRO.cellular.evolution_rate
            elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
                MACRO.generative.segment_length = math.random() * 0.29 + 0.01  -- 0.01-0.3
                MACRO.algo_param1 = MACRO.generative.segment_length
            end
        end
        
        if not MACRO.locked.algo_param2 then
            if MACRO.currentAlgorithm == 1 then -- Fractal Curves
                MACRO.fractal.persistence = math.random()  -- 0.0-1.0
                MACRO.algo_param2 = MACRO.fractal.persistence
            elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
                MACRO.cellular.random_activation = math.random() * 0.79 + 0.01  -- 0.01-0.8
                MACRO.algo_param2 = MACRO.cellular.random_activation
            elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
                MACRO.generative.smoothing_factor = math.random() * 49.99 + 0.01  -- 0.01-50.0
                MACRO.algo_param2 = MACRO.generative.smoothing_factor
            end
        end
        
        if not MACRO.locked.algo_param3 then
            if MACRO.currentAlgorithm == 1 then -- Fractal Curves
                MACRO.fractal.frequency_scale = math.random() * 19.0 + 1.0  -- 1.0-20.0
                MACRO.algo_param3 = MACRO.fractal.frequency_scale
            elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
                MACRO.cellular.smoothing_window = math.random(2, 40)  -- 2-40
                MACRO.algo_param3 = MACRO.cellular.smoothing_window
            elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
                MACRO.generative.variation_scale = math.random() * 0.04 + 0.01  -- 0.01-0.05
                MACRO.algo_param3 = MACRO.generative.variation_scale
            end
        end
        
        if not MACRO.locked.algo_param4 then
            if MACRO.currentAlgorithm == 1 then -- Fractal Curves
                MACRO.fractal.lacunarity = math.random() * 4.5 + 0.5  -- 0.5-5.0
                MACRO.algo_param4 = MACRO.fractal.lacunarity
            elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
                MACRO.cellular.cell_count = math.random(32, 512)  -- 32-512
                MACRO.algo_param4 = MACRO.cellular.cell_count
            elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
                MACRO.generative.momentum = math.random() * 0.099 + 0.001  -- 0.001-0.1
                MACRO.algo_param4 = MACRO.generative.momentum
            end
        end
        
        if not MACRO.locked.algo_param5 then
            if MACRO.currentAlgorithm == 1 then -- Fractal Curves
                MACRO.fractal.amplitude_bias = math.random() * 2.49 + 0.01  -- 0.01-2.5
                MACRO.algo_param5 = MACRO.fractal.amplitude_bias
            elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
                MACRO.cellular.rule_variation = math.random() * 4.0  -- 0.0-4.0
                MACRO.algo_param5 = MACRO.cellular.rule_variation
            end
        end
        
        -- Keep the same seed (don't change MACRO.seed)
        
        if MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.Separator(ctx)
end

function draw_target_info()
    local env, envName = get_selected_envelope()
    local env_changed = (MACRO.targetEnv ~= env)
    MACRO.targetEnv = env
    
    -- Auto-apply when new envelope is selected
    if env_changed and MACRO.autoApply and env and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    local startTime, endTime = get_time_selection()
    if endTime > startTime then
        ImGui.Text(ctx, string.format('Time selection: %.1f sec duration', endTime - startTime))
        MACRO.timeStart, MACRO.timeEnd = startTime, endTime
        
        -- Show recommended duration guidance
        local duration = endTime - startTime
        if duration < 10 then
            ImGui.TextColored(ctx, 0xFFFF00FF, 'Tip: 15+ seconds recommended for organic evolution')
        elseif duration > 120 then
            ImGui.TextColored(ctx, 0x00FF00FF, 'Perfect for long-form ambient modulation')
        else
            ImGui.TextColored(ctx, 0x00FFFFFF, 'Good duration for organic parameter evolution')
        end
    else
        ImGui.TextColored(ctx, 0xFFFFFF00, 'No time selection')
        MACRO.timeStart, MACRO.timeEnd = 0, 0
    end
end

function draw_parameters()
    ImGui.SeparatorText(ctx, 'Macro Modulation Parameters')
    
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local slider_width = math.max(300, content_width - 150)
    
    -- Core Parameters
    ImGui.Text(ctx, 'Core Settings')
    local intensity_changed = draw_locked_slider('Intensity', 'intensity', 0.0, 1.0, '%.3f', slider_width)
    if intensity_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    local center_changed = draw_locked_slider('Center', 'center', 0.0, 1.0, '%.3f', slider_width)
    if center_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    ImGui.Separator(ctx)
    
    -- Organic Parameters  
    ImGui.Text(ctx, 'Organic Character')
    local complexity_changed = draw_locked_slider('Complexity', 'complexity', 0.0, 1.0, '%.3f', slider_width)
    if complexity_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    local flow_changed = draw_locked_slider('Flow', 'flow', 0.0, 3.0, '%.3f', slider_width)
    if flow_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    local randomness_changed = draw_randomness_slider('Randomness', 'randomness', slider_width)
    if randomness_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    local peak_irregularity_changed = draw_locked_slider('Peak Irregularity', 'peak_irregularity', 0.0, 1.0, '%.3f', slider_width)
    if peak_irregularity_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    ImGui.Separator(ctx)
    
    -- Seed
    ImGui.Text(ctx, 'Randomization')
    ImGui.SetNextItemWidth(ctx, slider_width)
    local seed_changed
    seed_changed, MACRO.seed = ImGui.SliderInt(ctx, 'Random Seed', MACRO.seed, 1, 999999, '%d')
    if seed_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    ImGui.Separator(ctx)
    
    -- Range and Quality Settings (moved to bottom)
    ImGui.Text(ctx, 'Range and Quality')
    ImGui.SetNextItemWidth(ctx, slider_width)
    local min_changed
    min_changed, MACRO.min_value = ImGui.SliderDouble(ctx, 'Minimum Value', MACRO.min_value, 0.0, 1.0, '%.3f')
    if min_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    local max_changed
    max_changed, MACRO.max_value = ImGui.SliderDouble(ctx, 'Maximum Value', MACRO.max_value, 0.0, 1.0, '%.3f')
    if max_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    -- Ensure min <= max
    if MACRO.min_value > MACRO.max_value then
        MACRO.max_value = MACRO.min_value
    end
    
    ImGui.SetNextItemWidth(ctx, slider_width)
    local smoothness_changed
    smoothness_changed, MACRO.smoothness = ImGui.SliderInt(ctx, 'Smoothness (pts/min)', MACRO.smoothness, 60, 500, '%d')
    if smoothness_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
end

function draw_algorithm_parameters()
    ImGui.SeparatorText(ctx, 'Algorithm Parameters')
    
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local slider_width = math.max(300, content_width - 150)
    
    if MACRO.currentAlgorithm == 1 then -- Fractal Curves
        ImGui.Text(ctx, 'Fractal Curves Settings')
        
        -- Initialize sliders with current values for this algorithm
        if not MACRO.algo_param1 then MACRO.algo_param1 = MACRO.fractal.octaves end
        if not MACRO.algo_param2 then MACRO.algo_param2 = MACRO.fractal.persistence end
        if not MACRO.algo_param3 then MACRO.algo_param3 = MACRO.fractal.frequency_scale end
        if not MACRO.algo_param4 then MACRO.algo_param4 = MACRO.fractal.lacunarity end
        if not MACRO.algo_param5 then MACRO.algo_param5 = MACRO.fractal.amplitude_bias end
        
        local octaves_changed = draw_locked_slider('Octaves', 'algo_param1', 0, 10, '%.0f', slider_width)
        MACRO.fractal.octaves = math.floor(MACRO.algo_param1)
        if octaves_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local persistence_changed = draw_locked_slider('Persistence', 'algo_param2', 0.0, 1.0, '%.2f', slider_width)
        MACRO.fractal.persistence = MACRO.algo_param2
        if persistence_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local freq_changed = draw_locked_slider('Frequency Scale', 'algo_param3', 1.0, 20.0, '%.1f', slider_width)
        MACRO.fractal.frequency_scale = MACRO.algo_param3
        if freq_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local lacunarity_changed = draw_locked_slider('Lacunarity', 'algo_param4', 0.01, 1.0, '%.2f', slider_width)
        MACRO.fractal.lacunarity = MACRO.algo_param4
        if lacunarity_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local bias_changed = draw_locked_slider('Amplitude Bias', 'algo_param5', 0.01, 2.5, '%.2f', slider_width)
        MACRO.fractal.amplitude_bias = MACRO.algo_param5
        if bias_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
    elseif MACRO.currentAlgorithm == 2 then -- Cellular Automata
        ImGui.Text(ctx, 'Cellular Automata Settings')
        
        -- Initialize sliders with current values for this algorithm
        if not MACRO.algo_param1 then MACRO.algo_param1 = MACRO.cellular.evolution_rate end
        if not MACRO.algo_param2 then MACRO.algo_param2 = MACRO.cellular.random_activation end
        if not MACRO.algo_param3 then MACRO.algo_param3 = MACRO.cellular.smoothing_window end
        if not MACRO.algo_param4 then MACRO.algo_param4 = MACRO.cellular.cell_count end
        if not MACRO.algo_param5 then MACRO.algo_param5 = MACRO.cellular.rule_variation end
        
        local evolution_changed = draw_locked_slider('Evolution Rate', 'algo_param1', 0.005, 2.0, '%.3f', slider_width)
        MACRO.cellular.evolution_rate = MACRO.algo_param1
        if evolution_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local activation_changed = draw_locked_slider('Random Activation', 'algo_param2', 0.01, 2.0, '%.3f', slider_width)
        MACRO.cellular.random_activation = MACRO.algo_param2
        if activation_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local smoothing_changed = draw_locked_slider('Smoothing Window', 'algo_param3', 2, 40, '%.0f', slider_width)
        MACRO.cellular.smoothing_window = math.floor(MACRO.algo_param3)
        if smoothing_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local cell_count_changed = draw_locked_slider('Cell Count', 'algo_param4', 32, 512, '%.0f', slider_width)
        MACRO.cellular.cell_count = math.floor(MACRO.algo_param4)
        if cell_count_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local rule_var_changed = draw_locked_slider('Rule Variation', 'algo_param5', 0.0, 4.0, '%.2f', slider_width)
        MACRO.cellular.rule_variation = MACRO.algo_param5
        if rule_var_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
    elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
        ImGui.Text(ctx, 'Generative Walk Settings')
        
        -- Initialize sliders with current values for this algorithm
        if not MACRO.algo_param1 then MACRO.algo_param1 = MACRO.generative.segment_length end
        if not MACRO.algo_param2 then MACRO.algo_param2 = MACRO.generative.smoothing_factor end
        if not MACRO.algo_param3 then MACRO.algo_param3 = MACRO.generative.variation_scale end
        if not MACRO.algo_param4 then MACRO.algo_param4 = MACRO.generative.momentum end
        
        local segment_changed = draw_locked_slider('Segment Length', 'algo_param1', 0.01, 0.3, '%.3f', slider_width)
        MACRO.generative.segment_length = MACRO.algo_param1
        if segment_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local smooth_changed = draw_locked_slider('Smoothing Factor', 'algo_param2', 0.01, 50.0, '%.2f', slider_width)
        MACRO.generative.smoothing_factor = MACRO.algo_param2
        if smooth_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local variation_changed = draw_locked_slider('Variation Scale', 'algo_param3', 0.01, 0.05, '%.3f', slider_width)
        MACRO.generative.variation_scale = MACRO.algo_param3
        if variation_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local momentum_changed = draw_locked_slider('Momentum', 'algo_param4', 0.001, 0.1, '%.3f', slider_width)
        MACRO.generative.momentum = MACRO.algo_param4
        if momentum_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.Separator(ctx)
end

function draw_algorithm_selector()
    ImGui.SeparatorText(ctx, 'Modulation Algorithm')
    
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local button_width = math.max(150, (content_width - 30) / 4) -- 4 buttons with spacing
    
    -- Draw algorithm buttons in a single row
    for i, algorithmName in ipairs(algorithms) do
        local is_selected = (MACRO.currentAlgorithm == i)
        
        -- Style selected button differently
        if is_selected then
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x4A90E2FF)        -- Blue for selected
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x5BA0F2FF) -- Lighter blue for hover
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x357ABDFF)  -- Darker blue for active
        end
        
        if ImGui.Button(ctx, algorithmName, button_width, 30) then
            local old_algorithm = MACRO.currentAlgorithm
            MACRO.currentAlgorithm = i
            
            -- Reset algorithm parameters when switching algorithms
            if old_algorithm ~= i then
                MACRO.algo_param1 = nil
                MACRO.algo_param2 = nil
                MACRO.algo_param3 = nil
                MACRO.algo_param4 = nil
                -- Only reset algo_param5 for algorithms that use it (Fractal and Cellular)
                if i == 1 or i == 2 then
                    MACRO.algo_param5 = nil
                end
            end
            
            -- Auto apply if enabled, but only if we have a valid envelope and time range
            if MACRO.autoApply and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
                apply_macro_modulation()
            end
        end
        
        if is_selected then
            ImGui.PopStyleColor(ctx, 3) -- Pop the 3 colors we pushed
        end
        
        -- Add buttons on same line except for the last one
        if i < #algorithms then
            ImGui.SameLine(ctx)
        end
    end
    
    -- Algorithm descriptions
    local descriptions = {
        "Self-similar patterns using recursive noise octaves", 
        "Emergent patterns from 1D cellular automaton evolution",
        "Rule-based but unpredictable segment-based movement"
    }
    
    ImGui.TextColored(ctx, 0xAAAAAAAA, descriptions[MACRO.currentAlgorithm])
end

-- Main GUI loop
function main_loop()
    ImGui.SetNextWindowSizeConstraints(ctx, 750, 650, math.huge, math.huge)
    ImGui.SetNextWindowBgAlpha(ctx, 1.0)
    
    local visible, open = ImGui.Begin(ctx, 'joshadambell - Ambient 1 - Envelopes for Airports', true, ImGui.WindowFlags_MenuBar)
    
    if visible then
        draw_menu_bar()
        draw_controls_bar()
        draw_target_info()
        draw_algorithm_selector()
        draw_algorithm_parameters()
        draw_parameters()
    end
    
    ImGui.End(ctx)
    
    -- Help window
    draw_help_window()
    
    if open then
        reaper.defer(main_loop)
    end
end

-- Initialize and start
function init()
    -- Set random seed
    math.randomseed(os.time())
    MACRO.seed = math.random(1, 999999)
    
    ImGui.SetNextWindowSize(ctx, 800, 700, ImGui.Cond_FirstUseEver)
    main_loop()
end

-- Start the script
init()