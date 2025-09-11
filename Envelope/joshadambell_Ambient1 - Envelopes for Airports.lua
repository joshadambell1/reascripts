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
    enoMode = false,  -- Toggle for Eno Mode color scheme
    
    -- Algorithm-specific parameters (all set to midpoint of slider ranges)
    fractal = {
        type = 1,                  -- 1=fBm, 2=Ridged, 3=Turbulence (default: 1)
        octaves = 9,               -- 0 - 10 (default: 9)
        persistence = 0.4,         -- 0.0 - 1.0 (default: 0.4)
        frequency_scale = 10.0,    -- 1.0 - 20.0 (default: 10.0)
        lacunarity = 0.7,          -- 0.5 - 5.0 (default: 0.7)
        amplitude_bias = 1.9       -- 0.01 - 2.5 (default: 1.9)
    },
    
    sine_wave = {
        wave_count = 4,            -- 1 - 30 (default: 4)
        frequency_spread = 2.5,    -- 0.5 - 10.0 (default: 2.5)
        amplitude_variation = 0.6, -- 0.1 - 2.0 (default: 0.6)
        phase_drift = 1.2,         -- 0.1 - 30.0 (default: 1.2)
        beat_frequency = 0.8       -- 0.1 - 10.0 (default: 0.8)
    },
    
    generative = {
        segment_length = 0.2,      -- 0.01 - 0.3 (default: 0.2)
        smoothing_factor = 21.0,   -- 0.01 - 50.0 (default: 21.0)
        variation_scale = 0.03,    -- 0.01 - 0.05 (default: 0.03)
        momentum = 0.075,          -- 0.001 - 0.1 (default: 0.075)
        levy_probability = 0.02,   -- 0.0 - 0.1 (default: 0.02) - chance of Lévy flight
        markov_bias = 0.0          -- -1.0 - 1.0 (default: 0.0) - bias toward high/low regions
    },
    
    l_systems = {
        iterations = 3,            -- 1 - 6 (default: 3)
        branch_angle = 25.0,       -- 10.0 - 90.0 (default: 25.0)
        length_scale = 0.7,        -- 0.3 - 0.95 (default: 0.7)
        growth_rate = 1.5,         -- 0.01 - 4.0 (default: 1.5)
        complexity_factor = 0.6,   -- 0.2 - 1.0 (default: 0.6)
        max_change_rate = 3.0,     -- 0.1 - 10.0 (default: 3.0)
        tilt = 0.0,                -- -1.0 - 1.0 (default: 0.0)
        mapping_mode = 1           -- 1=Y-values, 2=Branch Density, 3=Recursion Depth, 4=Symmetry Axis
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
        algo_param5 = false,
        max_change_rate = false
    }
}

