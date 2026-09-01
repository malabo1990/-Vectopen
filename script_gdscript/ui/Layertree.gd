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
# IMPORTANTE: en un Tree multi-columna de Godot la SANGRÍA por nivel solo se
# aplica al contenido de la COLUMNA 0. Por eso el nombre + icono + flecha +
# líneas de jerarquía van todos en la columna 0 (COL_VIS); si no, los hijos no
# se ven desplazados a la derecha.
const COL_VIS  : int = 0  # Columna PRINCIPAL: flecha · líneas · sangría · icono · nombre
const COL_NAME : int = 1  # Slot de metadatos del NODO (sin contenido visible)
const COL_MASK : int = 2  # Botones de acción: ojo · candado · máscara

# ─── PROPIEDADES EXPORTADAS (ESTILO VECTOPEN) ─────────────────────────────
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

@export_group("Hover")
## Fila bajo el cursor = VERDE (no confundir con el azul de selección).
@export var color_hover_bg         : Color = Color(0.20, 0.78, 0.35, 0.18)

@export_group("Diseño")
## Sangría por nivel de anidamiento. Ajustada (estilo Figma/Sketch): lo justo
## para leer la jerarquía sin desperdiciar ancho.
@export var indent_size            : int   = 15

# ─── SEÑALES PÚBLICAS ─────────────────────────────────────────────────────────
signal item_right_clicked(item: TreeItem, position: Vector2)
signal item_selected_for_inspector(nodo: Node2D)
signal hierarchy_changed_by_user
## Navegación por teclado sobre la fila enfocada (las gestiona LayerSystem: la
## visibilidad y el agrupar/desagrupar necesitan undo real y el nodo real).
signal key_toggle_visibility(item: TreeItem)
signal key_group_request
signal key_ungroup_request

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
	# MULTI: seleccionar varias figuras en el lienzo marca varias filas a la vez.
	select_mode      = Tree.SELECT_MULTI
	# Necesario para la navegación por teclado (↑↓ nativo, ←→ plegar/desplegar,
	# Enter renombrar, Espacio visibilidad). El .tscn lo tenía en NONE.
	focus_mode       = Control.FOCUS_CLICK

	# Flag combinado: DROP_MODE_ON_ITEM (1) | DROP_MODE_IN_BETWEEN (2)
	drop_mode_flags  = 3

	# COL 0 = todo lo visible (flecha, líneas, sangría, icono, nombre). Expande.
	set_column_expand(COL_VIS,  true)
	set_column_clip_content(COL_VIS,  true)

	# COL 1 = solo almacena la referencia al nodo; sin ancho.
	set_column_custom_minimum_width(COL_NAME, 0)
	set_column_expand(COL_NAME, false)
	set_column_clip_content(COL_NAME, true)

	# COL 2 = los tres botones (ojo · candado · máscara), a la derecha. Las
	# columnas > 0 NO se ven afectadas por la sangría, así que aquí no se recortan.
	set_column_custom_minimum_width(COL_MASK, 74)
	set_column_expand(COL_MASK, false)
	set_column_clip_content(COL_MASK, false)

	_pull_theme_colors()
	_apply_theme()

	# Seguir el tema global (tokens de diseño) en vez de colores fijos.
	var tm = _theme_manager()
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)

	item_mouse_selected.connect(_on_item_mouse_selected)
	item_selected.connect(_on_item_selected_internal)
	# Al interactuar con una fila, el árbol toma el foco de teclado para que
	# funcionen ↑↓←→ / Enter / Espacio / Ctrl+G sin un clic extra.
	item_mouse_selected.connect(func(_p, _b): grab_focus())
	multi_selected.connect(func(_i, _c, _s): grab_focus())

	call_deferred("_buscar_vscroll_nativo")

func _theme_manager():
	var st := Engine.get_main_loop() as SceneTree
	return st.root.get_node_or_null("ThemeManager") if st else null

