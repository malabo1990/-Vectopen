# =============================================================================
# VECTOPEN STUDIO — LAYER TREE (UI COMPONENT)
# ARCHIVO: res://scenes/ui/LayerTree.gd
# MODALIDAD: @tool (Ejecución en editor y tiempo real)
# =============================================================================
@tool
extends Tree

# NOTA: Si Godot vuelve a decir "hides a global script class", comenta esta línea, 
# guarda el archivo (Ctrl+S), descomméntala y vuelve a guardar.
class_name LayerTree

# ─── COLUMNAS ─────────────────────────────────────────────────────────────────
const COL_VIS  : int = 0  # Checkbox visibilidad (Ojo)
const COL_NAME : int = 1  # Nombre del nodo + Icono vector/grupo
const COL_MASK : int = 2  # Checkbox bloqueo (Candado)

# ─── PROPIEDADES EXPORTADAS (ESTILO STUDIO MACOS) ─────────────────────────────
@export_group("Velocidad de Arrastre")
@export var velocidad_arrastre : float = 1.0

@export_group("Fondo")
@export var color_bg               : Color = Color(0.13, 0.13, 0.14)

@export_group("Texto Normal")
@export var color_text             : Color = Color(0.84, 0.84, 0.86)

@export_group("Texto Oculto")
@export var color_text_dim         : Color = Color(0.44, 0.44, 0.46)

@export_group("Selección")
@export var color_select_bg        : Color = Color(0.05, 0.30, 0.60, 0.35)
@export var color_select_text      : Color = Color(1.00, 1.00, 1.00)

@export_group("Enfoque")
@export var color_focus_bg         : Color = Color(0.05, 0.30, 0.60, 0.20)

@export_group("Artboard")
@export var color_artboard_bg      : Color = Color(0.16, 0.16, 0.18)
@export var color_artboard_text    : Color = Color(0.95, 0.95, 0.96)
@export var color_artboard_dim     : Color = Color(0.44, 0.44, 0.46)

@export_group("Grupo")
@export var color_group_text       : Color = Color(0.35, 0.75, 0.98)

@export_group("Líneas Guía")
@export var color_guide            : Color = Color(0.24, 0.24, 0.26)

@export_group("Diseño")
@export var indent_size            : int   = 16

# ─── SEÑALES PÚBLICAS ─────────────────────────────────────────────────────────
signal item_right_clicked(item: TreeItem, position: Vector2)
signal item_selected_for_inspector(nodo: Node2D)
signal hierarchy_changed_by_user

# ─── ESTADO INTERNO ───────────────────────────────────────────────────────────
var _seleccion_previa    : TreeItem    = null
var _texto_filtro        : String      = ""
var _arrastrando_scroll  : bool        = false
var _ultima_pos_y        : float       = 0.0
var _vscroll             : VScrollBar  = null

# =============================================================================
# INICIALIZACIÓN
# =============================================================================
func _ready() -> void:
	columns          = 3
	hide_root        = true
	allow_rmb_select = true
	allow_reselect   = true
	select_mode      = Tree.SELECT_SINGLE
	
	# Flag combinado: DROP_MODE_ON_ITEM (1) | DROP_MODE_IN_BETWEEN (2)
	drop_mode_flags  = 3 

	set_column_custom_minimum_width(COL_VIS,  32)
	set_column_expand(COL_VIS,  false)
	set_column_clip_content(COL_VIS,  true)

	set_column_expand(COL_NAME, true)
	set_column_clip_content(COL_NAME, false)

	set_column_custom_minimum_width(COL_MASK, 32)
	set_column_expand(COL_MASK, false)
	set_column_clip_content(COL_MASK, true)

	_apply_theme()

	item_mouse_selected.connect(_on_item_mouse_selected)
	item_selected.connect(_on_item_selected_internal)

	call_deferred("_buscar_vscroll_nativo")