-- Organic modulation algorithms
local algorithms = {
    "Fractal Curves", 
    "Sine Wave Interference",
    "Generative Walk",
    "L-Systems"
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


-- Fractal curve generator with multiple types: fBm, Ridged, Turbulence
local function fractal_noise(x, octaves, persistence, lacunarity, amplitude_bias, seed, fractal_type)
    fractal_type = fractal_type or 1  -- Default to fBm
    
    local value = 0
    local amplitude = 1
    local frequency = 1
    local max_value = 0
    
    for i = 1, octaves do
        local octave_value = smooth_noise(x * frequency, seed + i * 1000)
        
        -- Apply fractal type variations
        if fractal_type == 2 then
            -- Ridged multifractal: invert and sharpen peaks
            octave_value = 1.0 - math.abs(octave_value)
            octave_value = octave_value * octave_value  -- Sharpen ridges
        elseif fractal_type == 3 then
            -- Turbulence: use absolute value for chaotic patterns
            octave_value = math.abs(octave_value)
        end
        -- fractal_type == 1 (fBm) uses octave_value as-is
        
        -- Apply amplitude bias - weights higher/lower frequencies differently
        local biased_amplitude = amplitude * (amplitude_bias ^ (i - 1))
        value = value + octave_value * biased_amplitude
        max_value = max_value + biased_amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end
    
    return value / max_value
end


-- Sine wave interference state for organic beating patterns
local sine_wave_state = {
    last_time = -1,
    wave_phases = {},
    amplitude_phases = {}
}

-- Generative walk state for momentum
local generative_state = {
    last_value = 0,
    velocity = 0,
    last_time = -1
}

-- Initialize sine wave interference system
local function init_sine_wave_system(wave_count, seed)
    sine_wave_state.wave_phases = {}
    sine_wave_state.amplitude_phases = {}
    
    -- Generate unique phases for each wave to avoid perfect synchronization
    for i = 1, wave_count do
        local phase_random, _ = seeded_random(seed + i * 50, 0, 2 * math.pi)
        local amp_phase_random, _ = seeded_random(seed + i * 100 + 25, 0, 2 * math.pi)
        
        sine_wave_state.wave_phases[i] = phase_random
        sine_wave_state.amplitude_phases[i] = amp_phase_random
    end
end

-- Generate sine wave interference pattern
local function generate_sine_wave_interference(time_pos, seed)
    local wave_count = MACRO.sine_wave.wave_count
    local interference_sum = 0
    local total_amplitude = 0
    
    -- Initialize if needed
    if #sine_wave_state.wave_phases == 0 then
        init_sine_wave_system(wave_count, seed)
    end
    
    -- Generate multiple interfering sine waves
    for i = 1, wave_count do
        -- Calculate frequency for this wave
        local base_frequency = 1.0  -- Base frequency
        local frequency_multiplier = 1.0 + (i - 1) * MACRO.sine_wave.frequency_spread / (wave_count - 1)
        local wave_frequency = base_frequency * frequency_multiplier
        
        -- Calculate phase with drift
        local phase_drift_rate = MACRO.sine_wave.phase_drift * (i / wave_count)  -- Different drift rates per wave
        local current_phase = sine_wave_state.wave_phases[i] + time_pos * phase_drift_rate
        
        -- Calculate amplitude with variation
        local base_amplitude = 1.0 / wave_count  -- Normalize so all waves together ≈ 1.0
        local amplitude_variation_rate = MACRO.sine_wave.beat_frequency * (i * 0.7)  -- Different beat rates
        local amplitude_phase = sine_wave_state.amplitude_phases[i] + time_pos * amplitude_variation_rate
        local amplitude_multiplier = 1.0 + MACRO.sine_wave.amplitude_variation * math.sin(amplitude_phase)
        local wave_amplitude = base_amplitude * amplitude_multiplier
        
        -- Generate the sine wave
        local wave_value = wave_amplitude * math.sin(time_pos * wave_frequency * 2 * math.pi + current_phase)
        
        interference_sum = interference_sum + wave_value
        total_amplitude = total_amplitude + wave_amplitude
    end
    
    -- Normalize to maintain reasonable amplitude range
    if total_amplitude > 0 then
        interference_sum = interference_sum / total_amplitude
    end
    
    return interference_sum
end

-- L-Systems state
local l_systems_state = {
    pattern = {},
    last_seed = 0,
    branch_points = {},
    last_value = 0,
    last_time = -1
}

-- Generate L-Systems pattern
local function generate_l_systems_pattern(time_pos, seed)
    local iterations = MACRO.l_systems.iterations
    local branch_angle = MACRO.l_systems.branch_angle
    local length_scale = MACRO.l_systems.length_scale
    local growth_rate = MACRO.l_systems.growth_rate
    local complexity_factor = MACRO.l_systems.complexity_factor
    
    -- Reinitialize if seed changed
    if l_systems_state.last_seed ~= seed then
        l_systems_state.last_seed = seed
        math.randomseed(seed)
        
        -- Generate L-system pattern using recursive rules
        -- Start with axiom "F" (forward)
        local pattern = "F"
        
        -- Apply production rules for specified iterations
        for iter = 1, iterations do
            local new_pattern = ""
            for i = 1, #pattern do
                local char = pattern:sub(i, i)
                if char == "F" then
                    -- F -> F[+F]F[-F]F (forward, branch up, forward, branch down, forward)
                    new_pattern = new_pattern .. "F[+F]F[-F]"
                elseif char == "+" then
                    -- + means turn right
                    new_pattern = new_pattern .. "+"
                elseif char == "-" then
                    -- - means turn left  
                    new_pattern = new_pattern .. "-"
                elseif char == "[" then
                    -- [ means push position
                    new_pattern = new_pattern .. "["
                elseif char == "]" then
                    -- ] means pop position
                    new_pattern = new_pattern .. "]"
                else
                    new_pattern = new_pattern .. char
                end
            end
            pattern = new_pattern
        end
        
        -- Convert pattern to coordinate points
        l_systems_state.pattern = {}
        l_systems_state.branch_points = {}
        
        local x, y = 0, 0
        local angle = math.pi/2  -- Start pointing up
        local length = 1.0
        local position_stack = {}
        local point_index = 1
        
        -- Add starting point
        l_systems_state.pattern[point_index] = {x = x, y = y, time = 0}
        point_index = point_index + 1
        
        for i = 1, #pattern do
            local char = pattern:sub(i, i)
            if char == "F" then
                -- Move forward
                x = x + length * math.cos(angle)
                y = y + length * math.sin(angle) 
                local time_factor = (point_index - 1) / math.max(1, #pattern * 0.3)  -- Spread over time
                l_systems_state.pattern[point_index] = {x = x, y = y, time = time_factor}
                point_index = point_index + 1
                length = length * length_scale  -- Scale down for next segment
            elseif char == "+" then
                -- Turn right
                angle = angle - (branch_angle * math.pi / 180) * complexity_factor
            elseif char == "-" then
                -- Turn left  
                angle = angle + (branch_angle * math.pi / 180) * complexity_factor
            elseif char == "[" then
                -- Push current state
                table.insert(position_stack, {x = x, y = y, angle = angle, length = length})
            elseif char == "]" then
                -- Pop previous state
                if #position_stack > 0 then
                    local state = table.remove(position_stack)
                    x, y, angle, length = state.x, state.y, state.angle, state.length
                end
            end
        end
        
        -- Normalize coordinates to -1 to +1 range
        local min_x, max_x = math.huge, -math.huge
        local min_y, max_y = math.huge, -math.huge
        
        for _, point in ipairs(l_systems_state.pattern) do
            min_x = math.min(min_x, point.x)
            max_x = math.max(max_x, point.x)  
            min_y = math.min(min_y, point.y)
            max_y = math.max(max_y, point.y)
        end
        
        local range_x = max_x - min_x
        local range_y = max_y - min_y
        local max_range = math.max(range_x, range_y, 0.001)  -- Prevent division by zero
        
        for _, point in ipairs(l_systems_state.pattern) do
            point.x = (point.x - min_x - range_x/2) / max_range * 2
            point.y = (point.y - min_y - range_y/2) / max_range * 2
        end
    end
    
    -- Sample the pattern at the given time position
    if #l_systems_state.pattern < 2 then
        return 0
    end
    
    -- Apply growth rate to time position
    local adjusted_time = (time_pos * growth_rate) % 1.0
    
    -- Find the appropriate segment in the pattern
    local target_time = adjusted_time
    local closest_point = 1
    local min_time_diff = math.huge
    
    for i, point in ipairs(l_systems_state.pattern) do
        local time_diff = math.abs(point.time - target_time)
        if time_diff < min_time_diff then
            min_time_diff = time_diff
            closest_point = i
        end
    end
    
    -- Get current point
    local current_point = l_systems_state.pattern[closest_point]
    
    -- Calculate base value based on mapping mode
    local raw_value
    local mapping_mode = MACRO.l_systems.mapping_mode or 1
    
    if mapping_mode == 1 then
        -- Y-values (default): Traditional height-based mapping
        local base_value = current_point.y
        local x_influence = current_point.x * complexity_factor * 0.3
        raw_value = base_value + x_influence
        
    elseif mapping_mode == 4 then
        -- Symmetry Axis: X-coordinate bias with Y influence  
        raw_value = current_point.x * 0.7 + current_point.y * 0.3
    end
    
    -- Prevent sudden spikes by limiting rate of change
    if l_systems_state.last_time >= 0 and time_pos > l_systems_state.last_time then
        local time_delta = time_pos - l_systems_state.last_time
        local value_delta = raw_value - l_systems_state.last_value
        
        -- Use user-controlled maximum change rate
        local max_change_rate = MACRO.l_systems.max_change_rate
        local max_allowed_change = max_change_rate * time_delta
        
        -- Limit the change if it's too large
        if math.abs(value_delta) > max_allowed_change then
            local sign = value_delta >= 0 and 1 or -1
            raw_value = l_systems_state.last_value + sign * max_allowed_change
        end
    end
    
    -- Apply tilt to counteract constant growth/decline
    local tilt = MACRO.l_systems.tilt
    if tilt ~= 0 then
        -- Apply a time-based bias to push the envelope left or right
        -- Negative tilt = bias toward lower values (left tilt)
        -- Positive tilt = bias toward higher values (right tilt)
        local tilt_influence = tilt * 0.5  -- Scale the tilt effect
        raw_value = raw_value + tilt_influence * (time_pos - 0.5) * 2  -- -1 to +1 based on time position
    end
    
    -- Reset tracking if we've gone backwards in time (new generation)
    if time_pos < l_systems_state.last_time then
        l_systems_state.last_value = 0
    end
    
    -- Update state tracking
    l_systems_state.last_time = time_pos
    l_systems_state.last_value = raw_value
    
    return math.max(-1, math.min(1, raw_value))  -- Clamp to [-1, 1]
end

-- STEP 1: Generate base algorithm (-1 to +1 normalized)
function generate_base_algorithm(time_pos, current_seed)
    local base_value = 0
    
    if MACRO.currentAlgorithm == 1 then -- Fractal Curves
        -- Self-similar patterns using user-controlled fractal noise
        base_value = fractal_noise(time_pos * MACRO.fractal.frequency_scale, MACRO.fractal.octaves, MACRO.fractal.persistence, MACRO.fractal.lacunarity, MACRO.fractal.amplitude_bias, current_seed, MACRO.fractal.type)
        
    elseif MACRO.currentAlgorithm == 2 then -- Sine Wave Interference
        -- Reset or initialize sine wave system
        if sine_wave_state.last_time > time_pos or sine_wave_state.last_time == -1 then
            init_sine_wave_system(MACRO.sine_wave.wave_count, current_seed)
            sine_wave_state.last_time = 0
        end
        
        -- Generate sine wave interference pattern
        base_value = generate_sine_wave_interference(time_pos, current_seed)
        
        sine_wave_state.last_time = time_pos
        
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
        
        -- Check for Lévy flight (rare large jumps)
        local levy_check, _ = seeded_random(segment_seed + 10000, 0, 1)
        local is_levy_flight = levy_check < MACRO.generative.levy_probability
        
        local variation_scale = MACRO.generative.variation_scale
        if is_levy_flight then
            -- Lévy flight: much larger movement
            variation_scale = variation_scale * 5  -- 5x larger jump
        end
        
        local segment_start, _ = seeded_random(segment_seed, -variation_scale, variation_scale)
        local segment_end, _ = seeded_random(segment_seed + 1, -variation_scale, variation_scale)
        
        -- Apply Markov biasing based on current position
        if MACRO.generative.markov_bias ~= 0 then
            local current_pos = generative_state.last_value or 0
            local bias_strength = MACRO.generative.markov_bias
            
            -- Bias toward target regions: positive bias = high values, negative = low values
            local target_region = bias_strength  -- -1 to 1 range
            local bias_factor = (target_region - current_pos) * 0.3  -- Gradual pull toward target
            
            segment_start = segment_start + bias_factor
            segment_end = segment_end + bias_factor
        end
        
        
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
        
    elseif MACRO.currentAlgorithm == 4 then -- L-Systems
        -- Generate L-Systems branching pattern
        base_value = generate_l_systems_pattern(time_pos, current_seed)
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
        
    elseif MACRO.currentAlgorithm == 2 then -- Sine Wave Interference
        local count_factor = (MACRO.sine_wave.wave_count - 1) / 29                 -- 0.0-1.0
        local spread_factor = (MACRO.sine_wave.frequency_spread - 0.5) / 9.5       -- 0.0-1.0
        local amplitude_factor = (MACRO.sine_wave.amplitude_variation - 0.1) / 1.9 -- 0.0-1.0
        local phase_factor = (MACRO.sine_wave.phase_drift - 0.1) / 29.9            -- 0.0-1.0
        local beat_factor = (MACRO.sine_wave.beat_frequency - 0.1) / 9.9           -- 0.0-1.0
        
        local composite = (count_factor * 0.2) + (spread_factor * 0.25) + 
                         (amplitude_factor * 0.2) + (phase_factor * 0.2) + (beat_factor * 0.15)
        return 0.4 + composite * 1.6  -- Range: 0.4x to 2.0x
        
    elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
        local segment_factor = (0.3 - MACRO.generative.segment_length) / 0.29    -- Inverted: shorter = higher
        local smooth_factor = MACRO.generative.smoothing_factor / 50.0           -- 0.0002-1.0
        local variation_factor = (MACRO.generative.variation_scale - 0.01) / 0.04 -- 0.0-1.0
        local momentum_factor = (MACRO.generative.momentum - 0.001) / 0.099      -- 0.0-1.0
        
        local composite = (segment_factor * 0.35) + (smooth_factor * 0.25) + 
                         (variation_factor * 0.2) + (momentum_factor * 0.2)
        return 0.5 + composite * 1.5  -- Range: 0.5x to 2.0x
        
    elseif MACRO.currentAlgorithm == 4 then -- L-Systems
        local iterations_factor = (MACRO.l_systems.iterations - 1) / 5           -- 0.0-1.0
        local angle_factor = (MACRO.l_systems.branch_angle - 10.0) / 80.0        -- 0.0-1.0
        local scale_factor = (MACRO.l_systems.length_scale - 0.3) / 0.65         -- 0.0-1.0
        local growth_factor = (MACRO.l_systems.growth_rate - 0.01) / 3.99        -- 0.0-1.0
        local complexity_factor = (MACRO.l_systems.complexity_factor - 0.2) / 0.8 -- 0.0-1.0
        
        local composite = (iterations_factor * 0.25) + (angle_factor * 0.2) + 
                         (scale_factor * 0.2) + (growth_factor * 0.2) + (complexity_factor * 0.15)
        return 0.6 + composite * 1.4  -- Range: 0.6x to 2.0x
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
    sine_wave_state = {last_time = -1, wave_phases = {}, amplitude_phases = {}}
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
            local _, _, _, _, _, _, detected_min, detected_max, _, type = reaper.BR_EnvGetProperties(br_env)
            
            if type == 0 or type == 1 then
                local retval, chunk = reaper.GetEnvelopeStateChunk(MACRO.targetEnv, "", false)
                if retval and chunk then
                    chunk = chunk:gsub("VOLTYPE %d+\n", "")
                    reaper.SetEnvelopeStateChunk(MACRO.targetEnv, chunk, false)
                end
                
                if detected_min and detected_max and detected_min ~= detected_max then
                    env_min, env_max = detected_min, detected_max
                else
                    env_min, env_max = 0, 1
                end
            else
                if detected_min and detected_max and detected_min ~= detected_max then
                    env_min, env_max = detected_min, detected_max
                end
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
        MACRO.complexity = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
    if not MACRO.locked.flow then
        MACRO.flow = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
    if not MACRO.locked.randomness then
        MACRO.randomness = 1.5  -- Default randomness value
    end
    if not MACRO.locked.peak_irregularity then
        MACRO.peak_irregularity = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
    
    MACRO.currentAlgorithm = 1 -- Default to Fractal Curves
    MACRO.seed = math.random(1, 999999)
    
    -- Reset algorithm-specific parameters to defaults (skip locked ones)
    if not MACRO.locked.algo_param1 then
        MACRO.fractal.type = 1  -- Reset to fBm
        MACRO.fractal.octaves = 9
        MACRO.sine_wave.wave_count = 4
        MACRO.generative.segment_length = 0.2
        MACRO.generative.levy_probability = 0.02
        MACRO.generative.markov_bias = 0.0
        MACRO.algo_param1 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param2 then
        MACRO.fractal.persistence = 0.4
        MACRO.sine_wave.frequency_spread = 2.5
        MACRO.generative.smoothing_factor = 21.0
        MACRO.algo_param2 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param3 then
        MACRO.fractal.frequency_scale = 10.0
        MACRO.sine_wave.amplitude_variation = 0.6
        MACRO.generative.variation_scale = 0.03
        MACRO.algo_param3 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param4 then
        MACRO.fractal.lacunarity = 0.7
        MACRO.sine_wave.phase_drift = 1.2
        MACRO.generative.momentum = 0.075
        MACRO.algo_param4 = nil -- Reset slider value
    end
    
    if not MACRO.locked.algo_param5 then
        MACRO.fractal.amplitude_bias = 1.9
        MACRO.sine_wave.beat_frequency = 0.8
        MACRO.l_systems.mapping_mode = 1  -- Reset to Y-values
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

-- Parameter handling helper functions
function randomize_core_parameters()
    -- Randomize core parameters within reasonable ranges (skip locked ones)
    if not MACRO.locked.intensity then
        MACRO.intensity = math.random() * 0.3 + 0.35  -- 0.35-0.65
    end
    if not MACRO.locked.center then
        MACRO.center = math.random() * 0.2 + 0.4  -- 0.4-0.6
    end
end

function randomize_organic_parameters()
    -- Randomize organic character parameters (skip locked ones)
    if not MACRO.locked.complexity then
        MACRO.complexity = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
    if not MACRO.locked.flow then
        MACRO.flow = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
    if not MACRO.locked.randomness then
        MACRO.randomness = math.random() * 3.0 + 0.5  -- 0.5-3.5 (will be mapped through power curve)
    end
    if not MACRO.locked.peak_irregularity then
        MACRO.peak_irregularity = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
end

function randomize_algorithm_parameters(algorithm)
    -- Randomize algorithm-specific parameters based on current algorithm
    if not MACRO.locked.algo_param1 then
        if algorithm == 1 then -- Fractal Curves
            MACRO.fractal.octaves = math.random(1, 10)
            MACRO.algo_param1 = MACRO.fractal.octaves
        elseif algorithm == 2 then -- Sine Wave Interference
            MACRO.sine_wave.wave_count = math.random(1, 30)
            MACRO.algo_param1 = MACRO.sine_wave.wave_count
        elseif algorithm == 3 then -- Generative Walk
            MACRO.generative.segment_length = math.random() * 0.29 + 0.01
            MACRO.algo_param1 = MACRO.generative.segment_length
        elseif algorithm == 4 then -- L-Systems
            MACRO.l_systems.iterations = math.random(1, 6)
            MACRO.algo_param1 = MACRO.l_systems.iterations
        end
    end
    
    if not MACRO.locked.algo_param2 then
        if algorithm == 1 then
            MACRO.fractal.persistence = math.random()
            MACRO.algo_param2 = MACRO.fractal.persistence
        elseif algorithm == 2 then
            MACRO.sine_wave.frequency_spread = math.random() * 9.5 + 0.5
            MACRO.algo_param2 = MACRO.sine_wave.frequency_spread
        elseif algorithm == 3 then
            MACRO.generative.smoothing_factor = math.random() * 49.99 + 0.01
            MACRO.algo_param2 = MACRO.generative.smoothing_factor
        elseif algorithm == 4 then
            MACRO.l_systems.branch_angle = math.random() * 80.0 + 10.0
            MACRO.algo_param2 = MACRO.l_systems.branch_angle
        end
    end
    
    if not MACRO.locked.algo_param3 then
        if algorithm == 1 then
            MACRO.fractal.frequency_scale = math.random() * 19.0 + 1.0
            MACRO.algo_param3 = MACRO.fractal.frequency_scale
        elseif algorithm == 2 then
            MACRO.sine_wave.amplitude_variation = math.random() * 1.9 + 0.1
            MACRO.algo_param3 = MACRO.sine_wave.amplitude_variation
        elseif algorithm == 3 then
            MACRO.generative.variation_scale = math.random() * 0.04 + 0.01
            MACRO.algo_param3 = MACRO.generative.variation_scale
        elseif algorithm == 4 then
            MACRO.l_systems.length_scale = math.random() * 0.65 + 0.3
            MACRO.algo_param3 = MACRO.l_systems.length_scale
        end
    end
    
    if not MACRO.locked.algo_param4 then
        if algorithm == 1 then
            MACRO.fractal.lacunarity = math.random() * 4.5 + 0.5
            MACRO.algo_param4 = MACRO.fractal.lacunarity
        elseif algorithm == 2 then
            MACRO.sine_wave.phase_drift = math.random() * 29.9 + 0.1
            MACRO.algo_param4 = MACRO.sine_wave.phase_drift
        elseif algorithm == 3 then
            MACRO.generative.momentum = math.random() * 0.099 + 0.001
            MACRO.algo_param4 = MACRO.generative.momentum
        elseif algorithm == 4 then
            MACRO.l_systems.growth_rate = math.random() * 3.99 + 0.01
            MACRO.algo_param4 = MACRO.l_systems.growth_rate
        end
    end
    
    if not MACRO.locked.algo_param5 then
        if algorithm == 1 then
            MACRO.fractal.amplitude_bias = math.random() * 2.49 + 0.01
            MACRO.algo_param5 = MACRO.fractal.amplitude_bias
        elseif algorithm == 2 then
            MACRO.sine_wave.beat_frequency = math.random() * 9.9 + 0.1
            MACRO.algo_param5 = MACRO.sine_wave.beat_frequency
        elseif algorithm == 3 then
            MACRO.generative.levy_probability = math.random() * 0.1
            MACRO.algo_param5 = MACRO.generative.levy_probability
        elseif algorithm == 4 then
            MACRO.l_systems.complexity_factor = math.random() * 0.8 + 0.2
            MACRO.algo_param5 = MACRO.l_systems.complexity_factor
        end
    end
end

-- Helper function for mild randomization (±20% around middle value)
local function randomize_mild(min_val, max_val)
    local range = max_val - min_val
    local middle = min_val + range * 0.5
    local variation = range * 0.2  -- ±20% of total range
    return middle + (math.random() - 0.5) * 2 * variation  -- Random between middle-variation and middle+variation
end

-- Mild randomization functions (±20% around middle values)
function randomize_core_parameters_mild()
    if not MACRO.locked.intensity then
        MACRO.intensity = randomize_mild(0.0, 1.0)  -- Middle: 0.5, Range: 0.3-0.7
    end
    if not MACRO.locked.center then
        MACRO.center = randomize_mild(0.0, 1.0)  -- Middle: 0.5, Range: 0.3-0.7
    end
end

function randomize_organic_parameters_mild()
    if not MACRO.locked.complexity then
        MACRO.complexity = randomize_mild(0.5, 3.5)  -- Middle: 2.0, Range: 1.4-2.6
    end
    if not MACRO.locked.flow then
        MACRO.flow = randomize_mild(0.5, 3.5)  -- Middle: 2.0, Range: 1.4-2.6
    end
    if not MACRO.locked.randomness then
        MACRO.randomness = randomize_mild(0.5, 3.5)  -- Middle: 2.0, Range: 1.4-2.6
    end
    if not MACRO.locked.peak_irregularity then
        MACRO.peak_irregularity = randomize_mild(0.5, 3.5)  -- Middle: 2.0, Range: 1.4-2.6
    end
end

function randomize_algorithm_parameters_mild(algorithm)
    if not MACRO.locked.algo_param1 then
        if algorithm == 1 then -- Fractal Curves
            MACRO.fractal.octaves = math.floor(randomize_mild(0, 10) + 0.5)  -- Round to integer
            MACRO.algo_param1 = MACRO.fractal.octaves
        elseif algorithm == 2 then -- Sine Wave Interference
            MACRO.sine_wave.wave_count = math.floor(randomize_mild(1, 30) + 0.5)  -- Round to integer
            MACRO.algo_param1 = MACRO.sine_wave.wave_count
        elseif algorithm == 3 then -- Generative Walk
            MACRO.generative.segment_length = randomize_mild(0.01, 0.3)
            MACRO.algo_param1 = MACRO.generative.segment_length
        elseif algorithm == 4 then -- L-Systems
            MACRO.l_systems.iterations = math.floor(randomize_mild(1, 6) + 0.5)  -- Round to integer
            MACRO.algo_param1 = MACRO.l_systems.iterations
        end
    end
    
    if not MACRO.locked.algo_param2 then
        if algorithm == 1 then
            MACRO.fractal.persistence = randomize_mild(0.0, 1.0)
            MACRO.algo_param2 = MACRO.fractal.persistence
        elseif algorithm == 2 then
            MACRO.sine_wave.frequency_spread = randomize_mild(0.5, 10.0)
            MACRO.algo_param2 = MACRO.sine_wave.frequency_spread
        elseif algorithm == 3 then
            MACRO.generative.smoothing_factor = randomize_mild(0.01, 50.0)
            MACRO.algo_param2 = MACRO.generative.smoothing_factor
        elseif algorithm == 4 then
            MACRO.l_systems.branch_angle = randomize_mild(10.0, 90.0)
            MACRO.algo_param2 = MACRO.l_systems.branch_angle
        end
    end
    
    if not MACRO.locked.algo_param3 then
        if algorithm == 1 then
            MACRO.fractal.frequency_scale = randomize_mild(1.0, 20.0)
            MACRO.algo_param3 = MACRO.fractal.frequency_scale
        elseif algorithm == 2 then
            MACRO.sine_wave.amplitude_variation = randomize_mild(0.1, 2.0)
            MACRO.algo_param3 = MACRO.sine_wave.amplitude_variation
        elseif algorithm == 3 then
            MACRO.generative.variation_scale = randomize_mild(0.01, 0.05)
            MACRO.algo_param3 = MACRO.generative.variation_scale
        elseif algorithm == 4 then
            MACRO.l_systems.length_scale = randomize_mild(0.3, 0.95)
            MACRO.algo_param3 = MACRO.l_systems.length_scale
        end
    end
    
    if not MACRO.locked.algo_param4 then
        if algorithm == 1 then
            MACRO.fractal.lacunarity = randomize_mild(0.5, 5.0)
            MACRO.algo_param4 = MACRO.fractal.lacunarity
        elseif algorithm == 2 then
            MACRO.sine_wave.phase_drift = randomize_mild(0.1, 30.0)
            MACRO.algo_param4 = MACRO.sine_wave.phase_drift
        elseif algorithm == 3 then
            MACRO.generative.momentum = randomize_mild(0.001, 0.1)
            MACRO.algo_param4 = MACRO.generative.momentum
        elseif algorithm == 4 then
            MACRO.l_systems.growth_rate = randomize_mild(0.01, 4.0)
            MACRO.algo_param4 = MACRO.l_systems.growth_rate
        end
    end
    
    if not MACRO.locked.algo_param5 then
        if algorithm == 1 then
            MACRO.fractal.amplitude_bias = randomize_mild(0.01, 2.5)
            MACRO.algo_param5 = MACRO.fractal.amplitude_bias
        elseif algorithm == 2 then
            MACRO.sine_wave.beat_frequency = randomize_mild(0.1, 10.0)
            MACRO.algo_param5 = MACRO.sine_wave.beat_frequency
        elseif algorithm == 3 then
            MACRO.generative.levy_probability = randomize_mild(0.0, 0.1)
            MACRO.algo_param5 = MACRO.generative.levy_probability
        elseif algorithm == 4 then
            MACRO.l_systems.complexity_factor = randomize_mild(0.2, 1.0)
            MACRO.algo_param5 = MACRO.l_systems.complexity_factor
        end
    end
end

-- Extreme randomization functions (copy of existing functions with full range)
function randomize_core_parameters_extreme()
    -- Randomize core parameters within reasonable ranges (skip locked ones)
    if not MACRO.locked.intensity then
        MACRO.intensity = math.random() * 0.3 + 0.35  -- 0.35-0.65
    end
    if not MACRO.locked.center then
        MACRO.center = math.random() * 0.2 + 0.4  -- 0.4-0.6
    end
end

function randomize_organic_parameters_extreme()
    -- Randomize organic character parameters (skip locked ones)
    if not MACRO.locked.complexity then
        MACRO.complexity = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
    if not MACRO.locked.flow then
        MACRO.flow = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
    if not MACRO.locked.randomness then
        MACRO.randomness = math.random() * 3.0 + 0.5  -- 0.5-3.5 (will be mapped through power curve)
    end
    if not MACRO.locked.peak_irregularity then
        MACRO.peak_irregularity = math.random() * 3.0 + 0.5  -- 0.5-3.5 (power curve range)
    end
end

function randomize_algorithm_parameters_extreme(algorithm)
    -- Copy of existing randomize_algorithm_parameters function (full range)
    if not MACRO.locked.algo_param1 then
        if algorithm == 1 then -- Fractal Curves
            MACRO.fractal.octaves = math.random(1, 10)
            MACRO.algo_param1 = MACRO.fractal.octaves
        elseif algorithm == 2 then -- Sine Wave Interference
            MACRO.sine_wave.wave_count = math.random(1, 30)
            MACRO.algo_param1 = MACRO.sine_wave.wave_count
        elseif algorithm == 3 then -- Generative Walk
            MACRO.generative.segment_length = math.random() * 0.29 + 0.01
            MACRO.algo_param1 = MACRO.generative.segment_length
        elseif algorithm == 4 then -- L-Systems
            MACRO.l_systems.iterations = math.random(1, 6)
            MACRO.algo_param1 = MACRO.l_systems.iterations
        end
    end
    
    if not MACRO.locked.algo_param2 then
        if algorithm == 1 then
            MACRO.fractal.persistence = math.random()
            MACRO.algo_param2 = MACRO.fractal.persistence
        elseif algorithm == 2 then
            MACRO.sine_wave.frequency_spread = math.random() * 9.5 + 0.5
            MACRO.algo_param2 = MACRO.sine_wave.frequency_spread
        elseif algorithm == 3 then
            MACRO.generative.smoothing_factor = math.random() * 49.99 + 0.01
            MACRO.algo_param2 = MACRO.generative.smoothing_factor
        elseif algorithm == 4 then
            MACRO.l_systems.branch_angle = math.random() * 80.0 + 10.0
            MACRO.algo_param2 = MACRO.l_systems.branch_angle
        end
    end
    
    if not MACRO.locked.algo_param3 then
        if algorithm == 1 then
            MACRO.fractal.frequency_scale = math.random() * 19.0 + 1.0
            MACRO.algo_param3 = MACRO.fractal.frequency_scale
        elseif algorithm == 2 then
            MACRO.sine_wave.amplitude_variation = math.random() * 1.9 + 0.1
            MACRO.algo_param3 = MACRO.sine_wave.amplitude_variation
        elseif algorithm == 3 then
            MACRO.generative.variation_scale = math.random() * 0.04 + 0.01
            MACRO.algo_param3 = MACRO.generative.variation_scale
        elseif algorithm == 4 then
            MACRO.l_systems.length_scale = math.random() * 0.65 + 0.3
            MACRO.algo_param3 = MACRO.l_systems.length_scale
        end
    end
    
    if not MACRO.locked.algo_param4 then
        if algorithm == 1 then
            MACRO.fractal.lacunarity = math.random() * 4.5 + 0.5
            MACRO.algo_param4 = MACRO.fractal.lacunarity
        elseif algorithm == 2 then
            MACRO.sine_wave.phase_drift = math.random() * 29.9 + 0.1
            MACRO.algo_param4 = MACRO.sine_wave.phase_drift
        elseif algorithm == 3 then
            MACRO.generative.momentum = math.random() * 0.099 + 0.001
            MACRO.algo_param4 = MACRO.generative.momentum
        elseif algorithm == 4 then
            MACRO.l_systems.growth_rate = math.random() * 3.99 + 0.01
            MACRO.algo_param4 = MACRO.l_systems.growth_rate
        end
    end
    
    if not MACRO.locked.algo_param5 then
        if algorithm == 1 then
            MACRO.fractal.amplitude_bias = math.random() * 2.49 + 0.01
            MACRO.algo_param5 = MACRO.fractal.amplitude_bias
        elseif algorithm == 2 then
            MACRO.sine_wave.beat_frequency = math.random() * 9.9 + 0.1
            MACRO.algo_param5 = MACRO.sine_wave.beat_frequency
        elseif algorithm == 3 then
            MACRO.generative.levy_probability = math.random() * 0.1
            MACRO.algo_param5 = MACRO.generative.levy_probability
        elseif algorithm == 4 then
            MACRO.l_systems.complexity_factor = math.random() * 0.8 + 0.2
            MACRO.algo_param5 = MACRO.l_systems.complexity_factor
        end
    end
end

-- Generic helper function for power curve sliders (0.01-10.0 range, 2.0 at center)
function draw_power_curve_slider(label, param_name, default_value, slider_width)
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
        MACRO[param_name] = default_value
    end
    
    -- Convert actual value to slider position for internal slider mechanics
    local slider_position = reverse_map_randomness_value(MACRO[param_name])
    
    -- Create a custom format string that shows the actual mapped value
    local display_value = MACRO[param_name]
    local format_string = string.format("%.2f", display_value)
    
    local changed, new_slider_value = ImGui.SliderDouble(ctx, label, slider_position, 0.01, 10.0, format_string)
    
    if changed then
        -- Convert slider position back to actual value
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

-- Helper function for randomness slider with power curve
function draw_randomness_slider(label, param_name, slider_width)
    return draw_power_curve_slider(label, param_name, 1.5, slider_width)
end

-- Helper function for locked sliders
function draw_locked_slider(label, param_name, min_val, max_val, format, slider_width)
    -- Draw lock icon first
    local is_locked = MACRO.locked[param_name]
    local lock_icon = is_locked and "[L]" or "[U]"  -- [L] = Locked, [U] = Unlocked
    
    -- Clickable lock button
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x00000000)        -- Transparent background
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x33333355) -- Subtle hover
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x55555577)  -- Subtle active
    
    if ImGui.Button(ctx, lock_icon .. "##lock_" .. param_name, 20, 0) then
        MACRO.locked[param_name] = not MACRO.locked[param_name]
        is_locked = MACRO.locked[param_name]  -- Update for styling
    end
    
    ImGui.PopStyleColor(ctx, 3)
    
    -- Tooltip for lock icon
    if ImGui.IsItemHovered(ctx) then
        local tooltip_text = is_locked and "Parameter is locked (excluded from randomization)" or "Parameter is unlocked (will be randomized)"
        ImGui.SetTooltip(ctx, tooltip_text)
    end
    
    -- Place slider on same line
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, slider_width - 25)  -- Account for lock button width
    
    -- Style locked parameters
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
    
    -- Still handle right-click for locking (alternative method)
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
        MACRO.locked[param_name] = not MACRO.locked[param_name]
    end
    
    return changed