func _on_theme_changed(_mode: String) -> void:
	_pull_theme_colors()
	_apply_theme()
	queue_redraw()

## Rellena los @export de color desde ThemeManager (si está). Así el árbol usa
## los tokens de diseño y responde al cambio claro/oscuro.
func _pull_theme_colors() -> void:
	var tm = _theme_manager()
	if tm == null:
		return
	var S = tm.Slot
	color_bg            = tm.get_color(S.PANEL_SURFACE)
	color_text          = tm.get_color(S.PANEL_TEXT)
	color_text_dim      = tm.get_color(S.TEXT_DISABLED)
	color_select_bg     = Color(tm.get_color(S.ACCENT), 0.20)   # azul claro
	color_select_text   = tm.get_color(S.PANEL_TEXT)
	color_focus_bg      = Color(tm.get_color(S.ACCENT), 0.14)
	color_artboard_bg   = tm.get_color(S.PANEL_BG)
	color_artboard_text = tm.get_color(S.PANEL_TEXT)
	color_artboard_dim  = tm.get_color(S.TEXT_DISABLED)
	color_group_text    = tm.get_color(S.ACCENT)
	color_guide         = tm.get_color(S.BORDER)
	color_hover_bg      = Color(tm.get_color(S.AFFIRMATIVE), 0.20)   # verde claro

# =============================================================================
# TEMA VISUAL (INTERFAZ ELEGANTE COMPACTA)
# =============================================================================
func _apply_theme() -> void:
	add_theme_stylebox_override("panel",          _flat_solid(color_bg, 0))
	add_theme_stylebox_override("bg",              _flat_solid(color_bg, 0))
	add_theme_stylebox_override("bg_focus",       _flat_solid(color_bg, 0))
	# Fila SELECCIONADA: relleno azul + borde AZUL (mismo tono). Nada de negro
	# — confundía con las líneas de jerarquía.
	var sel_sb := _flat_solid(color_select_bg, 4)
	sel_sb.set_border_width_all(1)
	sel_sb.border_color = Color(color_group_text, 0.9)   # color_group_text = ACCENT (azul)
	add_theme_stylebox_override("selected",       sel_sb)
	add_theme_stylebox_override("selected_focus", sel_sb)
	add_theme_stylebox_override("cursor",         _flat_solid(Color(0, 0, 0, 0), 4))
	add_theme_stylebox_override("cursor_unfocused", _flat_solid(Color(0, 0, 0, 0), 4))
	# Fila bajo el cursor (hover) = VERDE · fila seleccionada = AZUL. Colores
	# bien distintos para no confundirse.
	add_theme_stylebox_override("hovered",          _flat_solid(color_hover_bg, 4))
	var hov_dim := color_hover_bg
	hov_dim.a *= 0.5
	add_theme_stylebox_override("hovered_dimmed",   _flat_solid(hov_dim, 4))
	add_theme_stylebox_override("hovered_selected", sel_sb)
	add_theme_stylebox_override("hovered_selected_focus", sel_sb)

	var drop_style := StyleBoxFlat.new()
	drop_style.bg_color     = Color(0.05, 0.44, 1.0, 0.08)
	drop_style.border_color = Color(0.05, 0.44, 1.0, 0.85)
	drop_style.set_border_width_all(1)
	drop_style.set_corner_radius_all(3)
	add_theme_stylebox_override("drop_zone", drop_style)

	add_theme_color_override("font_color",              color_text)
	add_theme_color_override("font_selected_color",     color_select_text)
	add_theme_color_override("guide_color",              color_guide)
	# Líneas de jerarquía: GRIS CASI BLANCO, muy finas. No hay línea azul de
	# "rama seleccionada" (parent_hl/children_hl) — confundía con la selección:
	# se ponen del MISMO gris que las normales.
	var linea_jer := Color(0.87, 0.87, 0.90, 1.0)
	add_theme_color_override("relationship_line_color", linea_jer)
	add_theme_color_override("parent_hl_line_color",    linea_jer)
	add_theme_color_override("children_hl_line_color",  linea_jer)
	add_theme_color_override("drop_position_color",     Color(0.0, 0.478, 1.0, 1.0))

	# Espaciado ajustado y elegante (estilo Figma/Sketch): filas juntas, sangría
	# corta.
	add_theme_constant_override("item_margin",            indent_size)   # px/nivel de sangría
	add_theme_constant_override("v_separation",             3)   # filas juntas
	add_theme_constant_override("h_separation",             4)
	add_theme_constant_override("inner_item_margin_left",   4)
	add_theme_constant_override("button_margin",            2)
	add_theme_constant_override("icon_max_width",          16)
	add_theme_constant_override("draw_guides",              0)
	add_theme_constant_override("draw_relationship_lines", 1)
	add_theme_constant_override("relationship_line_width",  1)
	add_theme_constant_override("parent_hl_line_width",     1)
	add_theme_constant_override("children_hl_line_width",   1)

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
	item.set_visible(_fila_coincide_filtro(item))

