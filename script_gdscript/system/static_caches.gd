# =============================================================================
# RUTA: res://script_gdscript/system/static_caches.gd
# Al CERRAR la app se vacían las cachés `static var` que guardan texturas,
# iconos, shaders y fuentes. Si no, se liberan al descargar los scripts,
# DESPUÉS de apagar el RenderingServer, y Godot avisa «leaked at exit»
# (y «RenderingServer::get_singleton() is null» en ~ImageTexture).
# Lo llama GlobalEvents._exit_tree. Solo toca scripts ya cargados.
# =============================================================================
extends RefCounted

const CACHES := {
	"res://script_gdscript/shapes/stroke_textures.gd": ["_cache"],
	"res://script_gdscript/shapes/filter_fx.gd": ["_shader_cache"],
	"res://script_gdscript/ui/toolbar.gd": ["_blanco_cache"],
	"res://script_gdscript/ui/modern/modern_bottom_toolbar.gd": ["_icon_cache"],
	"res://script_gdscript/ui/layers_system.gd": ["_icon_cache", "_type_icons", "_ICON_EYE", "_ICON_EYE_OFF",
		"_ICON_LOCK", "_ICON_LOCK_OPEN", "_CLIP_ICON", "_CLIP_ICON_OFF"],
	"res://script_gdscript/shapes/brush_stroke_render.gd": ["_shared_mats", "_pencil_shader"],
	"res://script_gdscript/shapes/VectorShape.gd": ["_shadow_shader", "_blur_shader", "_inner_shadow_shader", "_bevel_3d_shader"],
	"res://script_gdscript/shapes/blend_modes.gd": ["_shader"],
	"res://script_gdscript/ui/pro/pro_ui_style.gd": ["_icon_cache"],
	"res://script_gdscript/text/text_fx.gd": ["_grad_cache"],
	"res://script_gdscript/ui/transform_panel.gd": ["_icon_cache"],
	"res://script_gdscript/ui/panels/layer_icons.gd": ["_cache"],
	"res://scripts/canvas/world_text_label.gd": ["_glyph_cache"],
	"res://script_gdscript/shapes/vector_light.gd": ["_tex_cache"],
	# Objetos de las librerías NATIVAS (Rust): al cerrar, Godot descarga las
	# extensiones antes de revisar los objetos vivos y uno que quede se
	# avisaba como «1 ObjectDB instance leaked» de clase «RefCounted».
	"res://script_gdscript/system/native_io.gd": ["_io"],
	"res://script_gdscript/shapes/stroke_geom.gd": ["_geom_io"],
}

static func clear_all() -> void:
	for path in CACHES:
		if not ResourceLoader.has_cached(path):
			continue
		var sc: Script = load(path)
		if sc == null:
			continue
		for prop in CACHES[path]:
			var v = sc.get(prop)
			if v is Dictionary:
				(v as Dictionary).clear()
			elif v is Object:
				sc.set(prop, null)
	if ResourceLoader.has_cached("res://scripts/canvas/world_text_label.gd"):
		load("res://scripts/canvas/world_text_label.gd").set("_fallback_font", null)
	# Cursores personalizados (SmartCursor, cuentagotas, pincel): Input guarda
	# su textura y Input se destruye DESPUÉS del RenderingServer.
	for shape in range(Input.CURSOR_ARROW, Input.CURSOR_HELP + 1):
		Input.set_custom_mouse_cursor(null, shape)
