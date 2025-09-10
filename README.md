# joshadambell - reascripts

Game Audio and Audio Post tools for Reaper.

This ReaPack repository contains scripts for audio post-production workflows, including batch renaming tools, Media Explorer spotting functionality, and LFO generation tools.

**Author:** [joshadambell.com](https://joshadambell.com)

## 📦 Installation

- Extensions → ReaPack → Import Repositories
- Paste this: https://raw.githubusercontent.com/joshadambell1/reascripts/refs/heads/main/index.xml
- Browse Repositories → Search "joshadambell" → Right Click → Install
- Actions → Show Action List
- Search "joshadambell"
- Run

## 🛠️ Requirements

- For the Renamer and LFO Tool: **"ReaImGui: ReaScript binding for Dear ImGui extension"** from the repository: **https://github.com/ReaTeam/Extensions/raw/master/index.xml**

## 📜 Scripts

### 📝 Item & Track Renamer
`Renaming/joshadambell_Reaper Track and Item Renamer.lua`

Batch rename items and tracks with a GUI. Supports find/replace, prefixes, suffixes, character removal, and auto-numbering with live preview.

**Features:**
- **Find & Replace** - Replace all/first/last instances with case sensitivity
- **Prefix & Suffix** - Add text to beginning or end of names
- **Character Removal** - Remove X characters from start or end
- **Numbering** - Sequential numbers with separators (space/underscore/hyphen), zero-padding options, custom starting numbers
- **Live Preview** - See changes before applying with auto-refresh on selection change

**Usage:**
1. Select items/tracks in Reaper
2. Run script to open GUI
3. Enable "Item Renaming" or "Track Renaming" (or both)
4. Use any combination of tools and watch live preview
5. Click action buttons to apply changes

**Requires:** ReaImGui extension (install via ReaPack)

### 🎧 Media Explorer Spotting Scripts  
`Spotting/` folder

Replaces Soundminer's "Spot through DSP Rack" functionality. Preview audio files through FX and place processed versions onto your timeline.

Takes the last played file from Media Explorer, processes it through FX on a preview track, then places the final item on your selected track at the cursor.

**Two versions available:**

⚡ **"Only Bakes Time Selection"** (`joshadambell_Spot...only bakes time selection.lua`)
- Trims to Media Explorer selection first, then processes
- More efficient for short clips
- Bakes only the time selection from Media Explorer

🎛️ **"Bakes Whole File"** (`joshadambell_Spot...bakes whole file.lua`)
- Processes entire file through FX first, then trims to selection
- Better when FX need full audio context (reverb, compression, etc)
- Bakes full file for more flexibility later

**Setup:**
1. Create track named "Media Explorer Preview"
2. Add FX to that track  
3. In Media Explorer Options, set playback to "Play through first track named 'Media Explorer Preview' or first selected track"
4. Install scripts: Actions → Show Action List → Load → select .lua files

**Usage:**
1. Preview files in Media Explorer (plays through FX track)
2. Move cursor to where you want the sound
3. Select destination track
4. Run script
5. Processed audio appears on selected track

**What it does:**
- Bakes FX from preview track into final audio
- Respects Media Explorer time selections
- Keeps Media Explorer rate/pitch/volume settings
- Resets playback params after baking
- Fully undoable

### 🌊 Envelope LFO Tool
`Envelope/joshadambell_Envelope LFO Tool.lua`

LFO Generator for Reaper Envelopes with modern ReaImGui interface. Very very heavily inspired by the classic juliansader LFO Tool.

**Features:**
- **Interactive Envelope Editors** - Color-coded parameter envelopes
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

**Requires:** ReaImGui extension (install via ReaPack)

## 💬 Support

For issues or feature requests: [joshadambell.com](https://joshadambell.com)
