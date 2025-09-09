# 🎵 JBSFX Reaper Scripts

Game Audio and Audio Post tools for Reaper.

## 📜 Scripts

### 📝 Item & Track Renamer
`Renaming/JBSFX - Reaper Track and Item Renamer.lua`

Batch rename items and tracks with a GUI. Supports find/replace, prefixes, suffixes, character removal, and auto-numbering with live preview.

- 🔍 Find & replace text (all, first, or last instance)
- 🏷️ Add prefixes and suffixes  
- ✂️ Remove characters from start or end
- 🔢 Add sequential numbers with separators and zero-padding
- 👁️ Live preview and auto-refresh on selection change

Example: `Guitar.wav` → `SONG_Guitar_01`

Requires ReaImGui extension.

### 🎧 Media Explorer Spotting Scripts  
`Spotting/` folder

Replaces Soundminer's "Spot through DSP Rack" functionality. Preview audio files through FX and place processed versions onto your timeline.

**Two versions available:**

⚡ **"Only Bakes Time Selection"** - Trims to Media Explorer selection first, then processes. More efficient for short clips.

🎛️ **"Bakes Whole File"** - Processes entire file through FX, then trims to selection. Better when FX need full audio context (reverb, compression, etc).

Usage:
1. 🎵 Preview files in Media Explorer (plays through FX track)
2. 📍 Position cursor at desired location
3. 🎯 Select destination track
4. ▶️ Run script

Setup:
- 🎚️ Create track named "Media Explorer Preview"
- 🔧 Add FX to preview track
- ⚙️ Configure Media Explorer to play through preview track

## 📦 Installation

**ReaPack:** Add repository URL and install scripts.

**Manual:** Download .lua files and load via Actions → Show Action List → Load.

## 🛠️ Requirements

- 📝 Renamer: ReaImGui extension (available via ReaPack)
- 🎧 Spotting: Standard Reaper installation

## 💬 Support

For issues or feature requests: [joshadambell.com](https://joshadambell.com)
