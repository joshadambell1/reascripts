# 📝 Reaper Item & Track Renamer

Batch rename items and tracks with live preview. GUI-based tool with find/replace, prefix/suffix, character removal, and auto-numbering.

**Author:** [joshadambell.com](https://joshadambell.com)

## 🛠️ Requirements

- "ReaImGui: ReaScript binding for Dear ImGui extension" from the repository: https://github.com/ReaTeam/Extensions/raw/master/index.xml)

## 📦 Setup

1. Install ReaImGui via ReaPack
2. Install script: Actions → Show Action List → Load → select .lua file
3. Assign keyboard shortcut if desired

## 🚀 Usage  

1. Select items/tracks in Reaper
2. Run script to open GUI
3. Check "Enable Item Renaming" or "Enable Track Renaming" (or both)
4. Use any combination of tools:
   - Find & Replace for text changes
   - Prefix/Suffix for adding text to start/end  
   - Character removal for trimming
   - Numbering for sequential numbers
5. Watch live preview update
6. Click action buttons to apply

## 🔧 Tools

**Find & Replace**
- Replace all/first/last instances
- Case sensitive option

**Prefix & Suffix** 
- Add text to beginning or end of names

**Character Removal**
- Remove X characters from start or end

**Numbering**
- Add sequential numbers with separator (space/underscore/hyphen)
- Zero padding options (none/01/001/0001)
- Custom starting number
- Items and tracks numbered separately

## 💡 Example

Original: `Guitar.wav`, `Bass.wav`
- Add prefix "SONG_"
- Remove ".wav" 
- Add numbering with underscore, 2-digit padding

Result: `SONG_Guitar_01`, `SONG_Bass_02`

## ⚙️ Options

- Auto-refresh when selection changes
- Live preview shows before/after names
- All operations are undoable
