# Sistemas de Historial, Guardado y Archivos Recientes

> **Versión:** Implementado Julio 2026 | **Autoloads nuevos:** 3 | **Atajos:** Ctrl+Z, Ctrl+Shift+Z, Ctrl+S

---

## 1. Arquitectura General

Se añadieron tres nuevos autoloads que trabajan en conjunto:

```
┌─────────────────────────────────────────────────────────┐
│                    AUTOLOADS (3 nuevos)                   │
│                                                          │
│  HistoryManager     SaveManager     RecentFilesManager   │
│  (undo/redo)        (guardar/cargar) (archivos recientes)│
└───────┬──────────────────┬───────────────────┬───────────┘
        │                  │                   │
        ▼                  ▼                   ▼
┌──────────────┐  ┌──────────────┐  ┌────────────────────┐
│UndoRedoManager│  │DataRepository│  │user://recent_assets│
│(CommandPattern)│  │ (save/load)  │  │    .cfg (Config)  │
└──────────────┘  └──────────────┘  └────────────────────┘
```

### Dependencias entre sistemas

| Sistema | Depende de | Proporciona |
|---------|-----------|-------------|
| `HistoryManager` | `UndoRedoManager` (class_name) | API undo/redo para tools, señales `history_changed` |
| `SaveManager` | `DataRepository`, `RecentFilesManager` | Ctrl+S, FileDialog guardar, `save()`/`open()` |
| `RecentFilesManager` | — (solo ConfigFile) | `get_files()`, `add_file()`, `remove_file()`, `clear()` |
| `canvas.gd` | `HistoryManager`, `VectopenInput` | Captura Ctrl+Z/Y en el canvas |
| `ImportExportManager` | `SaveManager`, `RecentFilesManager` | Botones QuickActionMenu actualizados |
| `FileFlowLayout` | `RecentFilesManager` | Árbol de archivos recientes (UI) |

---

## 2. HistoryManager (res://autoloads/HistoryManager.gd)

### Propósito
Proporcionar una API pública para que las herramientas registren acciones de undo/redo en el historial. Funciona como wrapper del patrón Command implementado en `UndoRedoManager`.

### API pública

```gdscript
# Registra una nueva acción en el historial (limpia el redo_stack)
HistoryManager.register_action("Mover形状")

# Añade callables para hacer y deshacer
HistoryManager.add_do(some_callable)
HistoryManager.add_undo(another_callable)

# Confirma la acción (emite señal de cambio de estado)
HistoryManager.commit()

# Ejecutar undo/redo
HistoryManager.undo()     # Ctrl+Z
HistoryManager.redo()     # Ctrl+Shift+Z

# Consultar estado
var can_undo := HistoryManager.can_undo()
var can_redo := HistoryManager.can_redo()
var undo_name := HistoryManager.get_undo_name()  # "Mover形状"
var redo_name := HistoryManager.get_redo_name()

# Limpiar historial (ej. al abrir nuevo proyecto)
HistoryManager.clear()
```

### Señales

```gdscript
signal history_changed(can_undo: bool, can_redo: bool, undo_name: String, redo_name: String)
signal undo_performed(action_name: String)
signal redo_performed(action_name: String)
```

### Integración con Ctrl+Z/Y

El canvas (`canvas.gd:_handle_keyboard`) captura los atajos:

```gdscript
# Revisar redo PRIMERO para que Ctrl+Shift+Z no active undo accidentalmente
if VectopenInput.is_action_triggered(event, "redo"):
    HistoryManager.redo()
    get_viewport().set_input_as_handled()
    return

if VectopenInput.is_action_triggered(event, "undo"):
    HistoryManager.undo()
    get_viewport().set_input_as_handled()
    return
```

Las acciones de input están definidas en `VectopenInput`:
- `undo` → Ctrl+Z (`{"key": KEY_Z, "ctrl": true}`)
- `redo` → Ctrl+Shift+Z (`{"key": KEY_Z, "shift": true, "ctrl": true}`)

### Cómo añadir undo a una herramienta (ejemplo)

```gdscript
# En cualquier tool script:
func _on_transform_finished(shape: Node2D, old_pos: Vector2) -> void:
    var new_pos = shape.position
    HistoryManager.register_action("Mover " + shape.name)
    HistoryManager.add_do(func(): shape.position = new_pos)
    HistoryManager.add_undo(func(): shape.position = old_pos)
    HistoryManager.commit()
```