# =============================================================================
# TEMA VISUAL (INTERFAZ ELEGANTE COMPACTA)
# =============================================================================
func _apply_theme() -> void:
	add_theme_stylebox_override("panel",          _flat_solid(color_bg, 0))
	add_theme_stylebox_override("bg",              _flat_solid(color_bg, 0))
	add_theme_stylebox_override("bg_focus",       _flat_solid(color_bg, 0))
	add_theme_stylebox_override("selected",       _flat_solid(color_select_bg, 4))
	add_theme_stylebox_override("selected_focus", _flat_solid(color_select_bg, 4))
	add_theme_stylebox_override("cursor",         _flat_solid(color_focus_bg, 4))

	var drop_style := StyleBoxFlat.new()
	drop_style.bg_color     = Color(0.05, 0.44, 1.0, 0.08)
	drop_style.border_color = Color(0.05, 0.44, 1.0, 0.85)
	drop_style.set_border_width_all(1)
	drop_style.set_corner_radius_all(3)
	add_theme_stylebox_override("drop_zone", drop_style)

	add_theme_color_override("font_color",              color_text)
	add_theme_color_override("font_selected_color",     color_select_text)
	add_theme_color_override("guide_color",              color_guide)
	add_theme_color_override("relationship_line_color", color_guide)
	add_theme_color_override("drop_position_color",     Color(0.05, 0.44, 1.0, 1.0))

	add_theme_constant_override("item_margin",            indent_size)
	add_theme_constant_override("v_separation",            6)
	add_theme_constant_override("draw_guides",              1)
	add_theme_constant_override("draw_relationship_lines", 1)

func _flat_solid(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(2)
	return s

# =============================================================================
# API PÚBLICA — INTERFAZ CON EL SISTEMA DE CAPAS
# =============================================================================
func crear_item_studio(parent: TreeItem, nombre: String, tipo_nodo: String, referencia: Node) -> TreeItem:
	if not is_instance_valid(referencia):
		return null

	if parent == null:
		parent = get_root()
		if parent == null:
			return null

	var item : TreeItem = create_item(parent)
	if not item:
		return null

	item.set_cell_mode(COL_VIS,  TreeItem.CELL_MODE_CHECK)
	item.set_cell_mode(COL_NAME, TreeItem.CELL_MODE_STRING)
	item.set_cell_mode(COL_MASK, TreeItem.CELL_MODE_CHECK)

	item.set_text(COL_NAME,     nombre)
	item.set_editable(COL_NAME, true)
	item.set_editable(COL_VIS,  true)
	item.set_editable(COL_MASK, true)

	item.set_metadata(COL_NAME, referencia)
	item.set_metadata(COL_VIS,  tipo_nodo)

	_apply_identity_style(item, tipo_nodo)
	_evaluar_filtro(item)

	return item

func style_visibility(item: TreeItem, esta_visible: bool, tipo_nodo: String) -> void:
	if not is_instance_valid(item):
		return
	if not esta_visible:
		var dim : Color = color_artboard_dim if tipo_nodo == "artboard" else color_text_dim
		item.set_custom_color(COL_NAME, dim)
	else:
		_apply_identity_style(item, tipo_nodo)

func forzar_seleccion_desde_canvas(nodo_canvas: Node2D) -> void:
	var raiz : TreeItem = get_root()
	if not raiz or not is_instance_valid(nodo_canvas):
		return
	var encontrado : TreeItem = _buscar_por_nodo(raiz.get_first_child(), nodo_canvas)
	if encontrado:
		deselect_all()
		encontrado.select(COL_NAME)
		scroll_to_item(encontrado)

func reset_selection_state() -> void:
	_seleccion_previa = null

func actualizar_filtro_busqueda(nuevo_texto: String) -> void:
	_texto_filtro = nuevo_texto.strip_edges().to_lower()
	var raiz : TreeItem = get_root()
	if not raiz:
		return
	var it : TreeItem = raiz.get_first_child()
	while it:
		_filtrar_recursivo(it)
		it = it.get_next()

func colapsar_todos_los_grupos() -> void:
	_set_collapsed_all(true)

func expandir_todos_los_grupos() -> void:
	_set_collapsed_all(false)

# =============================================================================
# IDENTIDAD VISUAL POR TIPO DE CAPA
# =============================================================================
func _apply_identity_style(item: TreeItem, tipo: String) -> void:
	match tipo:
		"artboard":
			item.set_custom_bg_color(COL_VIS,  color_artboard_bg)
			item.set_custom_bg_color(COL_NAME, color_artboard_bg)
			item.set_custom_bg_color(COL_MASK, color_artboard_bg)
			item.set_custom_color(COL_NAME, color_artboard_text)
			item.set_selectable(COL_NAME, true)
		"group":
			item.clear_custom_bg_color(COL_VIS)
			item.clear_custom_bg_color(COL_NAME)
			item.clear_custom_bg_color(COL_MASK)
			item.set_custom_color(COL_NAME, color_group_text)
		_:
			item.clear_custom_bg_color(COL_VIS)
			item.clear_custom_bg_color(COL_NAME)
			item.clear_custom_bg_color(COL_MASK)
			item.set_custom_color(COL_NAME, color_text)

# =============================================================================
# FILTRADO DE BÚSQUEDA
# =============================================================================
func _evaluar_filtro(item: TreeItem) -> void:
	if _texto_filtro == "":
		item.set_visible(true)
		return
	item.set_visible(item.get_text(COL_NAME).to_lower().contains(_texto_filtro))

func _filtrar_recursivo(item: TreeItem) -> bool:
	if item == null:
		return false
	var coincide      : bool = _texto_filtro == "" or item.get_text(COL_NAME).to_lower().contains(_texto_filtro)
	var hijo_coincide : bool = false
	var hijo          : TreeItem = item.get_first_child()
	while hijo:
		if _filtrar_recursivo(hijo):
			hijo_coincide = true
		hijo = hijo.get_next()
	var es_visible : bool = coincide or hijo_coincide
	item.set_visible(es_visible)
	return es_visible

# =============================================================================
# INTERACCIÓN E INSPECTOR
# =============================================================================
func _on_item_selected_internal() -> void:
	var sel : TreeItem = get_selected()
	if not sel or sel == _seleccion_previa:
		return
	_seleccion_previa = sel

	var nodo : Node2D = sel.get_metadata(COL_NAME) as Node2D
	if is_instance_valid(nodo):
		item_selected_for_inspector.emit(nodo)
		var tipo : String = sel.get_metadata(COL_VIS) as String
		if tipo != "artboard":
			sel.set_custom_color(COL_NAME, color_select_text)

func _buscar_por_nodo(item: TreeItem, objetivo: Node2D) -> TreeItem:
	while item:
		if item.get_metadata(COL_NAME) == objetivo:
			return item
		var en_hijos : TreeItem = _buscar_por_nodo(item.get_first_child(), objetivo)
		if en_hijos:
			return en_hijos
		item = item.get_next()
	return null

func _set_collapsed_all(estado: bool) -> void:
	var raiz : TreeItem = get_root()
	if not raiz:
		return
	var it : TreeItem = raiz.get_first_child()
	while it:
		_colapsar_recursivo(it, estado)
		it = it.get_next()

func _colapsar_recursivo(item: TreeItem, estado: bool) -> void:
	if item == null:
		return
	var tipo : String = item.get_metadata(COL_VIS) as String
	if tipo == "group" or tipo == "artboard":
		item.collapsed = estado
	var hijo : TreeItem = item.get_first_child()
	while hijo:
		_colapsar_recursivo(hijo, estado)
		hijo = hijo.get_next()

# =============================================================================
# DRAG & DROP SEGURO CON REPARENTADO DE NODOS
# =============================================================================
func _get_drag_data(pos_mouse: Vector2) -> Variant:
	var item : TreeItem = get_item_at_position(pos_mouse)
	if not item:
		return null

	mouse_default_cursor_shape = Control.CURSOR_DRAG

	var panel := PanelContainer.new()
	var sb    := StyleBoxFlat.new()
	sb.bg_color          = Color(0.08, 0.08, 0.10, 0.92)
	sb.border_color      = Color(0.05, 0.44, 1.0, 1.0)
	sb.border_width_left = 3
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size  = 6
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = "    Moviendo: " + item.get_text(COL_NAME)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 12)
	panel.add_child(lbl)
	set_drag_preview(panel)

	deselect_all()
	item.select(COL_NAME)
	return item

