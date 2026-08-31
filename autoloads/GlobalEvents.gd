# ==========================================
# RUTA: res://script_gdscript/GlobalEvents.gd
# CONFIGURACIÓN: Mantener como Autoload (Singleton)
# ==========================================
@warning_ignore("unused_signal")
extends Node

# ==========================================
# SEÑALES EXISTENTES (Tus señales originales)
# ==========================================

# --- SEÑALES DE ARTBOARDS ---
signal artboard_created
signal artboard_deleted
signal artboard_selected
signal artboard_moved
signal artboard_resized
signal active_artboard_changed

# --- SEÑALES DEL COLOR / DEGRADADO ---
signal color_changed(new_color: Color)
signal gradient_changed(gradient: Gradient)
signal color_picker_opened
signal color_picker_closed

# --- SEÑALES DE CAPAS ---
signal layer_created
signal layer_deleted(layer_index: int)
signal layer_selected(layer_index: int)
signal layer_reordered
signal layer_visibility_toggled(layer_index: int, is_layer_visible: bool)
signal layer_locked_toggled

# --- SEÑALES DE OBJETOS VECTORIALES ---
signal object_created
signal object_selected
signal object_deleted
signal object_transformed
signal object_style_changed
## La selección del canvas cambió (añadida/quitada figura, o limpiada).
## `shapes` = Array de Node2D seleccionados ahora. La escucha InspectorCore.
signal selection_changed(shapes: Array)

# --- SEÑALES DE EFECTOS / UI ---
signal effect_parameter_updated(effect_name: String, property: String, value: Variant)
signal export_finished
signal export_error
signal import_started
signal import_finished
signal import_error
signal performance_warning
signal renderer_changed
signal memory_pressure_high
signal effect_applied
signal shader_applied
signal autosave_finished(path: String)
signal project_saved(path: String)
signal project_loaded(path: String)
signal filter_applied
signal vectorization_started
signal vectorization_progress
signal vectorization_finished

# ==========================================
# NUEVAS SEÑALES PARA DATA REPOSITORY
# ==========================================
signal data_project_loaded(project_name: String)
signal data_project_saved
signal data_project_closed
signal data_auto_save_triggered
signal data_auto_save_restored

signal data_shape_created(shape_id: String, shape_type: String)
signal data_shape_deleted(shape_id: String)
signal data_shape_changed(shape_id: String, property: String, value)
signal data_shape_selected(shape_id: String, add_to_selection: bool)

signal data_selection_changed(selected_ids: Array[String])
signal data_selection_cleared

signal data_layer_created(layer_id: String, layer_name: String)
signal data_layer_deleted(layer_id: String)
signal data_layer_changed(layer_id: String, property: String, value)
signal data_layer_reordered

signal data_artboard_created(artboard_id: String)
signal data_artboard_deleted(artboard_id: String)
signal data_artboard_changed(artboard_id: String, property: String, value)
signal data_active_artboard_changed(artboard_id: String)

signal data_undo_state_changed(can_undo: bool, can_redo: bool)
signal data_undo_performed
signal data_redo_performed

signal data_tool_changed(tool_name: String)
signal data_tool_config_changed(tool_name: String, config_key: String, value)

signal data_session_state_changed
signal data_recovery_saved
signal data_grid_settings_changed(grid_size: float, snap_enabled: bool)

signal theme_changed(mode: String)

# ==========================================
# MÉTODO DE UTILIDAD PARA EMISIÓN SEGURA
# ==========================================

## Emite una señal de forma segura si existe
func emit_safe(signal_name: String, arg1 = null, arg2 = null, arg3 = null) -> void:
	if has_signal(signal_name):
		match [arg1 != null, arg2 != null, arg3 != null]:
			[false, false, false]: emit_signal(signal_name)
			[true, false, false]: emit_signal(signal_name, arg1)
			[true, true, false]: emit_signal(signal_name, arg1, arg2)
			[true, true, true]: emit_signal(signal_name, arg1, arg2, arg3)