end

-- XY Pad for Organic Character parameters (Corner-based mapping)
function draw_organic_xy_pad(pad_width, pad_height)
    local pad_pos = {ImGui.GetCursorScreenPos(ctx)}
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local mouse_pos = {ImGui.GetMousePos(ctx)}
    
    -- Initialize pad position if not set
    if not MACRO.pad_x then MACRO.pad_x = 0.5 end
    if not MACRO.pad_y then MACRO.pad_y = 0.5 end
    
    -- Create invisible button for interaction
    ImGui.InvisibleButton(ctx, 'organic_xy_pad', pad_width, pad_height)
    local pad_hovered = ImGui.IsItemHovered(ctx)
    local pad_active = ImGui.IsItemActive(ctx)
    local changed = false
    
    -- Draw pad background - use Eno Mode colors only when active
    local bg_color = MACRO.enoMode and 0x2D8A3AFF or 0x323232FF  -- Green in Eno Mode, dark gray otherwise
    local border_color = MACRO.enoMode and 0x000000FF or 0x666666FF  -- Black in Eno Mode, medium gray otherwise
    ImGui.DrawList_AddRectFilled(draw_list, pad_pos[1], pad_pos[2], 
                                pad_pos[1] + pad_width, pad_pos[2] + pad_height, bg_color)
    ImGui.DrawList_AddRect(draw_list, pad_pos[1], pad_pos[2], 
                          pad_pos[1] + pad_width, pad_pos[2] + pad_height, border_color)
    
    -- Draw grid lines and labels
    local mid_x = pad_pos[1] + pad_width / 2
    local mid_y = pad_pos[2] + pad_height / 2
    local grid_color = MACRO.enoMode and 0x000000FF or 0xAAAAAAFF  -- Black in Eno Mode, light gray otherwise
    local text_color = MACRO.enoMode and 0x000000FF or 0xFFFFFFFF  -- Black in Eno Mode, white otherwise
    
    -- Vertical center line
    ImGui.DrawList_AddLine(draw_list, mid_x, pad_pos[2], mid_x, pad_pos[2] + pad_height, grid_color)
    -- Horizontal center line  
    ImGui.DrawList_AddLine(draw_list, pad_pos[1], mid_y, pad_pos[1] + pad_width, mid_y, grid_color)
    
    -- Corner labels - sized and positioned to fit properly inside pad
    local label_margin = 8  -- Increased margin from edges
    local line_height = 12  -- Increased line height for bigger text
    local label_color = MACRO.enoMode and 0x000000FF or 0xFFFFFFFF  -- Black in Eno Mode, white otherwise
    
    -- Calculate text widths for better positioning
    local complexity_width = 60   -- Approximate width of "Complexity" text
    local randomness_width = 70   -- Approximate width of "Randomness" text
    local flow_width = 35         -- Approximate width of "+ Flow" text
    local peak_width = 75         -- Approximate width of "+ Peak Irreg" text
    
    -- Top-left corner
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + label_margin, pad_pos[2] + label_margin, label_color, 'Complexity')
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + label_margin, pad_pos[2] + label_margin + line_height, label_color, '+ Flow')
    
    -- Top-right corner - align right edge of text with right margin
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + pad_width - randomness_width - label_margin, pad_pos[2] + label_margin, label_color, 'Randomness')
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + pad_width - flow_width - label_margin, pad_pos[2] + label_margin + line_height, label_color, '+ Flow')
    
    -- Bottom-left corner
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + label_margin, pad_pos[2] + pad_height - (line_height * 2) - label_margin, label_color, 'Complexity')
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + label_margin, pad_pos[2] + pad_height - line_height - label_margin, label_color, '+ Peak Irreg')
    
    -- Bottom-right corner - align right edge of text with right margin  
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + pad_width - randomness_width - label_margin, pad_pos[2] + pad_height - (line_height * 2) - label_margin, label_color, 'Randomness')
    ImGui.DrawList_AddText(draw_list, pad_pos[1] + pad_width - peak_width - label_margin, pad_pos[2] + pad_height - line_height - label_margin, label_color, '+ Peak Irreg')
    
    -- Handle mouse interaction
    if pad_active then
        -- Store the actual pad position (linear) - this follows the cursor exactly
        local linear_x = math.max(0, math.min(1, (mouse_pos[1] - pad_pos[1]) / pad_width))
        local linear_y = math.max(0, math.min(1, 1.0 - (mouse_pos[2] - pad_pos[2]) / pad_height))  -- Flip Y axis
        
        -- Store linear position so cursor sticks to node
        MACRO.pad_x = linear_x
        MACRO.pad_y = linear_y
        
        -- Apply exponential/perceptual mapping for finer control near center
        -- Using power curve: more sensitive near center, full range at edges
        local function perceptual_map(linear_val)
            -- Center-biased mapping using power curve (exponent = 1.5 gives good feel)
            local centered = (linear_val - 0.5) * 2  -- -1 to 1
            local sign = centered >= 0 and 1 or -1  -- Simple sign function
            local mapped = sign * (math.abs(centered) ^ 1.5)  -- Apply power curve
            return (mapped / 2) + 0.5  -- Back to 0-1 range
        end
        
        -- Apply perceptual mapping for parameter calculations only
        local mapped_x = perceptual_map(linear_x)
        local mapped_y = perceptual_map(linear_y)
        
        -- Corner-based mapping using mapped values for parameters
        -- Each corner contributes based on distance to that corner
        local tl_dist = math.sqrt((mapped_x - 0)^2 + (mapped_y - 1)^2)        -- Top-left: Complexity + Flow
        local tr_dist = math.sqrt((mapped_x - 1)^2 + (mapped_y - 1)^2)        -- Top-right: Randomness + Flow  
        local bl_dist = math.sqrt((mapped_x - 0)^2 + (mapped_y - 0)^2)        -- Bottom-left: Complexity + Peak
        local br_dist = math.sqrt((mapped_x - 1)^2 + (mapped_y - 0)^2)        -- Bottom-right: Randomness + Peak
        
        -- Convert distances to influence (closer = more influence)
        local max_dist = math.sqrt(2)  -- Maximum possible distance
        local tl_influence = (max_dist - tl_dist) / max_dist
        local tr_influence = (max_dist - tr_dist) / max_dist
        local bl_influence = (max_dist - bl_dist) / max_dist
        local br_influence = (max_dist - br_dist) / max_dist
        
        -- Apply power curve mapping to get final values (0.0-5.0 range for maximum expressiveness)
        local min_val = 0.0
        local max_val = 5.0
        local base_val = 0.0  -- Base value when no influence
        
        MACRO.complexity = base_val + (tl_influence + bl_influence) * (max_val - min_val) / 2
        MACRO.flow = base_val + (tl_influence + tr_influence) * (max_val - min_val) / 2
        MACRO.randomness = base_val + (tr_influence + br_influence) * (max_val - min_val) / 2
        MACRO.peak_irregularity = base_val + (bl_influence + br_influence) * (max_val - min_val) / 2
        
        changed = true
    end
    
    -- Draw current position indicator using stored pad position
    if MACRO.pad_x and MACRO.pad_y then
        local indicator_x = pad_pos[1] + MACRO.pad_x * pad_width
        local indicator_y = pad_pos[2] + (1.0 - MACRO.pad_y) * pad_height  -- Flip Y
        local indicator_color = pad_active and 0xFF6666FF or 0xFFAAAAFF
        local indicator_radius = 4
        
        ImGui.DrawList_AddCircleFilled(draw_list, indicator_x, indicator_y, indicator_radius, indicator_color)
        ImGui.DrawList_AddCircle(draw_list, indicator_x, indicator_y, indicator_radius + 1, 0x000000AA)
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
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local button_width = math.max(100, (content_width - 50) / 6) -- 6 buttons with spacing
    
    -- Control buttons - full width layout
    if ImGui.Button(ctx, 'Reset', button_width, 35) then
        reset_macro_parameters()
        if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Randomise Seed', button_width, 35) then
        MACRO.seed = math.random(1, 999999)
        if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Randomise Params Mild', button_width, 35) then
        -- Use mild randomization functions (±20% around middle values)
        randomize_organic_parameters_mild()
        randomize_core_parameters_mild()
        randomize_algorithm_parameters_mild(MACRO.currentAlgorithm)
        
        -- Special L-Systems parameters (not part of algo_param system)
        if MACRO.currentAlgorithm == 4 then
            MACRO.l_systems.max_change_rate = math.random() * 9.9 + 0.1  -- 0.1-10.0
            MACRO.l_systems.tilt = 0.0  -- Keep tilt at neutral
        end
        
        if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Randomise All', button_width, 35) then
        -- Use helper functions - much cleaner!
        MACRO.seed = math.random(1, 999999)  -- Randomize seed first
        randomize_organic_parameters()
        randomize_core_parameters()  
        randomize_algorithm_parameters(MACRO.currentAlgorithm)
        
        -- Special L-Systems parameters
        if MACRO.currentAlgorithm == 4 then
            MACRO.l_systems.max_change_rate = math.random() * 9.9 + 0.1
            MACRO.l_systems.tilt = 0.0  -- Keep tilt neutral
        end
        
        if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Randomise Params Extreme', button_width, 35) then
        -- Use extreme randomization functions (full range)
        randomize_organic_parameters_extreme()
        randomize_core_parameters_extreme()
        randomize_algorithm_parameters_extreme(MACRO.currentAlgorithm)
        
        -- Special L-Systems parameters (extreme range)
        if MACRO.currentAlgorithm == 4 then
            MACRO.l_systems.max_change_rate = math.random() * 9.9 + 0.1  -- 0.1-10.0 (full range)
            MACRO.l_systems.tilt = 0.0  -- Keep tilt at neutral
        end
        
        if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
    
    ImGui.SameLine(ctx)
    -- Eno Mode toggle button - let main styling handle colors when active
    if ImGui.Button(ctx, 'Eno Mode', button_width, 35) then
        MACRO.enoMode = not MACRO.enoMode
    end
    
    ImGui.Separator(ctx)