func _can_drop_data(pos_mouse: Vector2, data: Variant) -> bool:
	if not (data is TreeItem):
		return false
	var destino : TreeItem = get_item_at_position(pos_mouse)
	if not destino or destino == data:
		return false

	var temp : TreeItem = destino.get_parent()
	while temp != null:
		if temp == data:
			return false
		temp = temp.get_parent()

	var tipo_origen : String = (data as TreeItem).get_metadata(COL_VIS) as String
	if tipo_origen == "artboard" and get_drop_section_at_position(pos_mouse) == 0:
		return false

	return true

func _drop_data(pos_mouse: Vector2, data: Variant) -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW

	var origen  : TreeItem = data as TreeItem
	var destino : TreeItem = get_item_at_position(pos_mouse)

	if not is_instance_valid(origen):
		return

	if not destino:
		var raiz   : TreeItem = get_root()
		var ultimo : TreeItem = raiz.get_first_child()
		if ultimo and ultimo != origen:
			while ultimo.get_next() and ultimo.get_next() != origen:
				ultimo = ultimo.get_next()
			if ultimo != origen:
				origen.move_after(ultimo)
		hierarchy_changed_by_user.emit()
		return

	var seccion : int = get_drop_section_at_position(pos_mouse)

	var nodo_origen  : Node2D = origen.get_metadata(COL_NAME)  as Node2D
	var nodo_destino : Node2D = destino.get_metadata(COL_NAME) as Node2D
	var nodos_validos : bool  = is_instance_valid(nodo_origen) and is_instance_valid(nodo_destino)

	# Soltar sobre el grupo raíz "Fuera de artboard" → la figura pasa a ser
	# SUELTA (hija directa del contenedor de artboards).
	if str(destino.get_metadata(COL_VIS)) == "sueltos":
		if is_instance_valid(nodo_origen):
			var cont := _contenedor_artboards()
			if is_instance_valid(cont) and nodo_origen.get_parent() != cont:
				nodo_origen.reparent(cont, true)
		hierarchy_changed_by_user.emit()
		return

	match seccion:
		0: # Soltar justo ENCIMA del ítem (reparentar hacia adentro)
			origen.move_after(destino)
			if nodos_validos and nodo_origen.get_parent() != nodo_destino:
				nodo_origen.reparent(nodo_destino)
			destino.collapsed = false

		-1: # Soltar en el borde SUPERIOR (mover antes)
			origen.move_before(destino)
			if nodos_validos:
				var padre_real : Node = nodo_destino.get_parent()
				if nodo_origen.get_parent() != padre_real:
					nodo_origen.reparent(padre_real)
				padre_real.move_child(nodo_origen, nodo_destino.get_index())

		1: # Soltar en el borde INFERIOR (mover después)
			origen.move_after(destino)
			if nodos_validos:
				var padre_real : Node = nodo_destino.get_parent()
				if nodo_origen.get_parent() != padre_real:
					nodo_origen.reparent(padre_real)
				padre_real.move_child(nodo_origen, nodo_destino.get_index() + 1)

	hierarchy_changed_by_user.emit()

