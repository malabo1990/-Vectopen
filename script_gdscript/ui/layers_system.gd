# =============================================================================
# VECTOPEN STUDIO — LAYER SYSTEM (CORE BACKEND)
# ARCHIVO: res://script_gdscript/layers_system.gd
# MODALIDAD: @tool
# =============================================================================
@tool
extends Node
class_name LayerSystem

# ─── REFERENCIAS DE ARQUITECTURA ──────────────────────────────────────────────
@export_group("Componentes Core")
@export var layer_tree         : Tree      # Componente UI LayerTree
@export var artboard_container : Node2D    # ArtboardsContainer de canvas.tscn

# ─── ESTADO OPERATIVO INTERNO ─────────────────────────────────────────────────
var _bloquear_sincronizacion : bool = false
var _artboards_conectados    : Array[Node2D] = []
var _update_timer           : Timer = null
var _watchdog_timer         : Timer = null
var _watchdog_ticks_bloqueado : int = 0
var _pending_changes        : Array[Dictionary] = []
var _node_to_item_map       : Dictionary = {}  # Mapeo nodo → TreeItem

## Label "Numer layer" del panel (layout.tscn): muestra el nº total de
## elementos dibujables dentro de los artboards — útil para ver de un vistazo
## contra cuántas figuras estás trabajando (rendimiento).
var _contador_label : Label = null

## Item raíz sintético que agrupa las figuras SUELTAS (hijas directas del
## contenedor, fuera de todo artboard). Solo existe si hay alguna. Así el panel
## refleja exactamente lo que un editor profesional: lo que está fuera de un
## artboard se ve fuera de un artboard, no colgando como si fuera un artboard.
const SUELTOS_LABEL := "Fuera de artboard"
var _sueltos_item : TreeItem = null

## Iconos de las acciones por fila (ojo, candado, máscara de recorte), escalados
## a 16 px para que las filas del panel de capas sean compactas.
const _ICON_PX := 16
static var _icon_cache: Dictionary = {}

