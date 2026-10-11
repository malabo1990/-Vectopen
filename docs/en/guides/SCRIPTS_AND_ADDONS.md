# Scripts and add-ons

**Effects → Script** tab, two modules. Spanish version: `docs/es/guides/scripts_y_complementos.md`.

## Scripts

Write GDScript and press **▶ Ejecutar** (Ctrl+Enter or F5). `api` is Vectopen (`VectopenAPI`).

```gdscript
# Quick mode: with no extends/func, the code is wrapped in run() automatically.
var s := api.add_star(api.artboard_size() / 2.0, 80, 5)
api.set_fill(s, Color.GOLD)
print("Created: ", s.name)
```

```gdscript
extends VectopenScript

func run() -> void:
	for s in api.selection():
		api.set_fill(s, Color.from_hsv(randf(), 0.6, 0.95))
```

- One run = **one undo step**. If the script fails, its changes are rolled back and the console shows the line (click to jump).
- Syntax is checked while typing; `api.` + Ctrl+Space autocompletes; **API** button shows the reference (`VectopenAPI.REFERENCE`).
- **Guardar** (Ctrl+S) saves to `user://scripts/`; templates included. `run()` may `await api.wait(0.2)`.
- The API covers shapes, text, images, artboards, Inspector properties, selection, z-order, align/distribute, booleans, effects, filters, **shaders** (`apply_shader`, `save_shader`…), SVG import, export (.svg/.png/.jpg/.webp/.pdf) and vectorize. System operations with their own undo (booleans, align) are folded into the script's single undo step.
- Coordinates are artboard document space (top-left origin); shapes are placed by their **center**.
- An infinite loop freezes the app (GDScript cannot be interrupted).

## Add-ons

Blender-like. **Instalar…** accepts a `.zip`, a folder, or a `.gd`. Checkbox = enable/disable (remembered).
`⋯` menu: reload code, open folder, uninstall. Bundled (`res://plugins/`): Colores, Repetir, Hola Vectopen.
User add-ons: `user://addons/<id>/`.

```
my_addon/
  addon.cfg   # [addon] name, version, author, description, category, api="1.0", main="main.gd", enabled_by_default
  main.gd
```

```gdscript
extends VectopenAddon

func _enable() -> void:
	add_operator("Center", center, "Move the selection to the artboard center")
	add_panel(my_settings_control)      # shown on the add-on card

func center() -> void:                   # runs as ONE undo step
	for s in api.selection():
		api.set_position(s, api.artboard_size() / 2.0)
```

- `get_setting(key, default)` / `set_setting(key, value)` persist per add-on.
- Operators and panels are removed automatically on disable.
- An add-on that errors while enabling stays disabled and shows the error on its card.
- Loaded only if its `api` major version matches. Old single-file plugins with `on_load()` still load.
- Add-ons run with the same permissions as Vectopen: install only trusted ones.

## Internals

| File | Role |
|---|---|
| `script_gdscript/api/vectopen_api.gd` | `VectopenAPI` facade (InspectorCore, HistoryManager, SelectionManager, ArtboardManager); `begin/end` transactions = one undo step |
| `script_gdscript/api/script_runner.gd` | compile/check/run with a `Logger` capturing errors + output; rollback on error |
| `script_gdscript/api/script_library.gd` | `user://scripts/` + templates |
| `script_gdscript/api/vectopen_addon.gd`, `vectopen_script.gd` | base classes |
| `autoloads/PluginManager.gd` | discovery, install, enable/disable, `api` instance |
| `script_gdscript/ui/panels/effects/script_panel.gd` | the Script tab UI |

Tests: `test/core/VectopenAPI_test.gd`, `test/ui/ScriptPanel_test.gd` (including that every public API method is documented in `REFERENCE`).
