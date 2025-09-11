# Envelope Scripts

LFO generation tools for REAPER automation envelopes.

## 🌊 LFO Tool

### joshadambell_Envelope LFO Tool.lua

**Requirements:** "ReaImGui: ReaScript binding for Dear ImGui extension" from the repository: https://github.com/ReaTeam/Extensions/raw/master/index.xml

LFO Generator for Reaper Envelopes with ReaImGui interface. Very very heavily inspired by the classic juliansader LFO Tool.

**Features:**
- **Envelope Editors** - Color-coded parameter envelopes with visual feedback
- **Power Curve Sliders** - Better control in lower ranges for Rate (0.01-50Hz) and Amplitude (0.0-2.0)
- **6 LFO Shapes** - Bézier, Saw Down/Up, Square, Triangle, Sine-ish
- **Envelope Editing** - Shift+drag to draw/erase multiple points, hover tooltips
- **Auto-apply Mode** - Optional real-time updates
- **Parameter Randomization** - Add variation to Rate, Amplitude, and Center
- **ReaImGui Interface** - Color-coded parameters and help page

**Envelope Multipliers (0.0-2.0 range):**
- **Rate Multiplier** (Red) - Modulates LFO frequency over time
- **Amplitude Multiplier** (Green) - Controls LFO intensity over time  
- **Center Multiplier** (Blue) - Shifts oscillation center point over time

**Setup:**
1. Install ReaImGui extension via ReaPack
2. Install joshadambell_Envelope LFO Tool via ReaPack
3. Load script: Actions → Show Action List → Load → select .lua file

**Usage:**
1. Select an automation envelope in REAPER
2. Set time selection (where LFO will be applied)
3. Adjust Rate, Amplitude, Center, and other parameters
4. Draw envelope shapes using the editors
5. Choose LFO shape and apply to an envelope lane in Reaper

**Mouse Controls:**
- Left-click: Add/drag envelope points
- Shift+left-drag: Draw multiple points quickly
- Right-click: Delete single point
- Shift+right-drag: Delete multiple points
- Hover: View time/value tooltips

## 🌟 Ambient1 - Envelopes for Airports

### joshadambell_Ambient1 - Envelopes for Airports.lua

**Requirements:** "ReaImGui: ReaScript binding for Dear ImGui extension" from the repository: https://github.com/ReaTeam/Extensions/raw/master/index.xml

Brian Eno-inspired organic envelope modulation generator with 4 sophisticated algorithms and professional parameter control. Perfect for creating long-form ambient textures and evolving parameter automation.

**Features:**
- **4 Advanced Algorithms** - Fractal Curves, Sine Wave Interference, Generative Walk, L-Systems
- **15 Algorithm Parameters** - 5 unique parameters per algorithm for maximum expressiveness
- **XY Pad Control** - Intuitive corner-based mapping for Organic Character parameters
- **Parameter Locking System** - Right-click any parameter to exclude from randomization
- **Professional Integration** - REAPER envelope insertion with undo support
- **Seeded Generation** - Reproducible patterns with manual seed control

**Core Parameters:**
- **Intensity** (0.0-1.0) - Overall modulation amplitude
- **Center** (0.0-1.0) - Base value around which modulation occurs
- **Organic Character XY Pad** - Corner-based control for Complexity, Flow, Randomness, Peak Irregularity

**4 Algorithm Options:**

**1. Fractal Curves** - Self-similar recursive noise patterns
- Octaves, Persistence, Frequency Scale, Lacunarity, Amplitude Bias

**2. Sine Wave Interference** - Multiple sine waves with controlled chaos
- Wave Count, Frequency Spread, Amplitude Variation, Phase Drift, Beat Frequency

**3. Generative Walk** - Rule-based segment movement with momentum
- Segment Length, Smoothing Factor, Variation Scale, Momentum, Bias Direction

**4. L-Systems** - Recursive string rewriting with organic growth patterns
- Iterations, Branch Angle, Length Scale, Growth Rate, Complexity Factor, Max Change Rate, Tilt

**XY Pad Corner Mapping:**
- **Top-left**: Complexity + Flow (organic detail with smooth transitions)
- **Top-right**: Randomness + Flow (chaotic with smooth blending)
- **Bottom-left**: Complexity + Peak Irregularity (detailed with sharp events)
- **Bottom-right**: Randomness + Peak Irregularity (chaotic with peak events)

**Setup:**
1. Install ReaImGui extension via ReaPack
2. Install script via ReaPack or manual installation
3. Load script: Actions → Show Action List → Load → select .lua file

**Usage:**
1. Select automation envelope in REAPER
2. Set time selection (recommended: 15-60+ seconds for ambient evolution)
3. Choose algorithm and adjust algorithm-specific parameters
4. Use XY pad to control organic character blend
5. Adjust core parameters (Intensity, Center)
6. Script automatically applies modulation with permanent auto-apply

**Parameter Management:**
- **Randomise Seed** - Generate new random seed
- **Randomise Parameters** - Randomize unlocked parameters only
- **Randomise All** - Randomize both seed and unlocked parameters
- **Reset** - Return all unlocked parameters to defaults
- **Parameter Locking** - Right-click any slider to lock/unlock (orange = locked)

## 💬 Support

For issues or feature requests: [joshadambell.com](https://joshadambell.com)

<img width="3295" height="1135" alt="Screenshot 2025-09-10 121350" src="https://github.com/user-attachments/assets/67a14229-5f35-4a71-a101-c22344cc1c7f" />
