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

## 💬 Support

For issues or feature requests: [joshadambell.com](https://joshadambell.com)