## Filtro por texto o por ficha rápida: `is:oculto`, `is:bloqueado`, `is:grupo`,
## `is:texto`, `is:imagen`, `is:seleccionado`. El resto se trata como subcadena
## del nombre.
func _fila_coincide_filtro(item: TreeItem) -> bool:
	if _texto_filtro == "":
		return true
	if _texto_filtro.begins_with("is:") or _texto_filtro.begins_with("es:"):
		var clave := _texto_filtro.substr(3)
		var nodo = item.get_metadata(COL_NAME)
		var tipo := str(item.get_metadata(COL_VIS))
		match clave:
			"oculto", "hidden":      return is_instance_valid(nodo) and not bool(nodo.visible)
			"bloqueado", "locked":   return is_instance_valid(nodo) and bool(nodo.get_meta("locked", false))
			"grupo", "group":        return tipo == "group" or tipo == "artboard"
			"texto", "text":         return tipo.begins_with("text")
			"imagen", "image":       return nodo is Sprite2D
			"seleccionado", "selected": return item.is_selected(COL_VIS)
			_:                       return false
	return item.get_text(COL_VIS).to_lower().contains(_texto_filtro)

func _filtrar_recursivo(item: TreeItem) -> bool:
	if item == null:
		return false
	var coincide      : bool = _fila_coincide_filtro(item)
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
		# El realce de selección lo dibuja el stylebox "selected"; NO tocamos el
		# color de texto de la fila (antes lo forzaba a blanco de forma
		# permanente y quedaba invisible sobre el tema claro al deseleccionar).

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
## Nodos a arrastrar: si la fila bajo el cursor está en la multiselección,
## se arrastra TODA la selección; si no, solo esa fila. Se descartan los
## nodos cuyo ancestro también se arrastra (no tiene sentido moverlos aparte).
func _nodos_para_arrastrar(item: TreeItem) -> Array:
	var items: Array = []
	if item.is_selected(COL_VIS) and get_next_selected(null) != null:
		var it: TreeItem = get_next_selected(null)
		while it != null:
			items.append(it)
			it = get_next_selected(it)
		if item not in items:
			items.append(item)
	else:
		items = [item]
	var nodos: Array = []
	for i in items:
		var n = i.get_metadata(COL_NAME)
		if n is Node2D and is_instance_valid(n):
			nodos.append(n)
	# quitar descendientes de otros nodos ya en la lista
	var top: Array = []
	for n in nodos:
		var anc: Node = n.get_parent()
		var cubierto := false
		while anc != null:
			if anc in nodos:
				cubierto = true
				break
			anc = anc.get_parent()
		if not cubierto:
			top.append(n)
	return top

