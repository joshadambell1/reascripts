# 🎧 Media Explorer Spotting Scripts

Replaces Soundminer's "Spot through DSP Rack" functionality. Preview audio through FX and spot processed files onto your timeline.

Takes the last played file from Media Explorer, processes it through FX on a preview track, then places the final item on your selected track at the cursor.

**Author:** [joshadambell.com](https://joshadambell.com)

## 📜 Two Versions Available

⚡ **"Only Bakes Time Selection"** - Trims to Media Explorer selection first, then processes (more efficient, bakes only the time selection from Media Explorer)

🎛️ **"Bakes Whole File"** - Processes entire file through FX, then trims to selection (bakes full file for more flexibility later)

## 📦 Setup

1. Create track named "Media Explorer Preview" 
2. Add FX to that track
3. In Media Explorer Options, set playback to "Play through first track named 'Media Explorer Preview' or first selected track"
4. Install scripts: Actions → Show Action List → Load → select .lua files

## 🚀 Usage

1. Preview files in Media Explorer (plays through FX track)
2. Move cursor to where you want the sound
3. Select destination track 
4. Run script
5. Processed audio appears on selected track

## ✨ What it does

- Bakes FX from preview track into final audio
- Respects Media Explorer time selections  
- Keeps Media Explorer rate/pitch/volume settings
- Resets playback params after baking
- Undoable

## 🔧 Issues

- "Please select a track first" = select a track first
- "No file selected in Media Explorer" = preview a file first  
- No FX processing = add FX to preview track