static func _icon(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var src: Texture2D = load(path)
	var tex: Texture2D = src
	if src:
		var img := src.get_image()
		if img:
			img.resize(_ICON_PX, _ICON_PX, Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
	_icon_cache[path] = tex
	return tex

## Icono BLANCO (mismo alfa, píxeles a blanco). Necesario para los botones de
## fila cuyo color pone `set_button_color` (modulate MULTIPLICA: un icono negro
## no se puede ACLARAR, uno blanco se tiñe a cualquier tono → negro cuando está
## activado, gris casi blanco cuando no).
static func _icon_blanco(path: String) -> Texture2D:
	var clave := path + "#blanco"
	if _icon_cache.has(clave):
		return _icon_cache[clave]
	var src: Texture2D = load(path)
	var tex: Texture2D = src
	if src:
		var img := src.get_image()
		if img:
			img.resize(_ICON_PX, _ICON_PX, Image.INTERPOLATE_LANCZOS)
			img.convert(Image.FORMAT_RGBA8)
			for y in img.get_height():
				for x in img.get_width():
					var a := img.get_pixel(x, y).a
					if a > 0.0:
						img.set_pixel(x, y, Color(1, 1, 1, a))
			tex = ImageTexture.create_from_image(img)
	_icon_cache[clave] = tex
	return tex

static var _ICON_EYE: Texture2D = _icon_blanco("res://icon/UI/eye.svg")
static var _ICON_EYE_OFF: Texture2D = _icon_blanco("res://icon/UI/eye-off.svg")
static var _ICON_LOCK: Texture2D = _icon_blanco("res://icon/UI/lock.svg")
static var _ICON_LOCK_OPEN: Texture2D = _icon_blanco("res://icon/UI/lock-slash.svg")
static var _CLIP_ICON: Texture2D = _icon_blanco("res://icon/UI/exclude.svg")             # máscara ACTIVA (dos formas solapadas)
static var _CLIP_ICON_OFF: Texture2D = _icon_blanco("res://icon/UI/frame-alt-empty.svg") # máscara INACTIVA (marco vacío)

## Icono por tipo de capa en la columna del nombre (como un editor profesional).
const _TYPE_ICON_PATHS := {
	"rect": "res://icon/UI/square.svg",
	"circle": "res://icon/UI/circle-spark.svg",
	"triangle": "res://icon/UI/triangle.svg",
	"pentagon": "res://icon/UI/pentagon.svg",
	"star": "res://icon/UI/star.svg",
	"polygon": "res://icon/UI/hexagon.svg",
	"path": "res://icon/UI/pen.svg",
	"text": "res://icon/UI/text-square.svg",
	"image": "res://icon/UI/media-image.svg",
	"group": "res://icon/UI/folder.svg",
	"artboard": "res://icon/UI/frame-alt.svg",
	"shape": "res://icon/UI/frame-alt-empty.svg",
}
static var _type_icons: Dictionary = {}

static func _type_icon(clave: String) -> Texture2D:
	if _type_icons.has(clave):
		return _type_icons[clave]
	var path: String = _TYPE_ICON_PATHS.get(clave, _TYPE_ICON_PATHS["shape"])
	var tex := _icon(path)
	_type_icons[clave] = tex
	return tex

func _clave_icono(nodo: Node, tipo: String) -> String:
	if tipo == "artboard":
		return "artboard"
	if tipo == "group":
		return "group"
	if String(tipo).begins_with("text"):
		return "text"
	if nodo is Sprite2D:
		return "image"
	if nodo is Path2D:
		return "path"
	if nodo is Line2D:
		return "path"
	var cls: String = nodo.get_class() if is_instance_valid(nodo) else ""
	var scr = nodo.get_script() if is_instance_valid(nodo) else null
	var scr_path: String = ""
	if scr != null:
		scr_path = String(scr.resource_path).to_lower()
	for k in ["rect", "circle", "triangle", "pentagon", "star", "polygon"]:
		if scr_path.contains(k):
			return k
	if cls == "Polygon2D":
		return "polygon"
	return "shape"

## IDs de botón por fila.
const _BTN_VIS  := 1
const _BTN_LOCK := 2
const _BTN_CLIP := 3
## Modo de recorte que activa el botón (recorta + dibuja la propia forma).
const _CLIP_ON := 2   # CanvasItem.CLIP_CHILDREN_AND_DRAW

# =============================================================================
# INICIALIZACIÓN Y CONEXIONES DE SEÑALES
# =============================================================================
func _ready() -> void:
	# Localizar componentes automáticamente en la escena viva si quedan null
	if not layer_tree:
		var escena_activa = get_tree().current_scene
		if escena_activa:
			layer_tree = escena_activa.find_child("LayerTree", true, false) as Tree
			if not layer_tree:
				layer_tree = escena_activa.find_child("Tree", true, false) as Tree

	if not artboard_container:
		var escena_activa = get_tree().current_scene
		if escena_activa:
			artboard_container = escena_activa.find_child("ArtboardsContainer", true, false) as Node2D

	var escena := get_tree().current_scene
	if escena:
		_contador_label = escena.find_child("Numer layer", true, false) as Label

	_conectar_botones()
	_aplicar_tema_panel()

	# Botones por fila (máscara de recorte) → toggle con undo.
	if is_instance_valid(layer_tree) and not layer_tree.button_clicked.is_connected(_on_tree_button_clicked):
		layer_tree.button_clicked.connect(_on_tree_button_clicked)

	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)

	# Crear timer para actualizaciones batch
	_setup_update_timer()

	_crear_menu_contextual()

	conectar_senales_sistema()
	sincronizar_arbol_completo()

	var _dc := get_node_or_null("/root/DebugConsola")
	if _dc and _dc.has_method("registrar_layersystem"):
		_dc.registrar_layersystem(self)

## Ctrl+G / Ctrl+Shift+G desde CUALQUIER sitio (como el árbol de escena de
## Godot), no solo con el panel de capas enfocado. `_unhandled_key_input` solo
## salta si nadie más consumió la tecla.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kc: int = event.keycode if event.keycode != 0 else event.physical_keycode
	# F9 = volcado de diagnóstico del árbol (para verificación con MCP en vivo).
	if kc == KEY_F9:
		_volcar_diagnostico()
		get_viewport().set_input_as_handled()
		return
	if kc != KEY_G or not (event.ctrl_pressed or event.meta_pressed):
		return
	var fo = get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is TextEdit:
		return
	if event.shift_pressed:
		_desagrupar_seleccion()
	else:
		_agrupar_seleccion()
	get_viewport().set_input_as_handled()

## Escribe en el log el estado REAL del árbol: por cada fila, su profundidad,
## la x del área del nombre (prueba de la sangría), el tipo y cuántos botones
## tiene. Además, la selección viva. Se dispara con F9.
func _volcar_diagnostico() -> void:
	var rt := get_node_or_null("/root/MCPRuntime")
	var log_fn := func(s: String) -> void:
		if rt and rt.has_method("push_runtime_log"):
			rt.push_runtime_log("info", s)
		print(s)
	log_fn.call("── DIAGNÓSTICO PANEL DE CAPAS ──")
	if not is_instance_valid(layer_tree):
		log_fn.call("  layer_tree NULL"); return
	log_fn.call("  columnas=%d  select_mode=%d  focus_mode=%d" % [
		layer_tree.columns, layer_tree.select_mode, layer_tree.focus_mode])
	var raiz: TreeItem = layer_tree.get_root()
	if raiz == null:
		log_fn.call("  root NULL"); return
	_volcar_item(raiz.get_first_child(), 0, layer_tree, log_fn)
	var sm := get_node_or_null("/root/SelectionManager")
	if sm:
		var nombres: Array = []
		for n in sm.get_selected():
			nombres.append(String(n.name) if is_instance_valid(n) else "?")
		log_fn.call("  SELECCIÓN VIVA: %s" % str(nombres))
	log_fn.call("────────────────────────────────")

func _volcar_item(it: TreeItem, prof: int, tree: Tree, log_fn: Callable) -> void:
	while it != null:
		var area: Rect2 = tree.get_item_area_rect(it, 0)
		var nbtn := it.get_button_count(2)
		var sel := " [SEL]" if it.is_selected(0) else ""
		log_fn.call("  %s%s  prof=%d  nombre.x=%.0f  tipo=%s  botones=%d%s" % [
			"    ".repeat(prof), it.get_text(0), prof, area.position.x,
			str(it.get_metadata(0)), nbtn, sel])
		_volcar_item(it.get_first_child(), prof + 1, tree, log_fn)
		it = it.get_next()

func _on_theme_changed(_mode: String) -> void:
	_aplicar_tema_panel()

# =============================================================================
# TEMA DEL PANEL — usa los tokens de diseño (ThemeManager), sin blancos/negros fijos
# =============================================================================
func _aplicar_tema_panel() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var S = tm.Slot

	var panel := get_node_or_null("Panel") as Panel
	if panel == null:
		panel = find_child("Panel", false, false) as Panel
	if panel:
		# Estilo Apple: SIN marco y SIN sombra, esquinas redondeadas y márgenes
		# internos generosos para que el título "LAYERS" y el contenido respiren.
		var sb := StyleBoxFlat.new()
		sb.bg_color = tm.get_color(S.PANEL_SURFACE)
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(0)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		panel.add_theme_stylebox_override("panel", sb)

	# Más aire entre título / buscador / botones / árbol.
	var vbox := find_child("VBoxContainer", false, false)
	if vbox == null:
		vbox = panel.get_node_or_null("VBoxContainer") if is_instance_valid(panel) else null
	if vbox:
		vbox.add_theme_constant_override("separation", 10)

	var title := find_child("Title", true, false) as Label
	if title:
		title.add_theme_color_override("font_color", tm.get_color(S.TEXT_SECONDARY))
		title.remove_theme_stylebox_override("normal")
		title.add_theme_font_size_override("font_size", 12)

	var barra := find_child("ButtonsBar", true, false)
	if barra:
		if barra is HBoxContainer:
			barra.add_theme_constant_override("separation", 6)
		# Cada icono va DENTRO de un botón visible: chip gris claro redondeado
		# (estilo Apple), sin borde. Se ve al pasar el ratón y al pulsar.
		var chip: Color = tm.get_color(S.INPUT_BG)
		var hov: Color = tm.get_color(S.BUTTON_HOVER)
		var prs: Color = tm.get_color(S.BUTTON_PRESSED)
		var txt: Color = tm.get_color(S.BUTTON_TEXT)
		for b in barra.get_children():
			if b is Button:
				b.custom_minimum_size = Vector2(28, 28)
				b.add_theme_color_override("font_color", txt)
				b.add_theme_stylebox_override("normal", _chip_sb(chip))
				b.add_theme_stylebox_override("hover", _chip_sb(hov))
				b.add_theme_stylebox_override("pressed", _chip_sb(prs))

	var buscador := find_child("SearchLayers", true, false) as LineEdit
	if buscador:
		var inp := _btn_sb(tm.get_color(S.INPUT_BG), tm.get_color(S.INPUT_BORDER))
		inp.set_content_margin_all(6)
		buscador.add_theme_stylebox_override("normal", inp)
		var inp_foco := _btn_sb(tm.get_color(S.INPUT_BG), tm.get_color(S.ACCENT))
		inp_foco.set_content_margin_all(6)
		buscador.add_theme_stylebox_override("focus", inp_foco)
		buscador.add_theme_color_override("font_color", tm.get_color(S.PANEL_TEXT))
		buscador.add_theme_color_override("font_placeholder_color", tm.get_color(S.TEXT_DISABLED))
		buscador.add_theme_color_override("caret_color", tm.get_color(S.PANEL_TEXT))
		buscador.add_theme_font_size_override("font_size", 12)

func _btn_sb(c: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = border
	s.set_content_margin_all(4)
	return s

## Chip de botón estilo Apple: relleno suave, esquinas 7 px, sin borde.
func _chip_sb(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(7)
	s.content_margin_left = 5
	s.content_margin_right = 5
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## Los botones de la barra del panel (+, +A, -, D, M, G) no tenían NINGUNA
## señal conectada en la .tscn → no hacían nada. Los cableamos por código.
func _conectar_botones() -> void:
	var barra := get_node_or_null("Panel/VBoxContainer/ButtonsBar")
	if not barra:
		barra = find_child("ButtonsBar", true, false)
	if not barra:
		return
	# + = capa/grupo nuevo vacío · +A = artboard · - = borrar
	# D = duplicar · G = agrupar selección · M = desagrupar
	var mapa := {
		"AddLayer": _on_btn_add_group,
		"AddLayerArtboard": _on_btn_add_artboard,
		"DeleteLayer": _eliminar_seleccion,
		"DuplicateLayer": _duplicar_seleccion,
		"GroupLayer": _agrupar_seleccion,
		"MergeLayer": _desagrupar_seleccion,
	}
	for nombre in mapa:
		var b := barra.get_node_or_null(nombre) as Button
		if b and not b.pressed.is_connected(mapa[nombre]):
			b.pressed.connect(mapa[nombre])
	# Iconos + tooltips (se entienden mejor que las letras +/+A/-/D/M/G).
	_icono_boton(barra, "AddLayer", "res://icon/UI/plus-square-dashed.svg", "Nuevo grupo/capa (vacío)")
	_icono_boton(barra, "AddLayerArtboard", "res://icon/UI/frame-plus-in.svg", "Nuevo artboard")
	_icono_boton(barra, "DeleteLayer", "res://icon/UI/trash.svg", "Eliminar selección")
	_icono_boton(barra, "DuplicateLayer", "res://icon/UI/copy.svg", "Duplicar selección")
	_icono_boton(barra, "GroupLayer", "res://icon/UI/folder.svg", "Agrupar selección (Ctrl+G)")
	_icono_boton(barra, "MergeLayer", "res://icon/UI/arrow-separate.svg", "Desagrupar (Ctrl+Shift+G)")

	# Buscador de capas → filtra el árbol (nombre o fichas is:oculto / is:grupo /
	# is:texto / is:imagen / is:bloqueado / is:seleccionado). El filtro ya está
	# implementado en Layertree.actualizar_filtro_busqueda; aquí solo lo cableamos.
	var buscador := find_child("SearchLayers", true, false) as LineEdit
	if is_instance_valid(buscador) and not buscador.text_changed.is_connected(_on_buscar_capas):
		buscador.text_changed.connect(_on_buscar_capas)

func _on_buscar_capas(texto: String) -> void:
	if is_instance_valid(layer_tree) and layer_tree.has_method("actualizar_filtro_busqueda"):
		layer_tree.actualizar_filtro_busqueda(texto)

func _icono_boton(barra: Node, nombre: String, ruta_icono: String, texto: String) -> void:
	var b := barra.get_node_or_null(nombre) as Button
	if not b:
		return
	b.tooltip_text = texto
	var tex := _icon(ruta_icono)
	if tex:
		b.icon = tex
		b.text = ""
		b.expand_icon = false


func _hm() -> Node:
	return get_node_or_null("/root/HistoryManager")

func _mgr() -> ArtboardManager:
	return ArtboardManager.find(get_tree()) if get_tree() else null

func _artboard_activo() -> Node2D:
	var m := _mgr()
	if m and m.has_method("get_active_artboard"):
		var a = m.get_active_artboard()
		if is_instance_valid(a):
			return a
	if is_instance_valid(artboard_container):
		for ch in artboard_container.get_children():
			if _es_artboard(ch):
				return ch
	return null


## "+A": crea un artboard nuevo a la derecha del último (como añadir una página).
func _on_btn_add_artboard() -> void:
	if not is_instance_valid(artboard_container):
		return
	var GAP := 80.0
	var pos := Vector2(0, 0)
	var size := Vector2(794, 1123)
	var previos: Array = []
	for ch in artboard_container.get_children():
		if _es_artboard(ch):
			previos.append(ch)
	if not previos.is_empty():
		var ref: Node2D = previos.back()
		size = ref.artboard_size
		pos = ref.global_position + Vector2(ref.artboard_size.x + GAP, 0)
	var ab := Node2D.new()
	ab.set_script(load("res://scripts/canvas/artboard.gd"))
	ab.name = NameUtils.unique_child_name(artboard_container, "Artboard")
	ab.artboard_size = size
	var cont := artboard_container
	var m := _mgr()
	var do_fn := func() -> void:
		if not is_instance_valid(ab):
			return
		if ab.get_parent() == null:
			cont.add_child(ab)
		ab.global_position = pos
		if m and m.has_method("set_active_artboard"):
			m.set_active_artboard(ab)
	var undo_fn := func() -> void:
		if is_instance_valid(ab) and ab.get_parent():
			ab.get_parent().remove_child(ab)
	var h := _hm()
	if h and h.has_method("register_action"):
		h.register_action("Crear artboard")
		h.add_do(do_fn)
		h.add_undo(undo_fn)
		h.commit()
	do_fn.call()


## "+": crea un grupo vacío en el artboard activo (equivalente a "nueva capa").
func _on_btn_add_group() -> void:
	var destino := _artboard_activo()
	if not is_instance_valid(destino):
		return
	var grupo := Node2D.new()
	grupo.name = NameUtils.unique_child_name(destino, "Grupo")
	grupo.set_meta("shape_type", "group")
	grupo.position = Vector2(40, 40)
	var do_fn := func() -> void:
		if is_instance_valid(grupo) and grupo.get_parent() == null:
			destino.add_child(grupo)
	var undo_fn := func() -> void:
		if is_instance_valid(grupo) and grupo.get_parent():
			grupo.get_parent().remove_child(grupo)
	var h := _hm()
	if h and h.has_method("register_action"):
		h.register_action("Crear grupo")
		h.add_do(do_fn)
		h.add_undo(undo_fn)
		h.commit()
	do_fn.call()


## "-": borra el elemento seleccionado en el árbol (figura, grupo o artboard).
func _on_btn_delete() -> void:
	if not is_instance_valid(layer_tree):
		return
	var sel: TreeItem = layer_tree.get_selected()
	if not sel:
		return
	var nodo = sel.get_metadata(1)
	if not is_instance_valid(nodo) or not (nodo is Node):
		return
	var padre: Node = nodo.get_parent()
	var idx: int = nodo.get_index()
	var do_fn := func() -> void:
		if is_instance_valid(nodo) and nodo.get_parent():
			nodo.get_parent().remove_child(nodo)
	var undo_fn := func() -> void:
		if is_instance_valid(nodo) and is_instance_valid(padre) and nodo.get_parent() == null:
			padre.add_child(nodo)
			padre.move_child(nodo, mini(idx, padre.get_child_count() - 1))
	var h := _hm()
	if h and h.has_method("register_action"):
		h.register_action("Eliminar del panel de capas")
		h.add_do(do_fn)
		h.add_undo(undo_fn)
		h.commit()
	do_fn.call()


func conectar_senales_sistema() -> void:
	if not is_instance_valid(artboard_container):
		return
			
	# Monitorear si se añaden o quitan Artboards del contenedor principal
	if not artboard_container.child_entered_tree.is_connected(_on_node_added):
		artboard_container.child_entered_tree.connect(_on_node_added)
			
	# CORRECCIÓN DEL CRASH: 'child_exiting_tree' en lugar de 'child_exited_tree'
	if not artboard_container.child_exiting_tree.is_connected(_on_node_removed):
		artboard_container.child_exiting_tree.connect(_on_node_removed)

	# Conectar el evento de edición del propio Tree
	if is_instance_valid(layer_tree):
		if not layer_tree.item_edited.is_connected(_on_layer_tree_item_edited):
			layer_tree.item_edited.connect(_on_layer_tree_item_edited)
		# El LayerTree reparenta nodos reales en su _drop_data (drag&drop). Tras
		# eso hay que re-sincronizar el árbol con la jerarquía nueva — antes esta
		# señal se emitía pero nadie la escuchaba, así que el panel quedaba
		# desincronizado hasta el siguiente cambio estructural.
		if layer_tree.has_signal("hierarchy_changed_by_user") \
				and not layer_tree.hierarchy_changed_by_user.is_connected(_on_hierarchy_changed_by_user):
			layer_tree.hierarchy_changed_by_user.connect(_on_hierarchy_changed_by_user)

	# Refrescar el árbol (y con él, el indicador de "fuera del artboard") cuando
	# se termina de mover/transformar una figura — MoveTool.gd no emitía esta
	# señal (existía en GlobalEvents pero nada la disparaba); se conectó
	# también ahí. Sin esto, arrastrar una figura fuera del artboard no
	# actualizaba el panel de capas hasta el siguiente cambio estructural.
	if GlobalEvents and not GlobalEvents.object_transformed.is_connected(_on_object_transformed):
		GlobalEvents.object_transformed.connect(_on_object_transformed)

	# ── Sincronía BIDIRECCIONAL de selección (Fase 1) ─────────────────────────
	# Lienzo → panel: SelectionManager re-emite `GlobalEvents.selection_changed`.
	if GlobalEvents and GlobalEvents.has_signal("selection_changed") \
			and not GlobalEvents.selection_changed.is_connected(_on_canvas_selection_changed):
		GlobalEvents.selection_changed.connect(_on_canvas_selection_changed)
	# Panel → lienzo: cuando el usuario cambia la selección EN el árbol.
	if is_instance_valid(layer_tree):
		if layer_tree.has_signal("multi_selected") \
				and not layer_tree.multi_selected.is_connected(_on_tree_selection_changed):
			layer_tree.multi_selected.connect(_on_tree_selection_changed)
		if not layer_tree.item_selected.is_connected(_on_tree_item_selected):
			layer_tree.item_selected.connect(_on_tree_item_selected)
		# Menú contextual (clic derecho) de la fila.
		if layer_tree.has_signal("item_right_clicked") \
				and not layer_tree.item_right_clicked.is_connected(_mostrar_menu_contextual):
			layer_tree.item_right_clicked.connect(_mostrar_menu_contextual)
		# Navegación por teclado: Espacio (visibilidad) y Ctrl+G / Ctrl+Shift+G.
		if layer_tree.has_signal("key_toggle_visibility") \
				and not layer_tree.key_toggle_visibility.is_connected(_on_key_toggle_visibility):
			layer_tree.key_toggle_visibility.connect(_on_key_toggle_visibility)
			layer_tree.key_group_request.connect(_agrupar_seleccion)
			layer_tree.key_ungroup_request.connect(_desagrupar_seleccion)


## El usuario reordenó / reparentó nodos arrastrando en el propio panel de capas
## (LayerTree._drop_data ya movió los Node2D reales). Re-sincronizamos el árbol
## contra la jerarquía nueva.
##
## CRÍTICO: esta señal se emite DENTRO de `_drop_data`, es decir mientras Godot
## sigue ejecutando su máquina de estados de drag&drop del Viewport. Si
## `sincronizar_arbol_completo` (que hace `layer_tree.clear()` → libera TODOS los
## TreeItem) corre demasiado pronto, el sistema de drag de Godot se queda con
## punteros colgantes y el SIGUIENTE arrastre no arranca ("primer anidado OK, el
## segundo bloquea"). Por eso se aplaza a un frame LIMPIO, ya terminada la
## gestión del drop.
func _on_hierarchy_changed_by_user() -> void:
	if _bloquear_sincronizacion:
		return
	_resync_tras_drag()

func _resync_tras_drag() -> void:
	await get_tree().process_frame   # deja terminar la máquina de drag de Godot
	await get_tree().process_frame
	if not _bloquear_sincronizacion:
		sincronizar_arbol_completo()


func _on_object_transformed() -> void:
	# Mover/rotar/escalar NO cambia la ESTRUCTURA del árbol, solo si la figura
	# quedó fuera del artboard. Refrescamos ese indicador in situ (O(N) barato)
	# en vez de reconstruir N TreeItems desde cero (O(N) con allocations) en
	# cada fin de arrastre — con miles de figuras ese rebuild se notaba.
	_refrescar_indicadores_estado()

## Guarda contra el eco: cuando reflejamos la selección del lienzo EN el árbol,
## los `select()` disparan `multi_selected`, que reenviaría al lienzo, etc.
var _reflejando_seleccion: bool = false

## El lienzo (SelectionManager) cambió la selección. Reflejamos esas figuras
## como filas seleccionadas en el árbol, abrimos sus padres y hacemos scroll.
func _on_canvas_selection_changed(shapes: Array) -> void:
	if not is_instance_valid(layer_tree) or _reflejando_seleccion:
		return
	_reflejando_seleccion = true
	layer_tree.deselect_all()
	var primero: TreeItem = null
	for s in shapes:
		if not (s is Node) or not is_instance_valid(s):
			continue
		var it: TreeItem = _item_para_nodo(s)
		if it == null:
			continue
		it.select(0)
		var p := it.get_parent()
		while p != null:
			p.collapsed = false
			p = p.get_parent()
		if primero == null:
			primero = it
	if primero != null:
		layer_tree.scroll_to_item(primero)
	_reflejando_seleccion = false

## TreeItem que representa a `nodo` (o a su ancestro-capa más cercano si el nodo
## es un hijo interno de render que no aparece como fila propia).
func _item_para_nodo(nodo: Node) -> TreeItem:
	var actual: Node = nodo
	while is_instance_valid(actual):
		if _node_to_item_map.has(actual):
			var it: TreeItem = _node_to_item_map[actual]
			if is_instance_valid(it):
				return it
		actual = actual.get_parent()
	return null

## El usuario cambió la selección EN el árbol (clic, Ctrl+clic, Shift+rango).
## `multi_selected` se dispara una vez por fila afectada → diferimos para
## empujar UNA sola vez el conjunto final a SelectionManager.
func _on_tree_selection_changed(_item: TreeItem = null, _column: int = 0, _selected: bool = false) -> void:
	if _reflejando_seleccion:
		return
	call_deferred("_empujar_seleccion_del_arbol")

func _on_tree_item_selected() -> void:
	if _reflejando_seleccion:
		return
	call_deferred("_empujar_seleccion_del_arbol")

func _empujar_seleccion_del_arbol() -> void:
	if _reflejando_seleccion or not is_instance_valid(layer_tree):
		return
	var sm := get_node_or_null("/root/SelectionManager")
	if sm == null:
		return
	var nodos: Array = []
	var it: TreeItem = layer_tree.get_next_selected(null)
	while it != null:
		var n = it.get_metadata(1)
		if is_instance_valid(n) and n is Node2D:
			nodos.append(n)
		it = layer_tree.get_next_selected(it)
	_reflejando_seleccion = true
	sm.set_selection(nodos)
	_reflejando_seleccion = false

## Recorre los items ya existentes y actualiza texto/color/aviso sin recrearlos.
func _refrescar_indicadores_estado() -> void:
	if _bloquear_sincronizacion or not is_instance_valid(layer_tree):
		return
	for nodo in _node_to_item_map.keys():
		var item: TreeItem = _node_to_item_map[nodo]
		if not is_instance_valid(item) or not is_instance_valid(nodo):
			continue
		var tipo := str(item.get_metadata(0))
		if tipo == "artboard" or tipo == "sueltos":
			continue
		# Suelto de primer nivel (hijo directo del grupo "Fuera de artboard") →
		# fuera por definición. Más profundo → se compara con su contenedor local.
		var es_suelto_top: bool = item.get_parent() == _sueltos_item
		var ab := _encontrar_artboard_ancestro(nodo)
		var fuera := es_suelto_top or (ab != null and _esta_fuera_del_artboard(nodo, ab))
		var base_name := str(nodo.name)
		item.set_text(0, base_name + ("  ⚠ fuera del artboard" if fuera else ""))
		var idx := _indice_boton(item, 2, _BTN_VIS)
		if idx >= 0:
			item.set_button(2, idx, _ICON_EYE if nodo.visible else _ICON_EYE_OFF)
			_tintar_boton_id(item, _BTN_VIS, nodo.visible)
		_aplicar_estilo_visibilidad(item, nodo.visible, tipo)
		if fuera and nodo.visible:
			item.set_custom_color(0, Color(0.95, 0.65, 0.15))
	_repintar_canvas()


# =============================================================================
# SINCRO CORE: CONSTRUCCIÓN JERÁRQUICA DE LA UI
# =============================================================================
func sincronizar_arbol_completo() -> void:
	if _bloquear_sincronizacion or not is_instance_valid(layer_tree) or not is_instance_valid(artboard_container):
		return

	_bloquear_sincronizacion = true
	layer_tree.clear()
	_node_to_item_map.clear()
	_pending_changes.clear()
	_sueltos_item = null

	# `Tree.clear()` puede dejar el estado de drop en un limbo → tras el primer
	# reparent por arrastre, `get_drop_section_at_position()` devolvía -100 y
	# NINGÚN drop posterior anidaba (todos sacaban la figura al artboard).
	# Re-afirmamos el modo de drop combinado (ENCIMA | ENTRE) en cada rebuild.
	if "drop_mode_flags" in layer_tree:
		layer_tree.drop_mode_flags = 3

	# Crear la raíz invisible obligatoria para el Tree
	var raiz_oculta : TreeItem = layer_tree.create_item()
	if not raiz_oculta:
		_bloquear_sincronizacion = false
		return

	# Limpiar registro de artboards antiguos para evitar fugas de memoria
	_artboards_conectados.clear()

	# Los hijos directos del contenedor son de DOS clases: artboards y figuras
	# SUELTAS (fuera de todo artboard). Se muestran por separado.
	for hijo in artboard_container.get_children():
		if _es_artboard(hijo):
			_vincular_senales_artboard(hijo)
			_construir_nodo_recursivo(raiz_oculta, hijo, hijo)
		elif hijo is Node2D and hijo.name != "Contorno_Stroke":
			_construir_nodo_recursivo(_get_sueltos_item(), hijo, null)

	_bloquear_sincronizacion = false
	_repintar_canvas()


## Crea (perezosamente) el grupo raíz "Fuera de artboard". null-safe.
func _get_sueltos_item() -> TreeItem:
	if is_instance_valid(_sueltos_item):
		return _sueltos_item
	var raiz := layer_tree.get_root()
	if not raiz:
		return raiz
	_sueltos_item = layer_tree.create_item(raiz)
	_sueltos_item.set_cell_mode(0, TreeItem.CELL_MODE_STRING)
	_sueltos_item.set_text(0, SUELTOS_LABEL)
	_sueltos_item.set_editable(0, false)
	for c in 3:
		_sueltos_item.set_selectable(c, false)
	_sueltos_item.set_metadata(0, "sueltos")
	_sueltos_item.set_custom_color(0, Color(0.95, 0.65, 0.15))
	return _sueltos_item


func _construir_nodo_recursivo(parent_item: TreeItem, real_node: Node2D, artboard_actual: Node2D) -> void:
	if not is_instance_valid(real_node) or real_node.name == "Contorno_Stroke":
		return # Ignorar líneas estéticas auxiliares de las herramientas

	# Crear el TreeItem para este nodo
	var item = _create_tree_item(parent_item, real_node, artboard_actual)
	if item == null:
		return

	# Se recurre si el nodo tiene hijos que son CAPAS: grupo, artboard, O una
	# figura/texto que a su vez contiene otras figuras (elemento DENTRO de
	# elemento, cualquier profundidad). Los hijos internos de render
	# (Contorno_Stroke, Render_Visual, DisplayLabel…) los descarta `_es_capa` /
	# el filtro `hijo is Node2D`, así que una figura hoja no genera flecha ">".
	var tipo := str(item.get_metadata(0))
	var es_contenedor := tipo == "group" or tipo == "artboard" or tipo == "sueltos"
	if not es_contenedor and not _tiene_hijos_capa(real_node):
		return

	var ab_para_hijos: Node2D = artboard_actual if artboard_actual != null else real_node
	for hijo in real_node.get_children():
		if hijo is Node2D and _es_capa(hijo):
			_construir_nodo_recursivo(item, hijo, ab_para_hijos)

## ¿Este Node2D es una CAPA de usuario (figura / grupo / artboard) y no un
## nodo interno de render de una herramienta?
func _es_capa(n: Node) -> bool:
	if n.name == "Contorno_Stroke" or n.name == "Render_Visual":
		return false
	if n is VectorShape or n is Line2D or n is Polygon2D or n is Sprite2D or n is Path2D:
		return true
	if n.has_meta("shape_type"):
		return true
	if _es_artboard(n):
		return true
	# Node2D "pelado" con hijos → grupo. Sin hijos → probablemente auxiliar.
	return n.get_child_count() > 0

## Comprueba si el ORIGEN del nodo cae fuera del rectángulo del artboard.
## Es una comprobación simple por punto (no el AABB completo de la figura,
## que ya se calcula de forma más precisa y duplicada en MoveTool.gd y
## bounding_box.gd) — suficiente para el indicador de aviso del panel de
## capas sin añadir una tercera copia de esa lógica geométrica.
func _esta_fuera_del_artboard(real_node: Node2D, artboard_actual: Node2D) -> bool:
	if real_node == artboard_actual:
		return false
	if artboard_actual == null:
		return true   # figura SUELTA: fuera de todo artboard, por definición
	if not is_instance_valid(artboard_actual) or not ("artboard_size" in artboard_actual):
		return false
	var rect := Rect2(artboard_actual.global_position, artboard_actual.artboard_size)
	return not rect.has_point(real_node.global_position)

func _create_tree_item(parent_item: TreeItem, real_node: Node2D, artboard_actual: Node2D = null) -> TreeItem:
	# 1. Identificar el tipo de capa para el estilo visual
	var type : String = "shape"
	if _es_artboard(real_node):
		type = "artboard"
	elif real_node.has_meta("shape_type"):
		type = real_node.get_meta("shape_type") as String
	elif _tiene_hijos_capa(real_node):
		type = "group"

	# 2. Instanciar el TreeItem de forma segura
	var item : TreeItem = layer_tree.create_item(parent_item)
	if not item:
		return null

	# COLUMNA 0 = todo lo visible (flecha · líneas · sangría · icono · nombre).
	# En un Tree multi-columna de Godot la sangría por nivel SOLO afecta a la
	# columna 0 → si el nombre va en otra columna, los hijos no se ven a la
	# derecha. COL 1 solo guarda la referencia al nodo. COL 2 = botones.
	item.set_cell_mode(0, TreeItem.CELL_MODE_STRING)
	item.set_cell_mode(1, TreeItem.CELL_MODE_STRING)
	item.set_cell_mode(2, TreeItem.CELL_MODE_STRING)

	item.set_text(0, real_node.name)
	item.set_editable(0, true)
	item.set_icon(0, _type_icon(_clave_icono(real_node, type)))
	item.set_icon_max_width(0, 14)

	item.set_metadata(1, real_node)   # slot de metadatos del nodo
	item.set_metadata(0, type)        # slot de metadatos del tipo

	# TODAS las filas llevan los MISMOS 3 botones en el MISMO orden:
	#   1 ojo (visibilidad) · 2 candado (bloqueo) · 3 máscara (recorte)
	# Así las columnas quedan alineadas fila a fila. Activo = negro; inactivo =
	# gris casi blanco (igual que las líneas de jerarquía).
	var is_locked : bool = real_node.get_meta("locked", false)
	if is_instance_valid(layer_tree) and layer_tree.columns >= 3:
		item.add_button(2, _ICON_EYE if real_node.visible else _ICON_EYE_OFF, _BTN_VIS, false, "Visibilidad")
		item.add_button(2, _ICON_LOCK if is_locked else _ICON_LOCK_OPEN, _BTN_LOCK, false, "Bloquear")
		item.add_button(2, _CLIP_ICON_OFF, _BTN_CLIP, false, "Máscara de recorte (recortar a los hijos)")
		_tintar_boton_id(item, _BTN_VIS, real_node.visible)
		_tintar_boton_id(item, _BTN_LOCK, is_locked)   # cerrado(locked)=negro, abierto=gris
		_refrescar_boton_clip(item, real_node)

	# Aplicar paleta de color correspondiente (Gris, Azul para grupos, etc.)
	_aplicar_estilo_visibilidad(item, real_node.visible, type)

	# Aviso visual si la figura quedó fuera de los límites de su artboard
	# (arrastrada fuera, o creada con coordenadas fuera de rango).
	if type != "artboard" and _esta_fuera_del_artboard(real_node, artboard_actual):
		item.set_text(0, real_node.name + "  ⚠ fuera del artboard")
		item.set_tooltip_text(0, "Esta figura está fuera de los límites del artboard")
		if real_node.visible:
			item.set_custom_color(0, Color(0.95, 0.65, 0.15))  # Naranja de aviso

	# Mapear nodo → TreeItem para actualizaciones incrementales
	_node_to_item_map[real_node] = item

	return item

func _tiene_hijos_capa(nodo: Node) -> bool:
	for h in nodo.get_children():
		if h is Node2D and _es_capa(h):
			return true
	return false

func _tiene_hijos_dibujables(nodo: Node) -> bool:
	return _tiene_hijos_capa(nodo)

## Color de los botones de fila (ojo/candado/máscara). Los iconos son trazo
## negro y se tiñen: ACTIVO = negro (`PANEL_TEXT`); INACTIVO = gris casi blanco,
## el mismo que las líneas de jerarquía → casi no se ve, pero el hueco queda.
const _BOTON_INACTIVO := Color(0.87, 0.87, 0.90, 1.0)
func _color_boton(positivo: bool) -> Color:
	if not positivo:
		return _BOTON_INACTIVO
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return Color(0.1, 0.1, 0.12)
	return tm.get_color(tm.Slot.PANEL_TEXT)

## Tiñe el botón identificado por `id` en la columna 2 (todos los botones viven ahí).
func _tintar_boton_id(item: TreeItem, id: int, positivo: bool) -> void:
	var idx := _indice_boton(item, 2, id)
	if idx >= 0:
		item.set_button_color(2, idx, _color_boton(positivo))

## Colorea el botón de clip según su estado (acento = activo, atenuado = inactivo).
func _refrescar_boton_clip(item: TreeItem, nodo: Node) -> void:
	var idx := _indice_boton(item, 2, _BTN_CLIP)
	if idx < 0:
		return
	# Activa = recorte directo (figura) O máscara stencil (grupo/texto).
	var activo: bool = int(nodo.clip_children) != 0 or _mascara_activa(nodo)
	# Icono DISTINTO según estado (no solo color): activa = recorte; inactiva =
	# marco vacío. Color: activo = negro, inactivo = gris casi blanco.
	item.set_button(2, idx, _CLIP_ICON if activo else _CLIP_ICON_OFF)
	item.set_button_color(2, idx, _color_boton(activo))

func _indice_boton(item: TreeItem, column: int, id: int) -> int:
	for i in item.get_button_count(column):
		if item.get_button_id(column, i) == id:
			return i
	return -1

## El usuario pulsó un botón de fila del árbol: ojo / candado / máscara.
func _on_tree_button_clicked(item: TreeItem, _column: int, id: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var nodo = item.get_metadata(1)
	if not is_instance_valid(nodo):
		return

	match id:
		_BTN_VIS:
			_accion_undo("Visibilidad de capa",
				func(): _set_vis(item, nodo, not nodo.visible),
				func(): _set_vis(item, nodo, not nodo.visible))
			return
		_BTN_LOCK:
			var lk := not bool(nodo.get_meta("locked", false))
			_accion_undo("Bloqueo de capa",
				func(): _set_lock(item, nodo, lk),
				func(): _set_lock(item, nodo, not lk))
			return
		_BTN_CLIP:
			if not ("clip_children" in nodo):
				return
			if _es_contenedor_sin_cuerpo(nodo):
				# Grupo o texto: la máscara es STENCIL — la figura de arriba (o
				# las letras del texto) recortan al resto del contenido.
				if _mascara_activa(nodo):
					_desactivar_mascara(item, nodo)
				else:
					_activar_mascara(item, nodo)
				return
			# Figura con geometría propia: recorte directo (recorta a su forma).
			var antes: int = int(nodo.clip_children)
			var despues: int = 0 if antes != 0 else _CLIP_ON
			_accion_undo("Máscara de recorte",
				func(): _set_clip(item, nodo, despues),
				func(): _set_clip(item, nodo, antes))
			return

func _set_vis(item: TreeItem, nodo: Node, v: bool) -> void:
	if not is_instance_valid(nodo): return
	nodo.visible = v
	if is_instance_valid(item):
		var idx := _indice_boton(item, 2, _BTN_VIS)
		if idx >= 0:
			item.set_button(2, idx, _ICON_EYE if v else _ICON_EYE_OFF)
		_tintar_boton_id(item, _BTN_VIS, v)
		_aplicar_estilo_visibilidad(item, v, str(item.get_metadata(0)))
	_repintar_canvas()

func _set_lock(item: TreeItem, nodo: Node, locked: bool) -> void:
	if not is_instance_valid(nodo): return
	nodo.set_meta("locked", locked)
	if is_instance_valid(item):
		var idx := _indice_boton(item, 2, _BTN_LOCK)
		if idx >= 0:
			item.set_button(2, idx, _ICON_LOCK if locked else _ICON_LOCK_OPEN)
		_tintar_boton_id(item, _BTN_LOCK, locked)   # cerrado=negro, abierto=gris

func _set_clip(item: TreeItem, nodo: Node, modo: int) -> void:
	if not is_instance_valid(nodo) or not ("clip_children" in nodo): return
	nodo.clip_children = modo
	nodo.set_meta("clip_mask", modo != 0)
	if is_instance_valid(item):
		_refrescar_boton_clip(item, nodo)
	_repintar_canvas()

# ── MÁSCARA STENCIL para GRUPOS y TEXTO ──────────────────────────────────────
# `clip_children` de Godot recorta a la FORMA que dibuja el nodo. Un grupo
# (Node2D pelado) o un texto (Node2D + Label hijo) no dibujan → el recorte
# quedaría vacío. Solución estilo Illustrator: la figura de ARRIBA del grupo
# (o el Label del texto) es la MÁSCARA; el resto del contenido se mueve DENTRO
# de ella y se le pone `clip_children` → recorta al contenido a esa forma.

## ¿`n` es un contenedor SIN geometría propia (grupo pelado o texto)?
func _es_contenedor_sin_cuerpo(n: Node) -> bool:
	if n is VectorShape or n is Line2D or n is Polygon2D or n is Path2D or n is Sprite2D:
		return false
	return n is Node2D

func _mascara_activa(c: Node) -> bool:
	return is_instance_valid(c) and c.has_meta("clip_mask") and bool(c.get_meta("clip_mask"))

## Nodo que hará de máscara: para texto = su `DisplayLabel`; para grupo = el
## último hijo-figura (Z más alto, "el de arriba").
func _nodo_mascara_de(c: Node) -> CanvasItem:
	if c.has_meta("shape_type") and String(c.get_meta("shape_type")).begins_with("text_"):
		return c.get_node_or_null("DisplayLabel") as CanvasItem
	var ultimo: CanvasItem = null
	for h in c.get_children():
		if h is Node2D and _es_capa(h):
			ultimo = h
	return ultimo

func _activar_mascara(item: TreeItem, c: Node) -> void:
	var m := _nodo_mascara_de(c)
	if not is_instance_valid(m):
		return
	# Contenido a recortar = hijos-capa del contenedor que NO son la máscara.
	var contenido: Array = []
	for h in c.get_children():
		if h is Node2D and _es_capa(h) and h != m:
			contenido.append({"n": h, "i": h.get_index()})
	if contenido.is_empty():
		return   # nada que recortar

	var do_fn := func() -> void:
		for e in contenido:
			var n = e["n"]
			if is_instance_valid(n) and n.get_parent() != m:
				n.reparent(m, true)
		m.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		c.set_meta("clip_mask", true)
		c.set_meta("clip_mask_target", String(m.name))
		if is_instance_valid(item):
			_refrescar_boton_clip(item, c)
		_marcar_arbol_sucio()
		_repintar_canvas()
	var undo_fn := func() -> void:
		m.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		var e2 := contenido.duplicate()
		e2.sort_custom(func(a, b): return a["i"] < b["i"])
		for e in e2:
			var n = e["n"]
			if is_instance_valid(n) and n.get_parent() != c:
				n.reparent(c, true)
				c.move_child(n, mini(int(e["i"]), c.get_child_count() - 1))
		c.remove_meta("clip_mask")
		c.remove_meta("clip_mask_target")
		if is_instance_valid(item):
			_refrescar_boton_clip(item, c)
		_marcar_arbol_sucio()
		_repintar_canvas()
	_accion_undo("Máscara de recorte", do_fn, undo_fn)

func _desactivar_mascara(item: TreeItem, c: Node) -> void:
	var objetivo := String(c.get_meta("clip_mask_target", ""))
	var m := c.get_node_or_null(NodePath(objetivo)) as CanvasItem
	if not is_instance_valid(m):
		# fallback: cualquier hijo con clip_children activo
		for h in c.get_children():
			if h is CanvasItem and int(h.clip_children) != 0:
				m = h
				break
	if not is_instance_valid(m):
		c.remove_meta("clip_mask")
		return
	var contenido: Array = []
	for h in m.get_children():
		if h is Node2D and _es_capa(h):
			contenido.append({"n": h, "i": h.get_index()})

	var do_fn := func() -> void:
		m.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		for e in contenido:
			var n = e["n"]
			if is_instance_valid(n) and n.get_parent() != c:
				n.reparent(c, true)
		c.remove_meta("clip_mask")
		c.remove_meta("clip_mask_target")
		if is_instance_valid(item):
			_refrescar_boton_clip(item, c)
		_marcar_arbol_sucio()
		_repintar_canvas()
	var undo_fn := func() -> void:
		for e in contenido:
			var n = e["n"]
			if is_instance_valid(n) and n.get_parent() != m:
				n.reparent(m, true)
		m.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		c.set_meta("clip_mask", true)
		c.set_meta("clip_mask_target", String(m.name))
		if is_instance_valid(item):
			_refrescar_boton_clip(item, c)
		_marcar_arbol_sucio()
		_repintar_canvas()
	_accion_undo("Quitar máscara de recorte", do_fn, undo_fn)

func _accion_undo(nombre: String, do_fn: Callable, undo_fn: Callable) -> void:
	var h := _hm()
	if h and h.has_method("register_action"):
		h.register_action(nombre)
		h.add_do(do_fn)
		h.add_undo(undo_fn)
		h.commit()
	do_fn.call()


# =============================================================================
# MENÚ CONTEXTUAL (clic derecho) — Fase 2/3 del panel profesional
# =============================================================================
enum _Ctx {
	SEL, SEL_HIJOS, SEL_DESC, SEL_RAMA, SEL_SIMILARES,
	RENOMBRAR, DUPLICAR, ELIMINAR,
	VISIBILIDAD, BLOQUEO,
	AGRUPAR, DESAGRUPAR,
	AL_FRENTE, ADELANTE, ATRAS, AL_FONDO,
	AL_IZQ, AL_CENTRO_H, AL_DER, AL_ARRIBA, AL_MEDIO, AL_ABAJO,
	DIST_H, DIST_V,
}
var _ctx_menu: PopupMenu = null
var _ctx_align: PopupMenu = null
var _ctx_item: TreeItem = null

func _crear_menu_contextual() -> void:
	_ctx_menu = PopupMenu.new()
	_ctx_menu.name = "LayerContextMenu"
	add_child(_ctx_menu)
	_ctx_menu.id_pressed.connect(_on_ctx_menu_id)

	_ctx_align = PopupMenu.new()
	_ctx_align.name = "AlignSubmenu"
	_ctx_align.add_item("Izquierda", _Ctx.AL_IZQ)
	_ctx_align.add_item("Centro horizontal", _Ctx.AL_CENTRO_H)
	_ctx_align.add_item("Derecha", _Ctx.AL_DER)
	_ctx_align.add_separator()
	_ctx_align.add_item("Arriba", _Ctx.AL_ARRIBA)
	_ctx_align.add_item("Medio vertical", _Ctx.AL_MEDIO)
	_ctx_align.add_item("Abajo", _Ctx.AL_ABAJO)
	_ctx_align.add_separator()
	_ctx_align.add_item("Distribuir horizontal", _Ctx.DIST_H)
	_ctx_align.add_item("Distribuir vertical", _Ctx.DIST_V)
	_ctx_align.id_pressed.connect(_on_ctx_menu_id)
	_ctx_menu.add_child(_ctx_align)

func _mostrar_menu_contextual(item: TreeItem, pos: Vector2) -> void:
	if not is_instance_valid(item) or not is_instance_valid(_ctx_menu):
		return
	_ctx_item = item
	var nodo = item.get_metadata(1)
	var tipo := str(item.get_metadata(0))
	var es_contenedor := tipo == "group" or tipo == "artboard"
	# Asegurar que la fila del clic derecho forma parte de la selección viva
	# (si ya había varias filas seleccionadas, se respetan).
	var sm_ctx := get_node_or_null("/root/SelectionManager")
	if not item.is_selected(0):
		layer_tree.deselect_all()
		item.select(0)
	if sm_ctx and is_instance_valid(nodo) and not sm_ctx.is_selected(nodo):
		_empujar_seleccion_del_arbol()

	_ctx_menu.clear()
	_ctx_menu.add_item("Seleccionar", _Ctx.SEL)
	if es_contenedor:
		_ctx_menu.add_item("Seleccionar hijos", _Ctx.SEL_HIJOS)
		_ctx_menu.add_item("Seleccionar descendientes", _Ctx.SEL_DESC)
		_ctx_menu.add_item("Seleccionar rama", _Ctx.SEL_RAMA)
	else:
		_ctx_menu.add_item("Seleccionar similares", _Ctx.SEL_SIMILARES)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Renombrar", _Ctx.RENOMBRAR)
	_ctx_menu.add_item("Duplicar", _Ctx.DUPLICAR)
	_ctx_menu.add_item("Eliminar", _Ctx.ELIMINAR)
	_ctx_menu.add_separator()
	var visible_ahora := is_instance_valid(nodo) and bool(nodo.visible)
	_ctx_menu.add_item("Ocultar" if visible_ahora else "Mostrar", _Ctx.VISIBILIDAD)
	var bloqueado := is_instance_valid(nodo) and bool(nodo.get_meta("locked", false))
	_ctx_menu.add_item("Desbloquear" if bloqueado else "Bloquear", _Ctx.BLOQUEO)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Agrupar selección", _Ctx.AGRUPAR)
	if es_contenedor:
		_ctx_menu.add_item("Desagrupar", _Ctx.DESAGRUPAR)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Traer al frente", _Ctx.AL_FRENTE)
	_ctx_menu.add_item("Traer adelante", _Ctx.ADELANTE)
	_ctx_menu.add_item("Enviar atrás", _Ctx.ATRAS)
	_ctx_menu.add_item("Enviar al fondo", _Ctx.AL_FONDO)
	# Alinear / distribuir: solo con 2+ figuras seleccionadas.
	var sm0 := get_node_or_null("/root/SelectionManager")
	if sm0 and sm0.count() >= 2:
		_ctx_menu.add_separator()
		_ctx_menu.add_submenu_item("Alinear / distribuir", "AlignSubmenu")

	_tema_menu(_ctx_menu)
	_tema_menu(_ctx_align)
	_ctx_menu.reset_size()
	# Ajustar para que no se salga de la pantalla (Godot no siempre lo hace solo
	# con una posición forzada).
	var scr := DisplayServer.window_get_size()
	var msz := _ctx_menu.get_contents_minimum_size()
	var p := Vector2(pos)
	p.x = clampf(p.x, 4.0, float(scr.x) - msz.x - 4.0)
	p.y = clampf(p.y, 4.0, float(scr.y) - msz.y - 4.0)
	_ctx_menu.position = Vector2i(p)
	_ctx_menu.popup()

## Aplica los tokens del tema (claro por defecto) al PopupMenu — no hereda el
## theme del root de forma fiable para todos sus slots.
func _tema_menu(m: PopupMenu) -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null or m == null:
		return
	var S = tm.Slot
	var bg: Color = tm.get_color(S.PANEL_BG)
	var txt: Color = tm.get_color(S.PANEL_TEXT)
	var hov: Color = tm.get_color(S.BUTTON_HOVER)
	var brd: Color = tm.get_color(S.BORDER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = brd
	sb.set_content_margin_all(6)
	m.add_theme_stylebox_override("panel", sb)
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = hov
	hsb.set_corner_radius_all(5)
	m.add_theme_stylebox_override("hover", hsb)
	m.add_theme_color_override("font_color", txt)
	m.add_theme_color_override("font_hover_color", txt)
	m.add_theme_color_override("font_separator_color", tm.get_color(S.TEXT_DISABLED))

func _on_ctx_menu_id(id: int) -> void:
	var sm := get_node_or_null("/root/SelectionManager")
	var nodo = _ctx_item.get_metadata(1) if is_instance_valid(_ctx_item) else null
	match id:
		_Ctx.SEL:
			if sm and is_instance_valid(nodo):
				sm.select(nodo)
		_Ctx.SEL_HIJOS:
			if sm and is_instance_valid(nodo):
				sm.select_children(nodo)
		_Ctx.SEL_DESC:
			if sm and is_instance_valid(nodo):
				sm.select_descendants(nodo)
		_Ctx.SEL_RAMA:
			if sm and is_instance_valid(nodo):
				sm.select_branch(nodo)
		_Ctx.SEL_SIMILARES:
			_seleccionar_similares(nodo)
		_Ctx.RENOMBRAR:
			if is_instance_valid(_ctx_item):
				layer_tree.edit_selected(true)
		_Ctx.DUPLICAR:
			_duplicar_seleccion()
		_Ctx.ELIMINAR:
			_eliminar_seleccion()
		_Ctx.VISIBILIDAD:
			if is_instance_valid(_ctx_item) and is_instance_valid(nodo):
				_accion_undo("Visibilidad de capa",
					func(): _set_vis(_ctx_item, nodo, not nodo.visible),
					func(): _set_vis(_ctx_item, nodo, not nodo.visible))
		_Ctx.BLOQUEO:
			if is_instance_valid(_ctx_item) and is_instance_valid(nodo):
				var lk := not bool(nodo.get_meta("locked", false))
				_accion_undo("Bloqueo de capa",
					func(): _set_lock(_ctx_item, nodo, lk),
					func(): _set_lock(_ctx_item, nodo, not lk))
		_Ctx.AGRUPAR:
			_agrupar_seleccion()
		_Ctx.DESAGRUPAR:
			if is_instance_valid(nodo):
				_desagrupar(nodo)
		_Ctx.AL_FRENTE, _Ctx.ADELANTE, _Ctx.ATRAS, _Ctx.AL_FONDO:
			_cambiar_orden_z(id)
		_Ctx.AL_IZQ:      _alinear("left")
		_Ctx.AL_CENTRO_H: _alinear("center_h")
		_Ctx.AL_DER:      _alinear("right")
		_Ctx.AL_ARRIBA:   _alinear("top")
		_Ctx.AL_MEDIO:    _alinear("middle")
		_Ctx.AL_ABAJO:    _alinear("bottom")
		_Ctx.DIST_H:      _distribuir("h")
		_Ctx.DIST_V:      _distribuir("v")

## "Seleccionar similares": todas las figuras del mismo tipo dentro del mismo
## artboard (o entre las sueltas) que `ref`.
func _seleccionar_similares(ref: Node) -> void:
	var sm := get_node_or_null("/root/SelectionManager")
	if sm == null or not is_instance_valid(ref):
		return
	var scr_ref: Variant = ref.get_script()
	var ambito: Node = _encontrar_artboard_ancestro(ref)
	if ambito == null:
		ambito = artboard_container
	var iguales: Array = []
	_recolectar_similares(ambito, ref, scr_ref, iguales)
	if not iguales.is_empty():
		sm.select_many(iguales)

func _recolectar_similares(raiz: Node, ref: Node, scr_ref: Variant, out: Array) -> void:
	for c in raiz.get_children():
		if c is Node2D and _es_capa(c) and not _es_artboard(c):
			var mismo: bool = (c.get_class() == ref.get_class()) and (c.get_script() == scr_ref)
			if mismo and c.has_meta("shape_type") and ref.has_meta("shape_type"):
				mismo = str(c.get_meta("shape_type")) == str(ref.get_meta("shape_type"))
			if mismo:
				out.append(c)
		if c is Node2D:
			_recolectar_similares(c, ref, scr_ref, out)

func _alinear(modo: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("align"):
		ic.align(modo)

func _distribuir(eje: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("distribute"):
		ic.distribute(eje)

## Reenvía una acción a MoveTool (que ya la implementa con undo real).
func _accion_sobre_seleccion(metodo: String) -> void:
	var mt := _move_tool()
	if mt and mt.has_method(metodo):
		mt.call(metodo)

## Duplica la selección en su mismo padre, con un pequeño desplazamiento y
## nombre único. Un Undo. Independiente de la herramienta activa.
func _duplicar_seleccion() -> void:
	var nodos := _seleccion_nodos()
	if nodos.is_empty():
		return
	var clones: Array = []
	var padres: Array = []
	for n in nodos:
		var p: Node = n.get_parent()
		if not is_instance_valid(p):
			continue
		var c: Node = n.duplicate()
		c.name = NameUtils.unique_child_name(p, _nombre_base(String(n.name)))
		if c is Node2D:
			(c as Node2D).position += Vector2(16, 16)
		clones.append(c)
		padres.append(p)
	if clones.is_empty():
		return
	var do_fn := func() -> void:
		for i in clones.size():
			if is_instance_valid(clones[i]) and clones[i].get_parent() == null:
				padres[i].add_child(clones[i])
		var sm := get_node_or_null("/root/SelectionManager")
		if sm:
			sm.set_selection(clones)
		_marcar_arbol_sucio()
	var undo_fn := func() -> void:
		for c in clones:
			if is_instance_valid(c) and c.get_parent():
				c.get_parent().remove_child(c)
		_marcar_arbol_sucio()
	_accion_undo("Duplicar capas", do_fn, undo_fn)

## Elimina la selección del árbol (sin liberar, para poder deshacer). Un Undo.
func _eliminar_seleccion() -> void:
	var nodos := _seleccion_nodos()
	if nodos.is_empty():
		return
	var estados: Array = []
	for n in nodos:
		var p: Node = n.get_parent()
		if is_instance_valid(p):
			estados.append({"n": n, "p": p, "i": n.get_index()})
	if estados.is_empty():
		return
	var do_fn := func() -> void:
		for e in estados:
			if is_instance_valid(e["n"]) and e["n"].get_parent():
				e["n"].get_parent().remove_child(e["n"])
		var sm := get_node_or_null("/root/SelectionManager")
		if sm:
			sm.clear()
		_marcar_arbol_sucio()
	var undo_fn := func() -> void:
		var e2 := estados.duplicate()
		e2.sort_custom(func(a, b): return a["i"] < b["i"])
		for e in e2:
			if is_instance_valid(e["n"]) and is_instance_valid(e["p"]) and e["n"].get_parent() == null:
				e["p"].add_child(e["n"])
				e["p"].move_child(e["n"], mini(e["i"], e["p"].get_child_count() - 1))
		_marcar_arbol_sucio()
	_accion_undo("Eliminar capas", do_fn, undo_fn)

func _nombre_base(nombre: String) -> String:
	var re := RegEx.new()
	re.compile("^(.*?)[ _]\\d+$")
	var m := re.search(nombre)
	return m.get_string(1) if m else nombre

func _move_tool() -> Node:
	var st := get_tree()
	if st == null:
		return null
	var cv: Node = st.get_first_node_in_group("_vectopen_canvas")
	if cv and cv.has_method("get_current_tool"):
		var t = cv.get_current_tool()
		if t and t.has_method("get_class_name") and t.get_class_name() == "MoveTool":
			return t
	return null

# ── Agrupar / desagrupar / orden Z (con undo real) ──────────────────────────

func _seleccion_nodos() -> Array:
	var out: Array = []
	var sm := get_node_or_null("/root/SelectionManager")
	if sm:
		for n in sm.get_selected():
			if is_instance_valid(n) and n is Node2D:
				out.append(n)
	# Fallback: la selección VIVA del árbol (por si el envío diferido a
	# SelectionManager aún no corrió cuando se pulsa Ctrl+G justo tras el clic).
	if out.is_empty() and is_instance_valid(layer_tree):
		var it: TreeItem = layer_tree.get_next_selected(null)
		while it != null:
			var m = it.get_metadata(1)
			if is_instance_valid(m) and m is Node2D:
				out.append(m)
			it = layer_tree.get_next_selected(it)
	return out

## Mete las figuras seleccionadas en un grupo nuevo, conservando su transform
## global. El grupo se crea en el padre de la primera figura, en su índice.
func _agrupar_seleccion() -> void:
	var nodos := _seleccion_nodos()
	if nodos.size() < 1:
		return
	# Ordenar por índice de árbol para conservar el orden Z relativo.
	nodos.sort_custom(func(a, b): return a.get_index() < b.get_index())
	var padre: Node = nodos[0].get_parent()
	if not is_instance_valid(padre):
		return
	var idx_destino: int = nodos[0].get_index()
	var grupo := Node2D.new()
	grupo.name = NameUtils.unique_child_name(padre, "Grupo")
	grupo.set_meta("shape_type", "group")

	var estados: Array = []
	for n in nodos:
		estados.append({"n": n, "p": n.get_parent(), "i": n.get_index(),
			"gt": (n as Node2D).global_transform})

	# El grupo se coloca sobre la primera figura (dentro del artboard → sin el
	# aviso "fuera del artboard"). Los hijos conservan su transform global.
	var pos_grupo: Vector2 = (nodos[0] as Node2D).global_position
	var do_fn := func() -> void:
		if grupo.get_parent() == null:
			padre.add_child(grupo)
		padre.move_child(grupo, mini(idx_destino, padre.get_child_count() - 1))
		grupo.global_position = pos_grupo
		for n in nodos:
			if is_instance_valid(n):
				n.reparent(grupo, true)
		_seleccionar_solo(grupo)
		_marcar_arbol_sucio()
	var undo_fn := func() -> void:
		for e in estados:
			var n = e["n"]
			if is_instance_valid(n) and is_instance_valid(e["p"]):
				n.reparent(e["p"], true)
				e["p"].move_child(n, mini(e["i"], e["p"].get_child_count() - 1))
				(n as Node2D).global_transform = e["gt"]
		if is_instance_valid(grupo) and grupo.get_parent():
			grupo.get_parent().remove_child(grupo)
		_marcar_arbol_sucio()
	_accion_undo("Agrupar", do_fn, undo_fn)

## Saca los hijos del grupo a su padre y elimina el grupo.
func _desagrupar(grupo: Node) -> void:
	if not is_instance_valid(grupo):
		return
	var padre: Node = grupo.get_parent()
	if not is_instance_valid(padre):
		return
	# Si el grupo tiene una máscara stencil activa, quitarla antes de desagrupar
	# (si no, el contenido quedaría anidado bajo la figura-máscara).
	if _mascara_activa(grupo):
		var it := _node_to_item_map.get(grupo) as TreeItem
		_desactivar_mascara(it, grupo)
	var g_idx: int = grupo.get_index()
	var hijos: Array = []
	for h in grupo.get_children():
		if h is Node2D and _es_capa(h):
			hijos.append({"n": h, "gt": (h as Node2D).global_transform})

	var do_fn := func() -> void:
		var ins := g_idx
		for e in hijos:
			var n = e["n"]
			if is_instance_valid(n):
				n.reparent(padre, true)
				padre.move_child(n, mini(ins, padre.get_child_count() - 1))
				(n as Node2D).global_transform = e["gt"]
				ins += 1
		if is_instance_valid(grupo) and grupo.get_parent():
			grupo.get_parent().remove_child(grupo)
		_marcar_arbol_sucio()
	var undo_fn := func() -> void:
		if grupo.get_parent() == null:
			padre.add_child(grupo)
			padre.move_child(grupo, mini(g_idx, padre.get_child_count() - 1))
		for e in hijos:
			var n = e["n"]
			if is_instance_valid(n):
				n.reparent(grupo, true)
				(n as Node2D).global_transform = e["gt"]
		_marcar_arbol_sucio()
	_accion_undo("Desagrupar", do_fn, undo_fn)

func _cambiar_orden_z(modo: int) -> void:
	var nodos := _seleccion_nodos()
	if nodos.is_empty():
		return
	nodos.sort_custom(func(a, b): return a.get_index() < b.get_index())
	var previos: Array = []
	for n in nodos:
		previos.append({"n": n, "p": n.get_parent(), "i": n.get_index()})

	var do_fn := func() -> void:
		# Procesar de forma que el orden relativo de la selección se conserve.
		var lista := nodos.duplicate()
		if modo == _Ctx.AL_FRENTE or modo == _Ctx.ADELANTE:
			lista.reverse()
		for n in lista:
			if not is_instance_valid(n) or not is_instance_valid(n.get_parent()):
				continue
			var p: Node = n.get_parent()
			var last: int = p.get_child_count() - 1
			match modo:
				_Ctx.AL_FRENTE: p.move_child(n, last)
				_Ctx.AL_FONDO:  p.move_child(n, 0)
				_Ctx.ADELANTE:  p.move_child(n, mini(n.get_index() + 1, last))
				_Ctx.ATRAS:     p.move_child(n, maxi(n.get_index() - 1, 0))
		_repintar_canvas()
		_marcar_arbol_sucio()
	var undo_fn := func() -> void:
		for e in previos:
			var n = e["n"]
			if is_instance_valid(n) and is_instance_valid(e["p"]) and n.get_parent() == e["p"]:
				e["p"].move_child(n, mini(e["i"], e["p"].get_child_count() - 1))
		_repintar_canvas()
		_marcar_arbol_sucio()
	_accion_undo("Cambiar orden", do_fn, undo_fn)

func _seleccionar_solo(nodo: Node) -> void:
	var sm := get_node_or_null("/root/SelectionManager")
	if sm and is_instance_valid(nodo):
		sm.select(nodo)

## Pide una reconstrucción del árbol tras una acción que cambió la jerarquía
## (agrupar / desagrupar / duplicar / eliminar / orden Z). Diferido para
## coalescer varias señales de la misma acción.
func _marcar_arbol_sucio() -> void:
	if not _bloquear_sincronizacion:
		sincronizar_arbol_completo.call_deferred()

## Espacio sobre la fila enfocada → alterna visibilidad con undo.
func _on_key_toggle_visibility(item: TreeItem) -> void:
	if not is_instance_valid(item):
		return
	var nodo = item.get_metadata(1)
	if not is_instance_valid(nodo):
		return
	_accion_undo("Visibilidad de capa",
		func(): _set_vis(item, nodo, not nodo.visible),
		func(): _set_vis(item, nodo, not nodo.visible))

## Ctrl+Shift+G → desagrupa el primer grupo/artboard de la selección.
func _desagrupar_seleccion() -> void:
	for n in _seleccion_nodos():
		if is_instance_valid(n) and _tiene_hijos_capa(n):
			_desagrupar(n)
			return


# =============================================================================
# CONTROLADORES DE EVENTOS DE INTERFAZ Y LIENZO
# =============================================================================
func _on_layer_tree_item_edited() -> void:
	if _bloquear_sincronizacion or not is_instance_valid(layer_tree):
		return

	var item_editado = layer_tree.get_edited()
	if not item_editado:
		return

	var nodo_real : Node2D = item_editado.get_metadata(1) as Node2D
	if not is_instance_valid(nodo_real):
		return

	# Solo la columna 0 es editable (renombrar por doble clic).
	var texto : String = item_editado.get_text(0).strip_edges()
	if texto != "":
		nodo_real.name = texto
		item_editado.set_text(0, nodo_real.name)   # el nombre puede cambiar (dedup)
	else:
		item_editado.set_text(0, nodo_real.name)


func _on_node_added(nodo: Node) -> void:
	# Se dispara cuando se agrega un nodo
	if nodo is Node2D:
		_pending_changes.append({"node": nodo, "action": "added"})
		_schedule_update()

func _on_node_removed(nodo: Node) -> void:
	# Se dispara cuando se quita un nodo
	if nodo is Node2D:
		_pending_changes.append({"node": nodo, "action": "removed"})
		_schedule_update()

func _schedule_update() -> void:
	# (Re)arranca el timer one-shot: cada cambio nuevo reinicia la ventana de
	# 100 ms, así una ráfaga de N figuras se procesa en UN batch, no en N.
	# BUG previo: "and not is_stopped()" -> con el timer parado (lo normal) no
	# arrancaba nunca y los cambios incrementales no se procesaban; todo caía
	# en sincronizar_arbol_completo() = O(N²) al añadir figuras una a una.
	if _update_timer:
		_update_timer.start()

func _setup_update_timer() -> void:
	# Crear timer para actualizaciones batch
	_update_timer = Timer.new()
	_update_timer.wait_time = 0.1  # 100ms de batch
	_update_timer.timeout.connect(_process_pending_changes)
	_update_timer.one_shot = true
	add_child(_update_timer)

	# ── PERRO GUARDIÁN de `_bloquear_sincronizacion` ────────────────────────────
	# Ese flag solo debe estar en `true` DENTRO de una llamada síncrona
	# (sincronizar_arbol_completo / _process_pending_changes). Si un error de
	# ejecución aborta esa función a mitad, el flag se queda en `true` para
	# siempre → el panel de capas NO vuelve a sincronizarse nunca (nada de
	# drag-reparent, agrupar, duplicar…). Cada 0.5 s comprobamos: si sigue
	# bloqueado dos ticks seguidos (imposible en operación normal), lo forzamos
	# a `false` y pedimos una reconstrucción.
	_watchdog_timer = Timer.new()
	_watchdog_timer.wait_time = 0.5
	_watchdog_timer.one_shot = false
	_watchdog_timer.timeout.connect(_watchdog_sincronizacion)
	add_child(_watchdog_timer)
	_watchdog_timer.start()

func _watchdog_sincronizacion() -> void:
	if not _bloquear_sincronizacion:
		_watchdog_ticks_bloqueado = 0
		return
	_watchdog_ticks_bloqueado += 1
	if _watchdog_ticks_bloqueado >= 2:
		push_warning("LayerSystem: _bloquear_sincronizacion atascado — se fuerza el desbloqueo")
		_bloquear_sincronizacion = false
		_watchdog_ticks_bloqueado = 0
		if is_instance_valid(layer_tree) and is_instance_valid(artboard_container):
			sincronizar_arbol_completo.call_deferred()

func _process_pending_changes() -> void:
	if _pending_changes.is_empty() or _bloquear_sincronizacion:
		return
	
	_bloquear_sincronizacion = true
	var necesita_full := false

	for change in _pending_changes:
		var nodo = change["node"]
		var action = change["action"]
		if not is_instance_valid(nodo):
			continue

		if action == "added":
			if _node_to_item_map.has(nodo):
				continue  # ya está en el árbol
			var parent_node = nodo.get_parent()
			if parent_node and _node_to_item_map.has(parent_node):
				_create_tree_item(_node_to_item_map[parent_node], nodo, _encontrar_artboard_ancestro(nodo))
			elif artboard_container and artboard_container == parent_node:
				if _es_artboard(nodo):
					_vincular_senales_artboard(nodo)
					_create_tree_item(layer_tree.get_root(), nodo, nodo)
				else:
					# Figura SUELTA (hija directa del contenedor) → grupo "Fuera de artboard".
					_create_tree_item(_get_sueltos_item(), nodo, null)
			else:
				# Padre no mapeado (anidamiento profundo, orden raro): una
				# reconstrucción completa — O(N) UNA vez, no O(N) por figura.
				necesita_full = true

		elif action == "removed":
			if _node_to_item_map.has(nodo):
				var item: TreeItem = _node_to_item_map[nodo]
				_node_to_item_map.erase(nodo)
				if is_instance_valid(item):
					# Si tenía subelementos, sus entradas del map quedan colgando
					# apuntando a TreeItems que se van a liberar → una
					# reconstrucción completa (O(N) una vez) las purga.
					if item.get_child_count() > 0:
						necesita_full = true
					var padre := item.get_parent()
					if padre:
						padre.remove_child(item)

	_pending_changes.clear()
	_bloquear_sincronizacion = false

	if necesita_full:
		sincronizar_arbol_completo.call_deferred()
	else:
		_repintar_canvas()


# =============================================================================
# ASISTENTES TÉCNICOS Y RECONEXIÓN DINÁMICA
# =============================================================================

## Sube por los padres hasta encontrar el artboard directo de artboard_container
## al que pertenece nodo — usado por la ruta de alta incremental (drag&drop
## nuevo desde otra herramienta) para saber contra qué artboard comprobar
## "fuera de límites".
## Artboard al que pertenece `nodo` por jerarquía. null si es una figura
## SUELTA (hija directa del contenedor, fuera de todo artboard) o no cuelga
## de ningún artboard. Antes devolvía la propia figura suelta como si fuera
## un artboard → el aviso "fuera del artboard" no funcionaba con figuras sueltas.
func _encontrar_artboard_ancestro(nodo: Node) -> Node2D:
	var actual: Node = nodo
	while actual:
		if _es_artboard(actual):
			return actual as Node2D
		actual = actual.get_parent()
	return null

## Un artboard real (ArtboardEditor) o un doble con `artboard_size` (tests).
func _es_artboard(n: Node) -> bool:
	return n is ArtboardEditor or (n is Node2D and "artboard_size" in n)

func _vincular_senales_artboard(artboard: Node2D) -> void:
	# Conecta las señales del Artboard para enterarse de figuras nuevas/borradas
	# DENTRO de él. Va por la ruta incremental (_on_node_added/_removed → batch
	# de 100 ms), no por sincronizar_arbol_completo(): el batch ya difiere lo
	# suficiente para que la posición final de la figura esté asignada cuando
	# se evalúa el indicador "fuera del artboard".
	if not artboard in _artboards_conectados:
		_artboards_conectados.append(artboard)
		if not artboard.child_entered_tree.is_connected(_on_node_added):
			artboard.child_entered_tree.connect(_on_node_added)
		if not artboard.child_exiting_tree.is_connected(_on_node_removed):
			artboard.child_exiting_tree.connect(_on_node_removed)


## Compat: algo externo puede seguir llamando a este nombre. Rutea al batch.
func _on_canvas_structure_changed(nodo: Node) -> void:
	if nodo is Node2D:
		var action := "added" if nodo.is_inside_tree() else "removed"
		_pending_changes.append({"node": nodo, "action": action})
		_schedule_update()

func _aplicar_estilo_visibilidad(item: TreeItem, esta_visible: bool, tipo: String) -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var c_text: Color = tm.get_color(S.PANEL_TEXT) if tm else Color(0.11, 0.11, 0.12)
	var c_dim: Color = tm.get_color(S.TEXT_DISABLED) if tm else Color(0.56, 0.56, 0.58)
	var c_group: Color = tm.get_color(S.ACCENT) if tm else Color(0.04, 0.52, 1.0)
	if not esta_visible:
		item.set_custom_color(0, c_dim)
	elif tipo == "group":
		item.set_custom_color(0, c_group)
	else:
		item.set_custom_color(0, c_text)


func _repintar_canvas() -> void:
	if is_instance_valid(artboard_container):
		var raiz_canvas = artboard_container.get_parent()
		if raiz_canvas and raiz_canvas.has_method("queue_redraw"):
			raiz_canvas.queue_redraw()
	_actualizar_contador()


## Cuenta los Node2D dibujables dentro de cada artboard (sin contar el propio
## artboard ni los auxiliares de las herramientas) y lo escribe en el label.
func _actualizar_contador() -> void:
	if not is_instance_valid(_contador_label) or not is_instance_valid(artboard_container):
		return
	var total := 0
	var artboards := 0
	var sueltos := 0
	for ab in artboard_container.get_children():
		if _es_artboard(ab):
			artboards += 1
			total += _contar_descendientes(ab)
		elif ab is Node2D and ab.name != "Contorno_Stroke":
			sueltos += 1
			total += 1 + _contar_descendientes(ab)
	var txt := "%d capas" % total
	if artboards > 1:
		txt += " · %d artboards" % artboards
	if sueltos > 0:
		txt += " · %d fuera" % sueltos
	_contador_label.text = txt


func _contar_descendientes(nodo: Node) -> int:
	var n := 0
	for hijo in nodo.get_children():
		if hijo is Node2D and hijo.name != "Contorno_Stroke":
			n += 1
			n += _contar_descendientes(hijo)
	return n