func _get_drag_data(pos_mouse: Vector2) -> Variant:
	var item : TreeItem = get_item_at_position(pos_mouse)
	if not item:
		return null
	var nodos := _nodos_para_arrastrar(item)
	if nodos.is_empty():
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
	lbl.text = ("    Moviendo %d capas" % nodos.size()) if nodos.size() > 1 \
		else ("    Moviendo: " + str(item.get_text(COL_VIS)))
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 12)
	panel.add_child(lbl)
	set_drag_preview(panel)

	# NO devolver el `TreeItem` en `data`: la re-sincronización del panel tras el
	# drop hace `layer_tree.clear()` y lo libera; si el sistema de drag de Godot
	# aún lo retiene, quedan referencias colgantes → segundo arrastre bloqueado.
	# Solo se necesitan los NODOS reales (sobreviven al clear).
	return {"nodes": nodos}

func _drag_nodes(data: Variant) -> Array:
	if data is Dictionary and data.has("nodes"):
		return data["nodes"]
	if data is TreeItem:   # compat
		var n = (data as TreeItem).get_metadata(COL_NAME)
		return [n] if n is Node2D else []
	return []

func _can_drop_data(pos_mouse: Vector2, data: Variant) -> bool:
	var nodos := _drag_nodes(data)
	if nodos.is_empty():
		return false
	var destino : TreeItem = get_item_at_position(pos_mouse)
	if not destino:
		return false
	var nodo_destino = destino.get_metadata(COL_NAME)
	# El propio destino puede venir en la multiselección arrastrada (SELECT_MULTI
	# + sync lienzo↔panel dejan filas seleccionadas). Se excluye: arrastrar la
	# fila A sobre la fila B mueve el RESTO a B, no bloquea el drop. Sin esto,
	# meter una capa dentro de otra ya-seleccionada fallaba siempre.
	var efectivos := _nodos_efectivos(nodos, nodo_destino)
	if efectivos.is_empty():
		return false
	# El destino no puede DESCENDER de ninguno de los arrastrados efectivos.
	var anc: Node = nodo_destino if nodo_destino is Node else null
	while anc != null:
		if anc in efectivos:
			return false
		anc = anc.get_parent()
	# Un artboard no puede meterse DENTRO de otra fila.
	var seccion := _seccion_drop(pos_mouse, destino)
	if seccion == 0:
		for n in efectivos:
			if n is ArtboardEditor or (n is Node2D and "artboard_size" in n):
				return false
	return true

## Zona de drop robusta: -1 (encima, antes) · 0 (DENTRO) · 1 (debajo, después).
## `Tree.get_drop_section_at_position()` devuelve **-100** cuando no puede
## determinarla (fuera de un drag OS real, tras `clear()`, drop_mode raro…), y
## entonces `_drop_data` trataba TODO drop como "hermano" → nunca anidaba y
## SACABA las figuras al artboard. Si el motor no lo sabe, lo calculamos a mano
## desde el rectángulo de la fila: 30 % arriba / 30 % abajo = entre; 40 % centro
## = DENTRO.
func _seccion_drop(pos_mouse: Vector2, item: TreeItem) -> int:
	var s := get_drop_section_at_position(pos_mouse)
	if s >= -1 and s <= 1:
		return s
	# El motor no lo sabe (-100). Lo calculamos desde el rect de la fila.
	if not is_instance_valid(item):
		return 0
	return _seccion_por_rect(pos_mouse.y, get_item_area_rect(item, COL_VIS))

## -1 / 0 / 1 según en qué tercio (30/40/30) de `rect` cae la `y`. Puro y testeable.
static func _seccion_por_rect(y: float, rect: Rect2) -> int:
	if rect.size.y <= 0.0:
		return 0
	var f: float = (y - rect.position.y) / rect.size.y
	if f < 0.30:
		return -1
	if f > 0.70:
		return 1
	return 0

