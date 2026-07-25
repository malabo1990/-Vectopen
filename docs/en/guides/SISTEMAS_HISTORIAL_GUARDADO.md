# History, Save and Recent Files Systems

> **Version:** Implemented July 2026 | **New Autoloads:** 3 | **Shortcuts:** Ctrl+Z, Ctrl+Shift+Z, Ctrl+S

---

## 1. General Architecture

Three new autoloads were added that work together:

```
┌─────────────────────────────────────────────────────────┐
│                    AUTOLOADS (3 nuevos)                   │
│                                                          │
│  HistoryManager     SaveManager     RecentFilesManager   │
│  (undo/redo)        (save/load)     (recent files)       │
└───────┬──────────────────┬───────────────────┬───────────┘
        │                  │                   │
        ▼                  ▼                   ▼
┌──────────────┐  ┌──────────────┐  ┌────────────────────┐
│UndoRedoManager│  │DataRepository│  │user://recent_assets│
│(CommandPattern)│  │ (save/load)  │  │    .cfg (Config)  │
└──────────────┘  └──────────────┘  └────────────────────┘
```

### Dependencies between systems

| System | Depends on | Provides |
|---------|-----------|-------------|
| `HistoryManager` | `UndoRedoManager` (class_name) | undo/redo API for tools, `history_changed` signals |
| `SaveManager` | `DataRepository`, `RecentFilesManager` | Ctrl+S, FileDialog save, `save()`/`open()` |
| `RecentFilesManager` | — (ConfigFile only) | `get_files()`, `add_file()`, `remove_file()`, `clear()` |
| `canvas.gd` | `HistoryManager`, `VectopenInput` | Captures Ctrl+Z/Y on the canvas |
| `ImportExportManager` | `SaveManager`, `RecentFilesManager` | Updated QuickActionMenu buttons |
| `FileFlowLayout` | `RecentFilesManager` | Recent files tree (UI) |

---

## 2. HistoryManager (res://autoloads/HistoryManager.gd)

### Purpose
Provide a public API for tools to register undo/redo actions in the history. It acts as a wrapper around the Command pattern implemented in `UndoRedoManager`.

### Public API

```gdscript
# Registers a new action in history (clears the redo_stack)
HistoryManager.register_action("Move shape")

# Adds callables for do and undo
HistoryManager.add_do(some_callable)
HistoryManager.add_undo(another_callable)

# Confirms the action (emits state change signal)
HistoryManager.commit()

# Execute undo/redo
HistoryManager.undo()     # Ctrl+Z
HistoryManager.redo()     # Ctrl+Shift+Z

# Query state
var can_undo := HistoryManager.can_undo()
var can_redo := HistoryManager.can_redo()
var undo_name := HistoryManager.get_undo_name()  # "Move shape"
var redo_name := HistoryManager.get_redo_name()

# Clear history (e.g., when opening a new project)
HistoryManager.clear()
```

### Signals

```gdscript
signal history_changed(can_undo: bool, can_redo: bool, undo_name: String, redo_name: String)
signal undo_performed(action_name: String)
signal redo_performed(action_name: String)
```

### Integration with Ctrl+Z/Y

The canvas (`canvas.gd:_handle_keyboard`) captures the shortcuts:

```gdscript
# Check redo FIRST so Ctrl+Shift+Z does not accidentally trigger undo
if VectopenInput.is_action_triggered(event, "redo"):
    HistoryManager.redo()
    get_viewport().set_input_as_handled()
    return

if VectopenInput.is_action_triggered(event, "undo"):
    HistoryManager.undo()
    get_viewport().set_input_as_handled()
    return
```

The input actions are defined in `VectopenInput`:
- `undo` → Ctrl+Z (`{"key": KEY_Z, "ctrl": true}`)
- `redo` → Ctrl+Shift+Z (`{"key": KEY_Z, "shift": true, "ctrl": true}`)

### How to add undo to a tool (example)

```gdscript
# In any tool script:
func _on_transform_finished(shape: Node2D, old_pos: Vector2) -> void:
    var new_pos = shape.position
    HistoryManager.register_action("Move " + shape.name)
    HistoryManager.add_do(func(): shape.position = new_pos)
    HistoryManager.add_undo(func(): shape.position = old_pos)
    HistoryManager.commit()
```

