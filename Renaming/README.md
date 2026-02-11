# 📝 Renaming Tools

**Author:** [joshadambell.com](https://joshadambell.com)

## 🛠️ Dependencies

- **"ReaImGui: ReaScript binding for Dear ImGui extension"** from the repository: https://github.com/ReaTeam/Extensions/raw/master/index.xml

## 📦 Setup

1. Install ReaImGui via ReaPack
2. Install script: Actions → Show Action List → Load → select .lua file
3. Assign keyboard shortcut if desired

---

## Reaper Item & Track Renamer

Batch rename items and tracks with live preview. GUI-based tool with find/replace, prefix/suffix, character removal, and auto-numbering.

<img width="934" height="675" alt="image" src="https://github.com/user-attachments/assets/9ec3615b-dfff-474b-80d5-5a64d734ff24" />

### 🚀 Usage

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

### 🔧 Tools

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

### 💡 Example

Original: `Guitar.wav`, `Bass.wav`
- Add prefix "SONG_"
- Remove ".wav"
- Add numbering with underscore, 2-digit padding

Result: `SONG_Guitar_01`, `SONG_Bass_02`

### ⚙️ Options

- Auto-refresh when selection changes
- Live preview shows before/after names
- All operations are undoable

---

## Media File Find & Replace

Batch rename media files on disk in your project's media folder. Renames files, updates all item source references and take names in the open project.

<img width="1224" height="873" alt="image" src="https://github.com/user-attachments/assets/c55da9cd-57e4-40f9-8323-3ab3d36d650a" />

### 🚀 Usage

1. Open your REAPER project
2. Run script — media folder is auto-detected
3. Choose a rename mode and enter parameters
4. Preview changes in the table below
5. Click "Apply Rename" to rename files and update project references
6. Save your project to persist changes

### 🔧 Modes

**Find & Replace**
- Replace text in filename stems (extensions preserved)
- Case sensitive option

**Prepend / Append**
- Add text to beginning or end of filenames

**Trim Start / Trim End**
- Remove X characters from start or end of filenames

### 📁 Media Management

**Delete Unreferenced Media**
- Scans for media files with zero project references
- Confirmation dialog listing files before deletion
- Also removes associated .reapeaks files

### ⚙️ Options

- Auto-detects media folder location
- Click highlighted rows to exclude files from renaming
- Live preview shows before/after names with ref counts
- Update item names to match renamed media (on by default, optional)
- All rename operations are undoable