end

function draw_target_info()
    local env, envName = get_selected_envelope()
    local env_changed = (MACRO.targetEnv ~= env)
    MACRO.targetEnv = env
    
    -- Auto-apply when new envelope is selected
    if env_changed and env and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    local startTime, endTime = get_time_selection()
    if endTime > startTime then
        ImGui.Text(ctx, string.format('Time selection: %.1f sec duration', endTime - startTime))
        MACRO.timeStart, MACRO.timeEnd = startTime, endTime
        
        -- Show recommended duration guidance
        local duration = endTime - startTime
    else
        ImGui.TextColored(ctx, 0xFFFFFF00, 'No time selection')
        MACRO.timeStart, MACRO.timeEnd = 0, 0
    end
end

function draw_parameters()
    ImGui.SeparatorText(ctx, 'Macro Modulation Parameters')
    
    ImGui.Text(ctx, 'Core Settings')
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local slider_width = math.max(200, content_width - 58)
        
        local intensity_changed = draw_locked_slider('Intensity', 'intensity', 0.0, 1.0, '%.3f', slider_width)
        if intensity_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local center_changed = draw_locked_slider('Center', 'center', 0.0, 1.0, '%.3f', slider_width)
        if center_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        ImGui.Separator(ctx)
        
        -- Range and Quality Settings
        ImGui.Text(ctx, 'Range and Quality')
        
        -- Use compact horizontal sliders
        local compact_width = math.max(80, (content_width - 150) / 3)
        
        -- Minimum Value
        ImGui.SetNextItemWidth(ctx, compact_width)
        local min_changed
        min_changed, MACRO.min_value = ImGui.SliderDouble(ctx, 'Min', MACRO.min_value, 0.0, 1.0, '%.3f')
        if min_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        ImGui.SameLine(ctx)
        
        -- Maximum Value
        ImGui.SetNextItemWidth(ctx, compact_width)
        local max_changed
        max_changed, MACRO.max_value = ImGui.SliderDouble(ctx, 'Max', MACRO.max_value, 0.0, 1.0, '%.3f')
        if max_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        ImGui.SameLine(ctx)
        
        -- Smoothness
        ImGui.SetNextItemWidth(ctx, compact_width)
        local smoothness_changed
        smoothness_changed, MACRO.smoothness = ImGui.SliderInt(ctx, 'Smooth', MACRO.smoothness, 60, 500, '%d')
        if smoothness_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
    -- Ensure min <= max
    if MACRO.min_value > MACRO.max_value then
        MACRO.max_value = MACRO.min_value
    end
    
    ImGui.Separator(ctx)
    
    -- XY Pad underneath Range and Quality
    ImGui.Text(ctx, 'Organic Character')
    
    -- XY pad sized to fit within the fixed window
    local available_width = ImGui.GetContentRegionAvail(ctx)
    
    -- Use conservative sizing to ensure it fits
    local pad_width = available_width - 10   -- 5px margin on each side  
    local pad_height = 280                   -- Fixed height that fits comfortably
    
    -- XY Pad for all four organic parameters
    local organic_changed = draw_organic_xy_pad(pad_width, pad_height)
    if organic_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
        apply_macro_modulation()
    end
    
    -- Display current values below the pad
    ImGui.Text(ctx, string.format('C:%.2f  F:%.2f  R:%.2f  P:%.2f', 
               MACRO.complexity or 0, MACRO.flow or 0, MACRO.randomness or 0, MACRO.peak_irregularity or 0))