**Nota:** Si la herramienta usa `DataRepository.update_shape()`, el undo ya está incluido automáticamente (DataRepository registra la acción internamente). Usar `HistoryManager` directamente cuando se modifican nodos sin pasar por DataRepository.

### Límites

- Máximo 100 acciones en el historial (configurable vía `DataRepository.settings.max_undo_steps`)
- Al llegar al límite, se descarta la acción más antigua
- Al registrar una nueva acción, se limpia el `redo_stack`
- Compatible con el `UndoRedoManager` interno de `DataRepository` (cada uno tiene su propio stack)

---

## 3. SaveManager (res://autoloads/SaveManager.gd)

### Propósito
Unificar y simplificar el guardado/carga de proyectos, envolviendo `DataRepository.save_project()` y `DataRepository.load_project()` con una API limpia y atajo de teclado.

### API pública

```gdscript
# Guardar (si hay ruta actual, guarda ahí; si no, abre diálogo)
SaveManager.save()

# Guardar como (siempre abre diálogo)
SaveManager.save_as()

# Cargar proyecto
SaveManager.open("ruta/al/archivo.vectopen")

# Nuevo proyecto
SaveManager.new_project("Mi Proyecto")

# Marcar como modificado (para que la UI muestre indicador)
SaveManager.mark_modified()
```

### Atajo de teclado
- `Ctrl+S` → ejecuta `SaveManager.save()`
- Capturado via `_unhandled_input()` para no interferir con campos de texto
- Si no hay ruta actual, abre FileDialog de "Guardar como..."

### FileDialog integration

```gdscript
# save_as() crea un FileDialog con:
fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
fd.access = FileDialog.ACCESS_FILESYSTEM
fd.title = "Guardar proyecto"
fd.add_filter("*.vectopen", "Vectopen Project")
fd.add_filter("*.json", "JSON Backup")
```

### Flujo de guardado

```
Ctrl+S (o botón Guardar)
    → SaveManager.save()
        → ¿Hay current_path?
            → Sí: DataRepository.save_project(path)
                → RecentFilesManager.add_file(path)
                → emit project_saved(path)
            → No: SaveManager.save_as()
                → FileDialog popup
                → user selecciona ruta
                → _on_save_as_selected(path)
                    → DataRepository.save_project(path)
                    → RecentFilesManager.add_file(path)
```

---

## 4. RecentFilesManager (res://autoloads/RecentFilesManager.gd)

### Propósito
Unificar la lógica de archivos recientes que antes estaba duplicada entre `FileFlowLayout.gd` (UI) y `FileSystemManager.gd` (lógica). Todos los componentes del sistema usan este único punto de entrada.

### API pública

```gdscript
# Obtener lista de archivos recientes
var files: Array = RecentFilesManager.get_files()
# Cada archivo: {"name": String, "path": String, "format": String, "time": int}

# Añadir archivo a recientes (lo mueve al inicio si ya existe)
RecentFilesManager.add_file("ruta/al/archivo.vectopen")

# Eliminar archivo de recientes
RecentFilesManager.remove_file("ruta/al/archivo.vectopen")

# Limpiar todo el historial
RecentFilesManager.clear()
```

### Señal

```gdscript
signal recent_files_changed(files: Array)
```

### Almacenamiento

- Archivo: `user://recent_assets.cfg` (formato ConfigFile)
- Máximo: 20 archivos
- Sección: `[History]` → `items` (Array de Dictionary)
- Orden: el más reciente primero (índice 0)

```ini
[History]
items=[{"name": "MiProyecto", "path": "C:/.../mi_proyecto.vectopen", "format": "vectopen", "time": 1721849600}]
```

### Integración

| Componente | Acción |
|------------|--------|
| `SaveManager._save_to_path()` | Llama `add_file()` tras guardar |
| `SaveManager.open()` | Llama `add_file()` tras cargar |
| `ImportExportManager._on_open_file_selected()` | Llama `add_file()` |
| `FileFlowLayout._load_recent_files()` | Usa `get_files()` en vez de leer ConfigFile directamente |
| `FileFlowLayout._add_to_recent_files()` | Delega en `add_file()` |

---

## 5. Archivos Modificados

### Nuevos (3)

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `res://autoloads/HistoryManager.gd` | 57 | Wrapper público de UndoRedoManager para tools |
| `res://autoloads/SaveManager.gd` | 68 | Guardado/carga con Ctrl+S y FileDialog |
| `res://autoloads/RecentFilesManager.gd` | 49 | Gestión unificada de archivos recientes |

### Modificados (5)