**Note:** If the tool uses `DataRepository.update_shape()`, undo is already included automatically (DataRepository registers the action internally). Use `HistoryManager` directly when modifying nodes without going through DataRepository.

### Limits

- Maximum 100 actions in history (configurable via `DataRepository.settings.max_undo_steps`)
- When the limit is reached, the oldest action is discarded
- Registering a new action clears the `redo_stack`
- Compatible with `DataRepository`'s internal `UndoRedoManager` (each has its own stack)

---

## 3. SaveManager (res://autoloads/SaveManager.gd)

### Purpose
Unify and simplify project saving/loading, wrapping `DataRepository.save_project()` and `DataRepository.load_project()` with a clean API and keyboard shortcut.

### Public API

```gdscript
# Save (if there is a current path, saves there; otherwise opens dialog)
SaveManager.save()

# Save as (always opens dialog)
SaveManager.save_as()

# Load project
SaveManager.open("path/to/file.vectopen")

# New project
SaveManager.new_project("My Project")

# Mark as modified (so the UI shows an indicator)
SaveManager.mark_modified()
```

### Keyboard shortcut
- `Ctrl+S` → executes `SaveManager.save()`
- Captured via `_unhandled_input()` to avoid interfering with text fields
- If there is no current path, opens a "Save as..." FileDialog

### FileDialog integration

```gdscript
# save_as() creates a FileDialog with:
fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
fd.access = FileDialog.ACCESS_FILESYSTEM
fd.title = "Save project"
fd.add_filter("*.vectopen", "Vectopen Project")
fd.add_filter("*.json", "JSON Backup")
```

### Save flow

```
Ctrl+S (or Save button)
    → SaveManager.save()
        → Is there a current_path?
            → Yes: DataRepository.save_project(path)
                → RecentFilesManager.add_file(path)
                → emit project_saved(path)
            → No: SaveManager.save_as()
                → FileDialog popup
                → user selects path
                → _on_save_as_selected(path)
                    → DataRepository.save_project(path)
                    → RecentFilesManager.add_file(path)
```

---

## 4. RecentFilesManager (res://autoloads/RecentFilesManager.gd)

### Purpose
Unify the recent files logic that was previously duplicated between `FileFlowLayout.gd` (UI) and `FileSystemManager.gd` (logic). All system components use this single entry point.

### Public API

```gdscript
# Get list of recent files
var files: Array = RecentFilesManager.get_files()
# Each file: {"name": String, "path": String, "format": String, "time": int}

# Add file to recents (moves it to the top if it already exists)
RecentFilesManager.add_file("path/to/file.vectopen")

# Remove file from recents
RecentFilesManager.remove_file("path/to/file.vectopen")

# Clear entire history
RecentFilesManager.clear()
```

### Signal

```gdscript
signal recent_files_changed(files: Array)
```

### Storage

- File: `user://recent_assets.cfg` (ConfigFile format)
- Maximum: 20 files
- Section: `[History]` → `items` (Array of Dictionary)
- Order: most recent first (index 0)

```ini
[History]
items=[{"name": "MyProject", "path": "C:/.../my_project.vectopen", "format": "vectopen", "time": 1721849600}]
```

### Integration

| Component | Action |
|------------|--------|
| `SaveManager._save_to_path()` | Calls `add_file()` after saving |
| `SaveManager.open()` | Calls `add_file()` after loading |
| `ImportExportManager._on_open_file_selected()` | Calls `add_file()` |
| `FileFlowLayout._load_recent_files()` | Uses `get_files()` instead of reading ConfigFile directly |
| `FileFlowLayout._add_to_recent_files()` | Delegates to `add_file()` |

---

## 5. Modified Files

### New (3)

| File | Lines | Purpose |
|---------|--------|-----------|
| `res://autoloads/HistoryManager.gd` | 57 | Public wrapper for UndoRedoManager for tools |
| `res://autoloads/SaveManager.gd` | 68 | Save/load with Ctrl+S and FileDialog |
| `res://autoloads/RecentFilesManager.gd` | 49 | Unified recent files management |