## Contenedor de artboards de la escena viva (mismo patrón que LayerSystem).
func _contenedor_artboards() -> Node:
	var esc := get_tree().current_scene if get_tree() else null
	if esc:
		var c := esc.find_child("ArtboardsContainer", true, false)
		if c:
			return c
	# fallback: el padre del artboard ancestro del ítem seleccionado
	var sel := get_selected()
	if sel:
		var n = sel.get_metadata(COL_NAME)
		while is_instance_valid(n):
			if n is ArtboardEditor:
				return n.get_parent()
			n = n.get_parent()
	return null

# =============================================================================
# MENÚ CON CLIC DERECHO (CONTEXT MENU)
# =============================================================================
func _on_item_mouse_selected(pos_mouse: Vector2, boton: int) -> void:
	if boton == MOUSE_BUTTON_RIGHT:
		var item : TreeItem = get_item_at_position(pos_mouse)
		if item:
			item_right_clicked.emit(item, get_global_mouse_position())

# =============================================================================
# TECLADO Y NAVEGACIÓN AVANZADA (PANNING CON CLIC CENTRAL)
# =============================================================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_text_delete"):
		var sel : TreeItem = get_selected()
		if sel:
			var nodo : Node = sel.get_metadata(COL_NAME) as Node
			if is_instance_valid(nodo):
				print("Vectopen: Borrado por teclado → ", nodo.name)
				nodo.queue_free()
				hierarchy_changed_by_user.emit()
				get_viewport().set_input_as_handled()
		return

	if not _vscroll:
		_buscar_vscroll_nativo()

	var sobre_arbol : bool = get_global_rect().has_point(get_global_mouse_position())

	# Desplazamiento rápido con botón central del mouse (MMB)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and sobre_arbol:
			_arrastrando_scroll = true
			_ultima_pos_y = event.global_position.y
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			get_viewport().set_input_as_handled()
		elif not event.pressed and _arrastrando_scroll:
			_arrastrando_scroll = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _arrastrando_scroll:
		var delta : float = event.global_position.y - _ultima_pos_y
		if _vscroll and _vscroll.visible:
			_vscroll.value -= delta * velocidad_arrastre
		_ultima_pos_y = event.global_position.y
		get_viewport().set_input_as_handled()

func _buscar_vscroll_nativo() -> void:
	for child in get_children(true):
		if child is VScrollBar:
			_vscroll = child
			return