| Archivo | Cambio |
|---------|--------|
| `res://scripts/canvas/canvas.gd` | Añadido manejo de Ctrl+Z/Y vía HistoryManager |
| `res://autoloads/VectopenInput.gd` | Añadida acción `save` (Ctrl+S) |
| `res://project.godot` | Registrados 3 nuevos autoloads |
| `res://script_gdscript/system/ImportExportManager.gd` | Botones QuickActionMenu conectados a SaveManager y RecentFilesManager |
| `res://scenes/ui/FileFlowLayout.gd` | Sustituida lectura directa de ConfigFile por RecentFilesManager |

---

## 5.1 Nota: Colisión `class_name` vs. Autoload (corregido)

Los 3 scripts originalmente declaraban `class_name X` con el mismo nombre que su registro de autoload en `project.godot` (ej. `class_name SaveManager` + `SaveManager="*res://autoloads/SaveManager.gd"`). Godot rechaza esto ("Class X hides an autoload singleton"), lo que rompía la compilación en cadena de `ImportExportManager.gd` y evitaba que los 3 autoloads cargaran. Se quitó el `class_name` de los 3 (`HistoryManager.gd`, `SaveManager.gd`, `RecentFilesManager.gd`), igual que ya hacen el resto de autoloads del proyecto (`DataRepository.gd`, etc. tampoco declaran `class_name`). Ningún otro script referenciaba estos tipos por nombre de clase, así que no hubo impacto adicional.

## 6. Orden de Carga (Autoloads)

```
GlobalEvents → DataRepository → HistoryManager → SaveManager → RecentFilesManager
```

**Nota:** `HistoryManager`, `SaveManager` y `RecentFilesManager` deben cargarse DESPUÉS de `DataRepository` y `GlobalEvents` porque dependen de ellos. El orden en `project.godot` respeta esto.

---

## 7. Uso para Desarrolladores de Tools

### Registro básico de undo

```gdscript
# Al comenzar una operación (ej. antes de mover)
var _old_position: Vector2

func _on_grab_start(shape: Node2D) -> void:
    _old_position = shape.position

# Al finalizar (ej. soltar el mouse)
func _on_grab_end(shape: Node2D) -> void:
    var new_pos = shape.position
    if _old_position.distance_to(new_pos) > 0.01:
        HistoryManager.register_action("Mover " + shape.name)
        HistoryManager.add_do(func(): shape.position = new_pos)
        HistoryManager.add_undo(func(): shape.position = _old_position)
        HistoryManager.commit()
```

### Undo sin HistoryManager (usando DataRepository)

Si la tool ya usa `DataRepository` para modificar shapes, el undo es automático:

```gdscript
# DataRepository.create_shape() ya registra undo
# DataRepository.update_shape() ya registra undo
# DataRepository.delete_shape() ya registra undo

# Solo necesitas llamar a estos métodos y el undo se maneja solo:
DataRepository.update_shape(shape_id, "position", new_position)
```

### Consideraciones

1. **No duplicar undo:** Si usas `DataRepository.update_shape()`, NO registres también en `HistoryManager`
2. **Snapshots locales:** Tools como `MoveTool` y `NodeSelectionTool` tienen snapshots locales para cancelar con ESC — estos son independientes del sistema de undo y deben mantenerse
3. **Acciones compuestas:** Para operaciones que modifican múltiples shapes, registra una sola acción:

```gdscript
HistoryManager.register_action("Mover múltiples")
for shape in selected_shapes:
    var old = _snapshots[shape]["pos"]
    var new = shape.position
    HistoryManager.add_do(func(): shape.position = new)
    HistoryManager.add_undo(func(): shape.position = old)
HistoryManager.commit()
```

---

## 8. Integración con el Panel Export

### QuickActionMenu

| Botón | Acción actual |
|-------|--------------|
| **BtnNuevo** (New) | `SaveManager.new_project()` |
| **BtnArchivos** (Files) | FileDialog → `SaveManager.open()` |
| **BtnRecuperar** (Recover) | FileDialog → `SaveManager.open()` |
| **BtnReciente** (Recent) | Abre el archivo reciente más reciente vía `SaveManager.open()` |

### Export Panel (FileFlowLayout)

- **Browser (BtnBrowse)**: FileDialog para seleccionar carpeta de exportación
- **Folder path**: LineEdit con la ruta seleccionada
- **Format Selector**: Selección de formato de exportación (SVG, PNG, PDF, JPEG)
- **Recent Files Tree**: Muestra archivos recientes con thumbnails, búsqueda, drag & drop
