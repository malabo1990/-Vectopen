# LayerPanel.gd
# Panel de capas (prueba piloto) - CORREGIDO: add_button con Texture2D válido
# Godot 4.x - Sin errores en add_button()

@tool
extends PanelContainer

# ======================
# EXPORTED NODE PATHS
# ======================
@export var tree_path: NodePath
@export var btn_add_layer_path: NodePath
@export var btn_add_group_path: NodePath
@export var btn_add_mask_path: NodePath
@export var btn_move_up_path: NodePath
@export var btn_move_down_path: NodePath

# ======================
# ONREADY REFERENCES
# ======================
@onready var tree: Tree = get_node(tree_path) as Tree
@onready var btn_add_layer: Button = get_node(btn_add_layer_path) as Button
@onready var btn_add_group: Button = get_node(btn_add_group_path) as Button
@onready var btn_add_mask: Button = get_node(btn_add_mask_path) as Button
@onready var btn_move_up: Button = get_node(btn_move_up_path) as Button
@onready var btn_move_down: Button = get_node(btn_move_down_path) as Button

# ======================
# TEXTURA VACÍA PARA BOTONES
# ======================
var empty_texture: Texture2D

# ======================
# ESTADO
# ======================
var root: TreeItem

# ======================
# READY
# ======================
func _ready() -> void:
	# Crear textura vacía 1x1 (transparente)
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	empty_texture = ImageTexture.create_from_image(img)
	
	# Configuración del Tree
	tree.hide_root = true
	tree.columns = 1
	tree.allow_rmb_select = true
	tree.set_column_expand(0, true)
	tree.set_column_clip_content(0, true)
	
	root = tree.create_item()
	
	# Botones: solo conectamos señales (textos ya puestos por ti)
	btn_add_layer.pressed.connect(_on_add_layer)
	btn_add_group.pressed.connect(_on_add_group)
	btn_add_mask.pressed.connect(_on_add_mask)
	btn_move_up.pressed.connect(_on_move_up)
	btn_move_down.pressed.connect(_on_move_down)
	
	# Señales del Tree
	tree.item_edited.connect(_on_item_edited)
	tree.button_clicked.connect(_on_button_clicked)
	tree.item_mouse_selected.connect(_on_item_mouse_selected)
	
	# Capas de ejemplo
	_add_example_layers()

# ======================
# CREACIÓN DE ITEMS
# ======================
func _create_layer_item(layer_name: String, type: String = "layer", parent: TreeItem = null) -> TreeItem:
	var item := tree.create_item(parent if parent else root)
	item.set_text(0, layer_name)
	item.set_editable(0, true)
	item.set_metadata(0, { "type": type, "visible": true, "locked": false })
	
	# Botones con textura vacía (no null)
	item.add_button(0, empty_texture, 0)
	item.set_button_tooltip(0, 0, "Visibilidad: ON")
	
	item.add_button(0, empty_texture, 1)
	item.set_button_tooltip(0, 1, "Bloqueo: OFF")
	
	return item

func _on_add_layer() -> void:
	var selected := tree.get_selected()
	var parent_item := root
	if selected and selected.get_metadata(0).type == "group":
		parent_item = selected
	_create_layer_item("Nueva Capa", "layer", parent_item)

func _on_add_group() -> void:
	var selected := tree.get_selected()
	var parent_item := root
	if selected and selected.get_metadata(0).type == "group":
		parent_item = selected
	_create_layer_item("Nuevo Grupo", "group", parent_item)

func _on_add_mask() -> void:
	var selected := tree.get_selected()
	if not selected:
		push_warning("Selecciona una capa para añadir máscara")
		return
	var parent := selected.get_parent()
	var mask := _create_layer_item("Máscara", "mask", parent)
	parent.insert_child(mask, selected.get_index() + 1)

# ======================
# REORDENAMIENTO MANUAL
# ======================
func _on_move_up() -> void:
	var item := tree.get_selected()
	if not item or item == root: return
	var prev := item.get_prev()
	if prev:
		item.move_before(prev)
		tree.select(item.get_index())

func _on_move_down() -> void:
	var item := tree.get_selected()
	if not item or item == root: return
	var next := item.get_next()
	if next:
		item.move_after(next)
		tree.select(item.get_index())

# ======================
# INTERACCIÓN
# ======================
func _on_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	var meta = item.get_metadata(0)
	match id:
		0: # Ojo
			meta.visible = !meta.visible
			item.set_button_tooltip(0, 0, "Visibilidad: " + ("ON" if meta.visible else "OFF"))
			item.set_metadata(0, meta)
			layer_visibility_changed.emit(item, meta.visible)
		
		1: # Candado
			meta.locked = !meta.locked
			item.set_button_tooltip(0, 1, "Bloqueo: " + ("ON" if meta.locked else "OFF"))
			item.set_metadata(0, meta)
			layer_locked_changed.emit(item, meta.locked)

func _on_item_edited() -> void:
	var item := tree.get_edited()
	if item:
		var text := item.get_text(0).strip_edges()
		if text.is_empty():
			text = "Capa sin nombre"
		item.set_text(0, text)
		layer_renamed.emit(item, text)

func _on_item_mouse_selected(_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_RIGHT:
		_show_context_menu(tree.get_selected())

# ======================
# MENÚ CONTEXTUAL
# ======================
func _show_context_menu(item: TreeItem) -> void:
	if not item: return
	var menu := PopupMenu.new()
	menu.add_item("Eliminar", 0)
	menu.add_item("Duplicar", 1)
	menu.add_separator()
	menu.add_item("Convertir en Grupo", 2)
	menu.id_pressed.connect(func(id):
		match id:
			0: _delete_item(item)
			1: _duplicate_item(item)
			2: _convert_to_group(item)
		menu.queue_free()
	)
	add_child(menu)
	menu.popup(Rect2(get_global_mouse_position(), Vector2(150, 100)))

func _delete_item(item: TreeItem) -> void:
	if item.get_parent():
		item.get_parent().remove_child(item)

func _duplicate_item(item: TreeItem) -> void:
	var meta = item.get_metadata(0)
	var copy := _create_layer_item(item.get_text(0) + " (copia)", meta.type, item.get_parent())
	copy.move_after(item)

func _convert_to_group(item: TreeItem) -> void:
	if item.get_metadata(0).type == "group": return
	var meta = item.get_metadata(0)
	meta.type = "group"
	item.set_metadata(0, meta)

# ======================
# EJEMPLO INICIAL
# ======================
func _add_example_layers() -> void:
	var group := _create_layer_item("Fondo", "group")
	_create_layer_item("Cielo", "layer", group)
	_create_layer_item("Personaje", "layer")

# ======================
# SEÑALES PERSONALIZADAS
# ======================
signal layer_visibility_changed(item: TreeItem, visible: bool)
signal layer_locked_changed(item: TreeItem, locked: bool)
signal layer_renamed(item: TreeItem, new_name: String)
