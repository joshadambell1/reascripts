# joshadambell - reascripts

Game Audio and Audio Post tools for Reaper.

This ReaPack repository contains scripts for audio post-production workflows, including batch renaming tools and Media Explorer spotting functionality.

**Author:** [joshadambell.com](https://joshadambell.com)

## 📦 Installation

- Extensions → ReaPack → Import Repositories
- Paste this: https://raw.githubusercontent.com/joshadambell1/reascripts/refs/heads/main/index.xml
- Browse Repositories → Search "joshadambell" → Right Click → Install
- Actions → Show Action List
- Search "joshadambell"
- Run

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

## 🛠️ Requirements

- Renamer: ReaImGui extension (available via ReaPack)

## 💬 Support

For issues or feature requests: [joshadambell.com](https://joshadambell.com)
