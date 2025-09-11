# Envelope Toolkit

LFO generation tools for REAPER automation envelopes.

![Envelope LFO Tool](https://github.com/user-attachments/assets/052ee15e-06b7-4017-950c-44fe6545937a)

![Ambient 1](https://github.com/user-attachments/assets/818eb061-c775-4f80-864f-5bfe271f5c38)

## 🛠️ Dependencies

- **"ReaImGui: ReaScript binding for Dear ImGui extension"** from the repository: https://github.com/ReaTeam/Extensions/raw/master/index.xml
- **SWS Extensions** - Download from https://www.sws-extension.org/

## 🌊 LFO Tool

### joshadambell_Envelope LFO Tool.lua

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

<img width="3295" height="1135" alt="Screenshot 2025-09-10 121350" src="https://github.com/user-attachments/assets/67a14229-5f35-4a71-a101-c22344cc1c7f" />

## 🌟 Ambient1 - Envelopes for Airports

### joshadambell_Ambient1 - Envelopes for Airports.lua

**A comprehensive toolbox for fast and interesting modulation on a macro scale to provide inspiration.** This organic envelope modulation generator features 4 sophisticated algorithms with professional parameter control, perfect for creating evolving parameter automation and long-form ambient textures.

**Key Features:**
- **4 Advanced Algorithms** - Fractal Curves, Sine Wave Interference, Generative Walk, L-Systems
- **22+ Lockable Parameters** - Comprehensive parameter control with individual locking
- **XY Pad Control** - Intuitive corner-based mapping for 4 organic character parameters
- **Dual Randomization System** - Mild (±20% around center) and Extreme (full range) randomization
- **Professional Integration** - REAPER envelope insertion with undo support and auto-apply
- **Seeded Generation** - Reproducible patterns with manual seed control
- **Eno Mode** - Optional retro color scheme as Easter egg

**Core Parameters:**
- **Intensity** (0.0-1.0) - Overall modulation amplitude
- **Center** (0.0-1.0) - Base value around which modulation occurs
- **Min/Max Values** (0.0-1.0) - Output range clamping
- **Smoothness** (60-500 pts/min) - Curve point density

**Organic Character XY Pad:**
Interactive 280×280px pad with corner-based parameter mapping:
- **Top-left**: Complexity + Flow (detailed with smooth transitions)
- **Top-right**: Flow + Randomness (smooth chaotic blending)
- **Bottom-left**: Complexity + Peak Irregularity (detailed with sharp events)
- **Bottom-right**: Randomness + Peak Irregularity (chaotic with peak events)

**4 Algorithm Options:**

**1. Fractal Curves** - Self-similar recursive noise patterns (6 parameters)
- Type (fBm/Ridged/Turbulence), Octaves, Persistence, Frequency Scale, Lacunarity, Amplitude Bias

**2. Sine Wave Interference** - Multiple sine waves with controlled beating patterns (5 parameters)
- Wave Count, Frequency Spread, Amplitude Variation, Phase Drift, Beat Frequency

**3. Generative Walk** - Rule-based segment movement with momentum physics (6 parameters)
- Segment Length, Smoothing Factor, Variation Scale, Momentum, Lévy Probability, Markov Bias

**4. L-Systems** - Recursive string rewriting with organic growth patterns (7 parameters)
- Iterations, Branch Angle, Length Scale, Growth Rate, Complexity Factor, Max Change Rate, Mapping Mode

**Control Bar Functions:**
- **Reset** - Return unlocked parameters to defaults
- **Randomise Seed** - Generate new random seed for pattern variation
- **Randomise Params Mild** - Randomize parameters ±20% around their middle values (subtle variations)
- **Randomise Params Extreme** - Randomize parameters across full slider ranges (dramatic changes)  
- **Randomise All** - Randomize seed + all unlocked parameters (extreme mode)
- **Eno Mode** - Toggle retro amber/brown/green color scheme

**Advanced Features:**
- **Parameter Locking** - Right-click any slider to lock/unlock (orange background = locked)
- **Algorithm-Specific Controls** - Each algorithm shows only relevant parameters  
- **Real-time Preview** - Parameters update instantly with visual feedback
- **Professional Layout** - Fixed 780×950px window optimized for workflow efficiency

**Setup:**
1. Install ReaImGui extension via ReaPack
2. Install script via ReaPack or manual installation  
3. Load script: Actions → Show Action List → Load → select .lua file

**Usage Workflow:**
1. Select automation envelope in REAPER
2. Set time selection (recommended: 15-60+ seconds for macro-scale evolution)
3. Choose algorithm and adjust algorithm-specific parameters
4. Use XY pad for intuitive organic character control
5. Apply mild or extreme randomization for inspiration
6. Fine-tune with core parameters (Intensity, Center, Range)
7. Script auto-applies modulation with undo support

## 💬 Support

For issues or feature requests: [joshadambell.com](https://joshadambell.com)