## `nodos` sin el `destino` ni sus descendientes: lo que de verdad se reparenta.
func _nodos_efectivos(nodos: Array, destino: Variant) -> Array:
	if not (destino is Node):
		return nodos.duplicate()
	var out: Array = []
	for n in nodos:
		if not (n is Node) or not is_instance_valid(n):
			continue
		if n == destino:
			continue
		var a: Node = n
		var es_ancestro_o_destino := false
		while a != null:
			if a == destino:
				es_ancestro_o_destino = true
				break
			a = a.get_parent()
		if not es_ancestro_o_destino:
			out.append(n)
	return out

func _drop_data(pos_mouse: Vector2, data: Variant) -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	var nodos := _drag_nodes(data)
	if nodos.is_empty():
		return
	var destino : TreeItem = get_item_at_position(pos_mouse)
	if not destino:
		return

	# Resolver (padre destino, índice de inserción) según la zona de drop.
	var seccion := _seccion_drop(pos_mouse, destino)
	var nodo_destino = destino.get_metadata(COL_NAME)
	var efectivos := _nodos_efectivos(nodos, nodo_destino)
	if efectivos.is_empty():
		return
	var dest_parent: Node = null
	var dest_index: int = -1

	if str(destino.get_metadata(COL_VIS)) == "sueltos":
		dest_parent = _contenedor_artboards()
		dest_index = dest_parent.get_child_count() if is_instance_valid(dest_parent) else -1
	elif seccion == 0 and is_instance_valid(nodo_destino):
		# Soltar ENCIMA → hijo del destino (al final).
		dest_parent = nodo_destino
		dest_index = nodo_destino.get_child_count()
		destino.collapsed = false
	elif is_instance_valid(nodo_destino) and is_instance_valid(nodo_destino.get_parent()):
		dest_parent = nodo_destino.get_parent()
		dest_index = nodo_destino.get_index() + (1 if seccion >= 0 else 0)

	if not is_instance_valid(dest_parent):
		return
	var _dc := get_node_or_null("/root/DebugConsola")
	if _dc and _dc.has_method("evento"):
		var noms: Array = []
		for n in efectivos:
			if is_instance_valid(n): noms.append(n.name)
		var _dn := str(dest_parent.name) if is_instance_valid(dest_parent) else "?"
		_dc.evento("drop", "%s → %s  (sección %d, idx %d)" % [str(noms), _dn, seccion, dest_index])
	mover_capas(efectivos, dest_parent, dest_index)

## Reparenta `nodos` bajo `dest_parent` a partir de `dest_index`, conservando
## el transform global, como UNA acción de undo. Reutilizable desde tests y
## desde otras acciones (extraer del padre, etc.).
func mover_capas(nodos: Array, dest_parent: Node, dest_index: int) -> void:
	if nodos.is_empty() or not is_instance_valid(dest_parent):
		return
	var antes: Array = []
	for n in nodos:
		if is_instance_valid(n):
			antes.append({"n": n, "p": n.get_parent(), "i": n.get_index(),
				"gt": (n as Node2D).global_transform})
	var orden := nodos.duplicate()
	orden.sort_custom(func(a, b): return a.get_index() < b.get_index())

	var mover_a := func(dest: Node, base_idx: int) -> void:
		var ins := base_idx
		var _dc := get_node_or_null("/root/DebugConsola")
		for n in orden:
			if not (is_instance_valid(n) and is_instance_valid(dest)):
				continue
			var gt: Transform2D = (n as Node2D).global_transform
			if n.get_parent() != dest:
				if _dc and _dc.has_method("evento"):
					var _p0 := str(n.get_parent().name) if is_instance_valid(n.get_parent()) else "?"
					_dc.evento("reparent", "%s: %s → %s" % [str(n.name), _p0, str(dest.name)])
				n.reparent(dest, true)
			dest.move_child(n, clampi(ins, 0, dest.get_child_count() - 1))
			(n as Node2D).global_transform = gt
			ins = n.get_index() + 1
		hierarchy_changed_by_user.emit()

	var deshacer := func() -> void:
		var e2 := antes.duplicate()
		e2.sort_custom(func(a, b): return a["i"] > b["i"])
		for e in e2:
			var n = e["n"]
			if is_instance_valid(n) and is_instance_valid(e["p"]):
				if n.get_parent() != e["p"]:
					n.reparent(e["p"], true)
				e["p"].move_child(n, clampi(e["i"], 0, e["p"].get_child_count() - 1))
				(n as Node2D).global_transform = e["gt"]
		hierarchy_changed_by_user.emit()

	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Reordenar capas" if nodos.size() == 1 else "Mover %d capas" % nodos.size())
		hm.add_do(mover_a.bind(dest_parent, dest_index))
		hm.add_undo(deshacer)
		hm.commit()
	mover_a.call(dest_parent, dest_index)

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
		# `pos_mouse` (local al Tree) puede ser poco fiable con eventos
		# sintéticos; se cae a la fila seleccionada por el propio clic derecho.
		var item : TreeItem = get_item_at_position(pos_mouse)
		if item == null:
			item = get_selected()
		if item == null:
			return
		# Posición del menú: esquina del área de la fila, en coords de pantalla.
		var area := get_item_area_rect(item, COL_VIS)
		var origen := get_screen_position() + area.position + Vector2(area.size.x * 0.4, area.size.y)
		item_right_clicked.emit(item, origen)