end

function draw_algorithm_parameters()
    ImGui.SeparatorText(ctx, 'Algorithm Parameters')
    
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local slider_width = math.max(200, content_width - 112)
    
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
        if octaves_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local persistence_changed = draw_locked_slider('Persistence', 'algo_param2', 0.0, 1.0, '%.2f', slider_width)
        MACRO.fractal.persistence = MACRO.algo_param2
        if persistence_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local freq_changed = draw_locked_slider('Frequency Scale', 'algo_param3', 1.0, 20.0, '%.1f', slider_width)
        MACRO.fractal.frequency_scale = MACRO.algo_param3
        if freq_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local lacunarity_changed = draw_locked_slider('Lacunarity', 'algo_param4', 0.01, 1.0, '%.2f', slider_width)
        MACRO.fractal.lacunarity = MACRO.algo_param4
        if lacunarity_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local bias_changed = draw_locked_slider('Amplitude Bias', 'algo_param5', 0.01, 2.5, '%.2f', slider_width)
        MACRO.fractal.amplitude_bias = MACRO.algo_param5
        if bias_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        
    elseif MACRO.currentAlgorithm == 2 then -- Sine Wave Interference
        ImGui.Text(ctx, 'Sine Wave Interference Settings')
        
        -- Initialize sliders with current values for this algorithm
        if not MACRO.algo_param1 then MACRO.algo_param1 = MACRO.sine_wave.wave_count end
        if not MACRO.algo_param2 then MACRO.algo_param2 = MACRO.sine_wave.frequency_spread end
        if not MACRO.algo_param3 then MACRO.algo_param3 = MACRO.sine_wave.amplitude_variation end
        if not MACRO.algo_param4 then MACRO.algo_param4 = MACRO.sine_wave.phase_drift end
        if not MACRO.algo_param5 then MACRO.algo_param5 = MACRO.sine_wave.beat_frequency end
        
        local count_changed = draw_locked_slider('Wave Count', 'algo_param1', 1.0, 30.0, '%.0f', slider_width)
        MACRO.sine_wave.wave_count = math.floor(MACRO.algo_param1)
        if count_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local spread_changed = draw_locked_slider('Frequency Spread', 'algo_param2', 0.5, 10.0, '%.1f', slider_width)
        MACRO.sine_wave.frequency_spread = MACRO.algo_param2
        if spread_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local amplitude_changed = draw_locked_slider('Amplitude Variation', 'algo_param3', 0.1, 2.0, '%.2f', slider_width)
        MACRO.sine_wave.amplitude_variation = MACRO.algo_param3
        if amplitude_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local phase_changed = draw_locked_slider('Phase Drift', 'algo_param4', 0.1, 30.0, '%.1f', slider_width)
        MACRO.sine_wave.phase_drift = MACRO.algo_param4
        if phase_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local beat_changed = draw_locked_slider('Beat Frequency', 'algo_param5', 0.1, 10.0, '%.1f', slider_width)
        MACRO.sine_wave.beat_frequency = MACRO.algo_param5
        if beat_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
    elseif MACRO.currentAlgorithm == 3 then -- Generative Walk
        ImGui.Text(ctx, 'Generative Walk Settings')
        
        -- Initialize sliders with current values for this algorithm
        if not MACRO.algo_param1 then MACRO.algo_param1 = MACRO.generative.segment_length end
        if not MACRO.algo_param2 then MACRO.algo_param2 = MACRO.generative.smoothing_factor end
        if not MACRO.algo_param3 then MACRO.algo_param3 = MACRO.generative.variation_scale end
        if not MACRO.algo_param4 then MACRO.algo_param4 = MACRO.generative.momentum end
        if not MACRO.algo_param5 then MACRO.algo_param5 = MACRO.generative.levy_probability end
        
        -- Add Markov bias as a separate control (not using algo_param slot due to 5-param limit)
        local markov_changed = draw_locked_slider('Markov Bias', 'markov_bias', -1.0, 1.0, '%.3f', slider_width)
        if not MACRO.markov_bias then MACRO.markov_bias = MACRO.generative.markov_bias end
        MACRO.generative.markov_bias = MACRO.markov_bias
        if markov_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local segment_changed = draw_locked_slider('Segment Length', 'algo_param1', 0.01, 0.3, '%.3f', slider_width)
        MACRO.generative.segment_length = MACRO.algo_param1
        if segment_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local smooth_changed = draw_locked_slider('Smoothing Factor', 'algo_param2', 0.01, 50.0, '%.2f', slider_width)
        MACRO.generative.smoothing_factor = MACRO.algo_param2
        if smooth_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local variation_changed = draw_locked_slider('Variation Scale', 'algo_param3', 0.01, 0.05, '%.3f', slider_width)
        MACRO.generative.variation_scale = MACRO.algo_param3
        if variation_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local momentum_changed = draw_locked_slider('Momentum', 'algo_param4', 0.001, 0.1, '%.3f', slider_width)
        MACRO.generative.momentum = MACRO.algo_param4
        if momentum_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local levy_changed = draw_locked_slider('Levy Flight', 'algo_param5', 0.0, 0.1, '%.3f', slider_width)
        MACRO.generative.levy_probability = MACRO.algo_param5
        if levy_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
    elseif MACRO.currentAlgorithm == 4 then -- L-Systems
        ImGui.Text(ctx, 'L-Systems Settings')
        
        -- Initialize sliders with current values for this algorithm
        if not MACRO.algo_param1 then MACRO.algo_param1 = MACRO.l_systems.iterations end
        if not MACRO.algo_param2 then MACRO.algo_param2 = MACRO.l_systems.branch_angle end
        if not MACRO.algo_param3 then MACRO.algo_param3 = MACRO.l_systems.length_scale end
        if not MACRO.algo_param4 then MACRO.algo_param4 = MACRO.l_systems.growth_rate end
        if not MACRO.algo_param5 then MACRO.algo_param5 = MACRO.l_systems.complexity_factor end
        
        local iterations_changed = draw_locked_slider('Iterations', 'algo_param1', 1, 6, '%.0f', slider_width)
        MACRO.l_systems.iterations = math.floor(MACRO.algo_param1)
        if iterations_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local angle_changed = draw_locked_slider('Branch Angle', 'algo_param2', 10.0, 90.0, '%.1f', slider_width)
        MACRO.l_systems.branch_angle = MACRO.algo_param2
        if angle_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local scale_changed = draw_locked_slider('Length Scale', 'algo_param3', 0.3, 0.95, '%.2f', slider_width)
        MACRO.l_systems.length_scale = MACRO.algo_param3
        if scale_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local growth_changed = draw_locked_slider('Growth Rate', 'algo_param4', 0.01, 4.0, '%.2f', slider_width)
        MACRO.l_systems.growth_rate = MACRO.algo_param4
        if growth_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
        
        local complexity_changed = draw_locked_slider('Complexity Factor', 'algo_param5', 0.2, 1.0, '%.2f', slider_width)
        MACRO.l_systems.complexity_factor = MACRO.algo_param5
        if complexity_changed and MACRO.autoApply and MACRO.targetEnv and MACRO.timeStart then
            apply_macro_modulation()
        end
        
        -- Initialize slider with current L-systems value
        if not MACRO.max_change_rate then MACRO.max_change_rate = MACRO.l_systems.max_change_rate end
        
        local max_change_changed = draw_locked_slider('Max Change Rate', 'max_change_rate', 0.1, 10.0, '%.1f', slider_width)
        MACRO.l_systems.max_change_rate = MACRO.max_change_rate
        if max_change_changed and MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
            apply_macro_modulation()
        end
    end
