# =============================================================================
# VECTOPEN — INCRUSTAR UN COMPONENTE DE SMART EN EL PANEL DERECHO
# RUTA: res://script_gdscript/ui/components/smart_embed.gd
#
# Modern (inspector, estilo Figma) y Pro (estudio, estilo Affinity) usan los
# MISMOS componentes que Smart (tipografía completa, lista de efectos…) en
# vez de copias reducidas. Aquí se instancian sin su marco de ventana
# flotante (fondo, borde, sombra) para que se vean como una sección más.
# =============================================================================
extends RefCounted

## Instancia `scene_path` dentro de `parent` (envuelto, para aislar los
## efectos secundarios que algunos componentes hacen sobre su padre).
## `hide_paths`: nodos del componente que sobran en el lateral (su título:
## la sección del inspector ya tiene cabecera; antes salía «TIPOGRAFÍA» y
## debajo «TIPOGRAFÍA / TEXT»).
static func embed(scene_path: String, parent: Control, node_name: String, hide_paths: Array = []) -> Control:
	if not is_instance_valid(parent) or not ResourceLoader.exists(scene_path):
		return null
	var wrap := VBoxContainer.new()
	wrap.name = node_name
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)
	var inst := (load(scene_path) as PackedScene).instantiate() as Control
	if inst == null:
		return wrap
	inst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inst.custom_minimum_size.x = 0
	wrap.add_child(inst)
	flatten(inst)
	for hp in hide_paths:
		var h := inst.get_node_or_null(NodePath(String(hp))) as CanvasItem
		if h:
			h.visible = false
	return wrap

## Títulos propios de cada componente (sobran dentro de una sección).
const TITLE_PATHS := {
	"res://scenes/ui/panel_tooltext.tscn": ["BoxContainer/Label"],
	"res://scenes/ui/panels/effects/effects.tscn": ["MarginContainer/VBoxContainer/Toolbar/Label"],
}

## Quita el marco de ventana del componente (lo repone su propio tema si lo
## vuelve a pintar: se llama otra vez al cambiar de tema).
static func flatten(c: Control) -> void:
	if c is PanelContainer:
		var e := StyleBoxEmpty.new()
		c.add_theme_stylebox_override("panel", e)