# =============================================================================
# TECLADO Y NAVEGACIÓN AVANZADA (PANNING CON CLIC CENTRAL)
# =============================================================================
func _input(event: InputEvent) -> void:
	# SOLO si el árbol de capas tiene el foco de teclado. Antes interceptaba
	# CUALQUIER pulsación de Suprimir en toda la app y hacía nodo.queue_free()
	# sin undo ni sincronizar la selección → pérdida de datos irreversible, y
	# además impedía que Suprimir llegara al canvas (que sí borra con undo).
	if event.is_action_pressed("ui_text_delete") and has_focus():
		var sel : TreeItem = get_selected()
		if sel:
			var nodo = sel.get_metadata(COL_NAME)
			if is_instance_valid(nodo) and nodo is Node:
				_borrar_nodo_con_undo(nodo)
				get_viewport().set_input_as_handled()
		return

	# Navegación por teclado (solo con el árbol enfocado). ↑↓ y ←→ los gestiona
	# el propio Tree de forma nativa; aquí sumamos Enter / Espacio / Ctrl+G.
	if has_focus() and event is InputEventKey and event.pressed and not event.echo:
		var sel2 : TreeItem = get_selected()
		var kc: int = event.keycode if event.keycode != 0 else event.physical_keycode
		match kc:
			KEY_ENTER, KEY_KP_ENTER:
				if sel2:
					edit_selected(true)
					get_viewport().set_input_as_handled()
					return
			KEY_SPACE:
				if sel2:
					key_toggle_visibility.emit(sel2)
					get_viewport().set_input_as_handled()
					return
			KEY_G:
				if event.ctrl_pressed or event.meta_pressed:
					if event.shift_pressed:
						key_ungroup_request.emit()
					else:
						key_group_request.emit()
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

## Borra el nodo seleccionado en el árbol registrando una acción de undo
## (detach + guardar padre/índice; no queue_free para poder restaurarlo).
func _borrar_nodo_con_undo(nodo: Node) -> void:
	var padre := nodo.get_parent()
	if not is_instance_valid(padre):
		return
	var idx := nodo.get_index()
	var do_fn := func() -> void:
		if is_instance_valid(nodo) and is_instance_valid(nodo.get_parent()):
			nodo.get_parent().remove_child(nodo)
	var undo_fn := func() -> void:
		if is_instance_valid(nodo) and is_instance_valid(padre) and nodo.get_parent() == null:
			padre.add_child(nodo)
			padre.move_child(nodo, mini(idx, padre.get_child_count() - 1))
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Eliminar del panel de capas")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
	hierarchy_changed_by_user.emit()


func _buscar_vscroll_nativo() -> void:
	for child in get_children(true):
		if child is VScrollBar:
			_vscroll = child
			return