end

function draw_algorithm_selector()
    ImGui.SeparatorText(ctx, 'Modulation Algorithm')
    
    local content_width = ImGui.GetContentRegionAvail(ctx)
    local button_width = math.max(150, (content_width - 30) / 4) -- 4 buttons with spacing
    
    -- Draw algorithm buttons in a single row
    for i, algorithmName in ipairs(algorithms) do
        local is_selected = (MACRO.currentAlgorithm == i)
        
        -- Style selected button differently - use Eno Mode colors only when active
        if is_selected then
            if MACRO.enoMode then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xD35900FF)        -- Orange for selected
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xF8D399FF) -- Light golden for hover
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xD35900FF)  -- Orange for active
            else
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0078D4FF)        -- Blue for selected
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x106EBAFF) -- Darker blue for hover
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x005A9EFF)  -- Even darker blue for active
            end
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
            if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
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
        "Complex beating patterns from interfering sine waves",
        "Rule-based but unpredictable segment-based movement",
        "Recursive string rewriting with organic growth patterns"
    }
    
    ImGui.TextColored(ctx, 0xAAAAAAAA, descriptions[MACRO.currentAlgorithm])
    
    -- Algorithm-specific sub-options (only show when relevant algorithm is selected)
    if MACRO.currentAlgorithm == 1 then
        -- Fractal Type buttons for Fractal Curves
        ImGui.Text(ctx, "Type:")
        ImGui.SameLine(ctx)
        
        local fractal_types = {'fBm', 'Ridged', 'Turbulence'}
        local sub_button_width = math.max(80, (content_width - 60) / 3)
        
        for i = 1, 3 do
            local is_selected = (MACRO.fractal.type == i)
            
            if is_selected then
                if MACRO.enoMode then
                    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xD35900FF)
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xF8D399FF)
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xD35900FF)
                else
                    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0078D4FF)        -- Blue for selected
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x106EBAFF) -- Darker blue for hover
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x005A9EFF)  -- Even darker blue for active
                end
            end
            
            if ImGui.Button(ctx, fractal_types[i], sub_button_width, 25) then
                MACRO.fractal.type = i
                if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
                    apply_macro_modulation()
                end
            end
            
            if is_selected then
                ImGui.PopStyleColor(ctx, 3)
            end
            
            if i < 3 then
                ImGui.SameLine(ctx)
            end
        end
        
    elseif MACRO.currentAlgorithm == 4 then
        -- L-Systems Mapping buttons for L-Systems (only Y-values and Symmetry Axis)
        ImGui.Text(ctx, "Mapping:")
        ImGui.SameLine(ctx)
        
        local mapping_types = {'Y-values', 'Symmetry Axis'}
        local mapping_indices = {1, 4}  -- Map to original indices (1=Y-values, 4=Symmetry Axis)
        
        -- Calculate remaining width after "Mapping:" text and apply adaptive sizing
        local remaining_width = ImGui.GetContentRegionAvail(ctx)
        local sub_button_width = math.max(100, (remaining_width - 10) / 2) -- 2 buttons with minimal spacing
        
        for i = 1, 2 do
            local mapping_index = mapping_indices[i]
            local is_selected = (MACRO.l_systems.mapping_mode == mapping_index)
            
            if is_selected then
                if MACRO.enoMode then
                    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xD35900FF)
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xF8D399FF)
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xD35900FF)
                else
                    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0078D4FF)        -- Blue for selected
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x106EBAFF) -- Darker blue for hover
                    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x005A9EFF)  -- Even darker blue for active
                end
            end
            
            if ImGui.Button(ctx, mapping_types[i], sub_button_width, 25) then
                MACRO.l_systems.mapping_mode = mapping_index
                if MACRO.targetEnv and MACRO.timeEnd > MACRO.timeStart then
                    apply_macro_modulation()
                end
            end
            
            if is_selected then
                ImGui.PopStyleColor(ctx, 3)
            end
            
            if i < 2 then
                ImGui.SameLine(ctx)
            end
        end
    end
