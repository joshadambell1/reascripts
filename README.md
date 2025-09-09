# JBSFX Reaper Scripts

Professional audio post-production tools for Reaper. Built for efficiency and workflow optimization.

## 🎯 Scripts Overview

### 📝 Item & Track Renamer
**Location:** `Renaming/JBSFX - Reaper Track and Item Renamer.lua`

Batch rename items and tracks with live preview. GUI-based tool with multiple renaming methods.

**Key Features:**
- 🔍 **Find & Replace** - All/first/last instances with case sensitivity
- 🏷️ **Prefix & Suffix** - Quick text addition to start/end 
- ✂️ **Character Removal** - Trim X characters from start or end
- 🔢 **Auto Numbering** - Sequential numbers with custom separators and zero-padding
- 👁️ **Live Preview** - See changes before applying
- ⚡ **Auto-refresh** - Updates when selection changes

**Example:** `Guitar.wav` → `SONG_Guitar_01`

**Requirements:** ReaImGui extension

---

### 🎵 Media Explorer Spotting Scripts  
**Location:** `Spotting/`

Replace Soundminer's "Spot through DSP Rack" functionality. Preview audio through FX and spot processed files directly onto your timeline.

#### Version 1: "Only Bakes Time Selection"
**File:** `JBSFX - Spot...Item (only bakes time selection).lua`

**Best for:** Efficiency when you only need the selected portion
- Trims Media Explorer selection first
- Processes only selected audio through FX
- Faster processing for short selections

#### Version 2: "Bakes Whole File"  
**File:** `JBSFX - Spot...Item (bakes whole file).lua`

**Best for:** When FX need full audio context
- Processes entire file through FX first
- Trims to selection afterward  
- Preserves reverb tails, dynamics processing context

**How it Works:**
1. 🎧 Preview files in Media Explorer (plays through FX)
2. 📍 Position cursor where you want the sound
3. 🎯 Select destination track
4. ▶️ Run script
5. ✨ Processed audio appears on selected track

**Setup Required:**
- Create track named "Media Explorer Preview"
- Add desired FX to preview track
- Configure Media Explorer playback routing

---

## 📦 Installation

### Via ReaPack (Recommended)
1. Add repository URL to ReaPack
2. Install desired scripts
3. Assign keyboard shortcuts for faster workflow

### Manual Installation
1. Download `.lua` files
2. Load via Actions → Show Action List → Load
3. Assign shortcuts as needed

## 🛠️ Requirements

- **Renamer:** ReaImGui extension (install via ReaPack)
- **Spotting:** Standard Reaper installation

## 📞 Support

For issues, feature requests, or questions:
**Contact:** [joshadambell.com](https://joshadambell.com)

---

*These scripts are designed to streamline professional audio post-production workflows in Reaper.*