### Modified (5)

| File | Change |
|---------|--------|
| `res://scripts/canvas/canvas.gd` | Added Ctrl+Z/Y handling via HistoryManager |
| `res://autoloads/VectopenInput.gd` | Added `save` action (Ctrl+S) |
| `res://project.godot` | Registered 3 new autoloads |
| `res://script_gdscript/system/ImportExportManager.gd` | QuickActionMenu buttons connected to SaveManager and RecentFilesManager |
| `res://scenes/ui/FileFlowLayout.gd` | Replaced direct ConfigFile reading with RecentFilesManager |

---

## 5.1 Note: `class_name` vs. Autoload Collision (fixed)

The 3 scripts originally declared `class_name X` with the same name as their autoload registration in `project.godot` (e.g. `class_name SaveManager` + `SaveManager="*res://autoloads/SaveManager.gd"`). Godot rejects this ("Class X hides an autoload singleton"), which broke the compilation chain of `ImportExportManager.gd` and prevented the 3 autoloads from loading. The `class_name` was removed from all 3 (`HistoryManager.gd`, `SaveManager.gd`, `RecentFilesManager.gd`), just like the rest of the project's autoloads (`DataRepository.gd`, etc. also do not declare `class_name`). No other scripts referenced these types by class name, so there was no additional impact.

## 6. Load Order (Autoloads)

```
GlobalEvents → DataRepository → HistoryManager → SaveManager → RecentFilesManager
```

**Note:** `HistoryManager`, `SaveManager` and `RecentFilesManager` must be loaded AFTER `DataRepository` and `GlobalEvents` because they depend on them. The order in `project.godot` respects this.

---

## 7. Usage for Tool Developers

### Basic undo registration

```gdscript
# When starting an operation (e.g., before moving)
var _old_position: Vector2

func _on_grab_start(shape: Node2D) -> void:
    _old_position = shape.position

# When finishing (e.g., releasing the mouse)
func _on_grab_end(shape: Node2D) -> void:
    var new_pos = shape.position
    if _old_position.distance_to(new_pos) > 0.01:
        HistoryManager.register_action("Move " + shape.name)
        HistoryManager.add_do(func(): shape.position = new_pos)
        HistoryManager.add_undo(func(): shape.position = _old_position)
        HistoryManager.commit()
```

### Undo without HistoryManager (using DataRepository)

If the tool already uses `DataRepository` to modify shapes, undo is automatic:

```gdscript
# DataRepository.create_shape() already registers undo
# DataRepository.update_shape() already registers undo
# DataRepository.delete_shape() already registers undo

# You only need to call these methods and undo is handled automatically:
DataRepository.update_shape(shape_id, "position", new_position)
```

### Considerations

1. **Do not duplicate undo:** If you use `DataRepository.update_shape()`, do NOT also register in `HistoryManager`
2. **Local snapshots:** Tools like `MoveTool` and `NodeSelectionTool` have local snapshots for cancelling with ESC — these are independent of the undo system and should be kept
3. **Compound actions:** For operations that modify multiple shapes, register a single action:

```gdscript
HistoryManager.register_action("Move multiple")
for shape in selected_shapes:
    var old = _snapshots[shape]["pos"]
    var new = shape.position
    HistoryManager.add_do(func(): shape.position = new)
    HistoryManager.add_undo(func(): shape.position = old)
HistoryManager.commit()
```

---

## 8. Integration with the Export Panel

### QuickActionMenu

| Button | Current action |
|-------|--------------|
| **BtnNuevo** (New) | `SaveManager.new_project()` |
| **BtnArchivos** (Files) | FileDialog → `SaveManager.open()` |
| **BtnRecuperar** (Recover) | FileDialog → `SaveManager.open()` |
| **BtnReciente** (Recent) | Opens the most recent file via `SaveManager.open()` |

### Export Panel (FileFlowLayout)

- **Browser (BtnBrowse)**: FileDialog to select an export folder
- **Folder path**: LineEdit with the selected path
- **Format Selector**: Export format selection (SVG, PNG, PDF, JPEG)
- **Recent Files Tree**: Shows recent files with thumbnails, search, drag & drop