end

-- Main GUI loop
function main_loop()
    ImGui.SetNextWindowSize(ctx, 780, 950)
    ImGui.SetNextWindowSizeConstraints(ctx, 780, 950, 780, 950) -- Fixed size, no resizing
    
    -- Eno Mode custom styling - only applied when toggled on
    local style_colors_pushed = 0
    if MACRO.enoMode then
        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0xFCEACEFF)        -- Window background (opaque)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x000000FF)            -- All text
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xC79445FF)          -- Button idle
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xF8D399FF)   -- Button hover
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xD35900FF)    -- Button selected/active
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x2D8A3AFF)         -- Darker green slider backgrounds
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x2D8A3AFF)  -- Darker green slider backgrounds (hovered)
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x2D8A3AFF)   -- Darker green slider backgrounds (active)
        ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, 0x0066CCFF)      -- Blue slider handles (opaque)
        ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, 0x0066CCFF) -- Blue slider handles (active)
        style_colors_pushed = 10
    end
    
    local visible, open = ImGui.Begin(ctx, 'joshadambell - Ambient 1 - Envelopes for Airports', true, ImGui.WindowFlags_MenuBar)
    
    if visible then
        -- Make text larger and more prominent
        --ImGui.PushFont(ctx, nil, 16.0)  -- Use 16pt font size (larger than default)
        
        draw_menu_bar()
        draw_controls_bar()
        draw_target_info()
        draw_algorithm_selector()
        draw_algorithm_parameters()
        draw_parameters()
        
       -- ImGui.PopFont(ctx)  -- Pop the custom font size
    end
    
    ImGui.End(ctx)
    
    -- Pop custom styling only if we pushed colors
    if style_colors_pushed > 0 then
        ImGui.PopStyleColor(ctx, style_colors_pushed)
    end
    
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
    
    -- Window size is now set in main_loop
    main_loop()
end

-- Start the script
init()