# =============================================================================
# RUTA: res://script_gdscript/api/vectopen_api.gd
# API PÚBLICA de Vectopen para scripts (pestaña Script) y complementos.
#
# Es la ÚNICA puerta que un script o complemento necesita: crear figuras,
# leer/escribir propiedades (las mismas del Inspector), selección, artboards,
# grupos, borrar/duplicar, importar SVG, deshacer/rehacer y registrar
# operadores/paneles (complementos). Por dentro usa los sistemas reales
# (InspectorCore, HistoryManager, SelectionManager, ArtboardManager), así que
# lo que hace un script es idéntico a lo que hace el usuario a mano.
#
# DESHACER: todo lo que se haga entre begin()/end() (o dentro de
# transaction()) es UN solo paso de deshacer. Fuera de una transacción, cada
# llamada que modifica es su propio paso. La pestaña Script envuelve cada
# ejecución en una transacción: "Ctrl+Z" deshace el script entero.
#
# Coordenadas: las de documento del artboard (origen arriba-izquierda);
# las figuras se colocan por su CENTRO, como en la app.
#
# Estabilidad: lo documentado con "##" es la API estable (API_VERSION). Los
# métodos que empiezan por "_" son internos y pueden cambiar.
# =============================================================================
class_name VectopenAPI
extends RefCounted

const API_VERSION := "1.0"
const SvgImport = preload("res://script_gdscript/system/svg_import.gd")

## Referencia de la API (autocompletado y ayuda de la pestaña Script).
## [grupo, firma, descripción]. Un test comprueba que coincide con el código.
const REFERENCE := [
	["Información", "version() -> String", "Versión de la API"],
	["Información", "info(texto)", "Escribe en la consola (también print())"],
	["Información", "warn(texto)", "Aviso en la consola"],
	["Información", "error(texto)", "Error: el script cuenta como fallido y se deshace"],
	["Información", "wait(segundos)", "Pausa (usar con await)"],
	["Artboards", "artboard() -> Node2D", "Artboard activo"],
	["Artboards", "artboards() -> Array", "Todos los artboards"],
	["Artboards", "set_active_artboard(artboard)", "Cambia el artboard activo"],
	["Artboards", "artboard_size(artboard = null) -> Vector2", "Tamaño del artboard"],
	["Consulta", "shapes(padre = null, recursivo = false) -> Array", "Objetos del artboard (o de un grupo)"],
	["Consulta", "find(nombre) -> Node2D", "Objeto por nombre"],
	["Consulta", "kind_of(objeto) -> String", "rectangle, ellipse, polygon, star, path, text, image, group…"],
	["Consulta", "is_shape(nodo) -> bool", "¿Es un objeto del documento?"],
	["Selección", "selection() -> Array", "Objetos seleccionados"],
	["Selección", "select(objeto_o_lista)", "Selecciona"],
	["Selección", "clear_selection()", "Quita la selección"],
	["Propiedades", "props() -> Array", "Nombres de propiedades del Inspector"],
	["Propiedades", "get_prop(objeto, prop)", "Lee una propiedad (Inspector o del nodo)"],
	["Propiedades", "set_prop(objeto, prop, valor) -> bool", "Cambia una propiedad (con deshacer)"],
	["Propiedades", "set_props(objeto, {prop: valor})", "Varias a la vez"],
	["Propiedades", "set_fill(objeto, color)", "Color de relleno"],
	["Propiedades", "set_stroke(objeto, color, grosor = -1)", "Color y grosor del trazo"],
	["Propiedades", "get_position(objeto) -> Vector2", "Centro en coordenadas del artboard"],
	["Propiedades", "set_position(objeto, pos)", "Mueve el centro a pos"],
	["Propiedades", "move(objeto, delta)", "Desplaza"],
	["Propiedades", "set_rotation(objeto, grados)", "Rotación en grados"],
	["Crear", "add_rect(centro, tamaño, radio = 0) -> Node2D", "Rectángulo"],
	["Crear", "add_ellipse(centro, tamaño) -> Node2D", "Elipse / círculo"],
	["Crear", "add_polygon(centro, radio, lados, radio_esquinas = 0) -> Node2D", "Polígono regular"],
	["Crear", "add_star(centro, radio, puntas = 5, ratio_interior = 0.5) -> Node2D", "Estrella"],
	["Crear", "add_shape(puntos) -> Node2D", "Polígono libre por vértices"],
	["Crear", "add_path(puntos, cerrado = false) -> Node2D", "Trazado de líneas rectas"],
	["Crear", "add_curve(curve2d, cerrado = false) -> Node2D", "Trazado Bézier (Curve2D con tiradores)"],
	["Crear", "add_line(a, b, grosor = 2, color = negro) -> Node2D", "Línea"],
	["Crear", "add_text(pos, texto, tamaño = 24, color = negro) -> Node2D", "Texto (pos = arriba-izquierda)"],
	["Crear", "import_svg(svg_texto, pos = (0,0)) -> Node2D", "SVG como grupo de trazados"],
	["Crear", "add(nodo, padre = null) -> Node2D", "Añade un nodo ya configurado"],
	["Organizar", "delete(objeto_o_lista)", "Borra"],
	["Organizar", "duplicate(objeto, desplazamiento = (20,20)) -> Node2D", "Copia"],
	["Organizar", "group(lista, nombre = \"Grupo\") -> Node2D", "Agrupa"],
	["Organizar", "arrange(objeto, donde)", "Orden de capas: front, back, up, down"],
	["Organizar", "align(lista, modo)", "left, center_h, right, top, middle, bottom ([] = selección)"],
	["Organizar", "distribute(lista, eje)", "Reparte 3+ objetos: \"h\" o \"v\""],
	["Organizar", "boolean(op, lista) -> Node", "union, subtract, intersect, exclude, flatten, release"],
	["Efectos", "effect_types() -> Array", "Tipos de efecto (Drop Shadow, Blur, 3D…)"],
	["Efectos", "add_effect(objeto, tipo, params = {}) -> Dictionary", "Añade un efecto"],
	["Efectos", "clear_effects(objeto, tipo = \"\")", "Quita efectos"],
	["Efectos", "filter_types() -> Array", "Tipos de filtro (glass, grain, neon…)"],
	["Efectos", "add_filter(objeto, tipo, params = {}) -> Dictionary", "Añade un filtro"],
	["Efectos", "clear_filters(objeto)", "Quita los filtros"],
	["Shaders", "shaders() -> Array", "Shaders guardados en la biblioteca"],
	["Shaders", "shader_templates() -> Array", "Plantillas de shader"],
	["Shaders", "shader_code(nombre) -> String", "Código de un shader o plantilla"],
	["Shaders", "save_shader(nombre, codigo) -> Array", "Guarda en la biblioteca; devuelve errores"],
	["Shaders", "apply_shader(objeto_o_lista, nombre_o_codigo) -> bool", "Aplica un shader"],
	["Shaders", "remove_shader(objeto_o_lista)", "Quita el shader"],
	["Shaders", "get_shader(objeto) -> Dictionary", "Shader aplicado ({} si no hay)"],
	["Documento", "add_artboard(tamaño, nombre) -> Node2D", "Artboard nuevo (y activo)"],
	["Documento", "add_image(ruta_o_image, centro) -> Node2D", "Imagen"],
	["Documento", "export(ruta, artboard = null, opciones = {}) -> bool", ".svg .pdf .eps .png .jpg .webp .vop .tscn .scn (await)"],
	["Documento", "svg(artboard = null) -> String", "SVG del artboard como texto"],
	["Documento", "vectorize_presets() -> Array", "Presets de vectorización"],
	["Documento", "vectorize(imagen, preset, ocultar = true) -> Node2D", "Imagen → trazados Bézier (await)"],
	["Deshacer", "begin(nombre)", "Abre un paso de deshacer"],
	["Deshacer", "end()", "Cierra el paso abierto con begin()"],
	["Deshacer", "transaction(nombre, funcion)", "Ejecuta funcion como un paso"],
	["Deshacer", "rollback()", "Deshace lo hecho desde begin()"],
	["Deshacer", "in_transaction() -> bool", "¿Hay un paso abierto?"],
	["Deshacer", "undo()", "Deshacer"],
	["Deshacer", "redo()", "Rehacer"],
	["Complementos", "register_operator(id, etiqueta, funcion, ayuda = \"\")", "Registra una acción"],
	["Complementos", "unregister_operator(id)", "Quita una acción"],
	["Complementos", "operators(complemento = \"\") -> Array", "Acciones registradas"],
	["Complementos", "run_operator(id) -> bool", "Ejecuta una acción registrada"],
]

## Nombre del método de una entrada de REFERENCE ("add_rect(…)" → "add_rect").
static func reference_method(entry: Array) -> String:
	return String(entry[1]).get_slice("(", 0)

## Mensajes de los scripts / complementos (`info`, `warn`, `error`).
## (`print()` dentro de un script también llega a la consola.)
signal message(text: String, level: String)
## La selección del canvas cambió.
signal selection_changed(nodes: Array)

var _host: Node = null
var _tx: Array = []          # [{do: Callable, undo: Callable}]
var _tx_depth := 0
var _tx_name := ""
var _tx_dirty := false       # hay escrituras de propiedades pendientes de aviso
var _ops: Dictionary = {}    # id -> {label, callable, owner, tooltip}

func _init(host: Node = null) -> void:
	_host = host
	var ge := _n("GlobalEvents")
	if ge and ge.has_signal("selection_changed"):
		ge.selection_changed.connect(func(s: Array) -> void: selection_changed.emit(s))

func _n(autoload: String) -> Node:
	if not is_instance_valid(_host) or not _host.is_inside_tree():
		return null
	return _host.get_node_or_null("/root/" + autoload)

# ── información ──────────────────────────────────────────────────────────────
## Versión de esta API ("1.0").
func version() -> String:
	return API_VERSION

## Escribe en la consola de la pestaña Script (y en la salida de Godot).
func info(text: Variant) -> void:
	print("[Vectopen] ", text)
	message.emit(str(text), "info")

func warn(text: Variant) -> void:
	push_warning(str(text))
	message.emit(str(text), "warning")

func error(text: Variant) -> void:
	push_error(str(text))
	message.emit(str(text), "error")

## Espera `seconds` (usar con await dentro de run(): `await api.wait(0.2)`).
func wait(seconds: float) -> void:
	if is_instance_valid(_host) and _host.is_inside_tree():
		await _host.get_tree().create_timer(seconds).timeout

# ── artboards ────────────────────────────────────────────────────────────────
func _manager() -> Node:
	if not is_instance_valid(_host) or not _host.is_inside_tree():
		return null
	return ArtboardManager.find(_host.get_tree())

## Artboard activo (donde se crean las figuras).
func artboard() -> Node2D:
	var m := _manager()
	if m:
		return m.get_active_artboard()
	var canvas := _host.get_tree().get_first_node_in_group("_vectopen_canvas") if _host and _host.is_inside_tree() else null
	var c = canvas.get_node_or_null("ArtboardsContainer") if canvas else null
	if c:
		for ch in c.get_children():
			if "artboard_size" in ch:
				return ch
	return null

## Todos los artboards del documento.
func artboards() -> Array:
	var m := _manager()
	return Array(m.all_artboards()) if m else ([artboard()] if artboard() else [])

func set_active_artboard(ab: Node2D) -> void:
	var m := _manager()
	if m and is_instance_valid(ab):
		m.set_active_artboard(ab)

## Tamaño del artboard (activo si no se indica).
func artboard_size(ab: Node2D = null) -> Vector2:
	var a := ab if ab else artboard()
	return a.artboard_size if a and "artboard_size" in a else Vector2.ZERO

# ── consulta ─────────────────────────────────────────────────────────────────
## ¿Es `n` un objeto del documento (figura, texto, imagen, grupo)?
static func is_shape(n: Node) -> bool:
	if n == null or not (n is Node2D) or n.name in ["Contorno_Stroke", "Render_Visual"]:
		return false
	if "artboard_size" in n:
		return false
	if n is VectorShape or n is Line2D or n is Polygon2D or n is Sprite2D or n is Path2D:
		return true
	return n.has_meta("shape_type") or n.get_child_count() > 0

## Tipo legible: rectangle, ellipse, polygon, star, path, text, image, group…
func kind_of(n: Node) -> String:
	if not is_instance_valid(n):
		return ""
	if n is VectorRectangle: return "rectangle"
	if n is VectorCircle: return "ellipse"
	if n is VectorStar: return "star"
	if n is VectorPolygon: return "drop" if String(n.get_meta("shape_kind", "")) == "drop" else "polygon"
	if n is Path2D: return "path"
	if n is Line2D: return "line"
	if n is Sprite2D: return "image"
	if n is Polygon2D: return "polygon2d"
	var st := String(n.get_meta("shape_type", ""))
	if st.begins_with("text"): return "text"
	if st != "": return st
	return "group" if n.get_child_count() > 0 else "node"

## Objetos de `parent` (por defecto el artboard activo). `recursive` entra
## en los grupos.
func shapes(parent: Node = null, recursive: bool = false) -> Array:
	var p := parent if parent else artboard()
	var out: Array = []
	if p == null:
		return out
	for ch in p.get_children():
		if is_shape(ch):
			out.append(ch)
			if recursive and kind_of(ch) == "group":
				out.append_array(shapes(ch, true))
	return out

## Primer objeto con ese nombre (busca en todo el artboard activo).
func find(name: String, parent: Node = null) -> Node2D:
	for s in shapes(parent, true):
		if String(s.name) == name:
			return s
	return null

# ── selección ────────────────────────────────────────────────────────────────
func selection() -> Array:
	var sm := _n("SelectionManager")
	if sm and sm.has_method("get_selected"):
		return Array(sm.get_selected()).filter(func(s) -> bool: return is_instance_valid(s))
	return []

func select(nodes: Variant) -> void:
	var sm := _n("SelectionManager")
	if sm:
		sm.set_selection(nodes if nodes is Array else [nodes])

func clear_selection() -> void:
	var sm := _n("SelectionManager")
	if sm:
		sm.clear()

# ── propiedades ──────────────────────────────────────────────────────────────
## Propiedades del Inspector (las que `get_prop`/`set_prop` entienden siempre).
func props() -> Array:
	var ic := _n("InspectorCore")
	return Array(ic.PROPS) if ic else []

## Lee una propiedad. Acepta las del Inspector ("fill_color", "width",
## "corner_radius", "text"…) y cualquier propiedad del nodo ("position"…).
func get_prop(node: Node, prop: String) -> Variant:
	if not is_instance_valid(node):
		return null
	var ic := _n("InspectorCore")
	if ic and prop in ic.PROPS:
		return ic._read(node, prop)
	return node.get(prop) if prop in node else node.get_meta(prop, null)

## Cambia una propiedad (con deshacer). Devuelve false si no existe.
func set_prop(node: Node, prop: String, value: Variant) -> bool:
	if not is_instance_valid(node):
		error("set_prop: objeto no válido")
		return false
	var ic := _n("InspectorCore")
	var before: Variant = null
	var writer: Callable
	if ic and prop in ic.PROPS and ic._read(node, prop) != null:
		before = ic._read(node, prop)
		writer = func(v: Variant) -> void: ic._write(node, prop, v)
	elif prop in node:
		before = node.get(prop)
		writer = func(v: Variant) -> void:
			node.set(prop, v)
			if node is CanvasItem:
				node.queue_redraw()
	else:
		error("set_prop: «%s» no tiene la propiedad «%s»" % [node.name, prop])
		return false
	writer.call(value)
	_tx_dirty = true
	_record("Script · %s" % prop,
		func() -> void:
			if is_instance_valid(node): writer.call(value),
		func() -> void:
			if is_instance_valid(node): writer.call(before),
		true)
	return true

## Varias propiedades a la vez: {"fill_color": Color.RED, "width": 200}.
func set_props(node: Node, values: Dictionary) -> void:
	begin("Script · propiedades")
	for k in values:
		set_prop(node, String(k), values[k])
	end()

func set_fill(node: Node, color: Color) -> void:
	set_prop(node, "fill_color", color)

func set_stroke(node: Node, color: Color, width: float = -1.0) -> void:
	begin("Script · trazo")
	set_prop(node, "stroke_color", color)
	if width >= 0.0:
		set_prop(node, "stroke_width", width)
	end()

## Centro del objeto en coordenadas del artboard.
func get_position(node: Node) -> Vector2:
	return Vector2(float(get_prop(node, "pos_x")), float(get_prop(node, "pos_y"))) \
		if node is VectorShape else (node as Node2D).position

func set_position(node: Node, pos: Vector2) -> void:
	if node is VectorShape:
		begin("Script · mover")
		set_prop(node, "pos_x", pos.x)
		set_prop(node, "pos_y", pos.y)
		end()
	else:
		set_prop(node, "position", pos)

func move(node: Node, delta: Vector2) -> void:
	set_position(node, get_position(node) + delta)

## Rotación en GRADOS.
func set_rotation(node: Node, degrees: float) -> void:
	set_prop(node, "rotation", degrees)

# ── crear ────────────────────────────────────────────────────────────────────
func _style_new(node: Node2D) -> void:
	var dp := _n("DrawPreferences")
	if "fill_color" in node:
		node.set("fill_color", dp.fill_color if dp else Color(0.88, 0.88, 0.88))
		node.set("stroke_color", dp.stroke_color if dp else Color(0.1, 0.1, 0.1))
		node.set("stroke_width", float(dp.get("stroke_width")) if dp and dp.get("stroke_width") != null else 2.0)

## Añade `node` (ya configurado) al artboard activo o a `parent`, con deshacer.
func add(node: Node2D, parent: Node = null) -> Node2D:
	var p := parent if parent else artboard()
	if p == null or not is_instance_valid(node):
		error("add: no hay artboard activo")
		return null
	if String(node.name) == "" or String(node.name).begins_with("@"):
		node.name = "Objeto"
	node.name = NameUtils.unique_child_name(p, String(node.name))
	p.add_child(node)
	node.owner = p if "artboard_size" in p else p.owner
	var idx := node.get_index()
	_record("Crear %s" % node.name,
		func() -> void:
			if is_instance_valid(node) and is_instance_valid(p) and node.get_parent() == null:
				p.add_child(node)
				p.move_child(node, mini(idx, p.get_child_count() - 1)),
		func() -> void:
			if is_instance_valid(node) and node.get_parent() == p:
				var sm := _n("SelectionManager")
				if sm and sm.is_selected(node):
					sm.deselect(node)
				p.remove_child(node),
		false)
	var ge := _n("GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_created")
	return node

## Rectángulo centrado en `center`.
func add_rect(center: Vector2, size: Vector2, radius: float = 0.0, name: String = "Rectángulo") -> Node2D:
	var r := VectorRectangle.new()
	r.name = name
	r.size = size
	r.set_doc_position(DVec2.from_v2(center))
	r.corner_radius = radius
	_style_new(r)
	return add(r)

## Elipse (o círculo) centrada en `center`.
func add_ellipse(center: Vector2, size: Vector2, name: String = "Elipse") -> Node2D:
	var c := VectorCircle.new()
	c.name = name
	c.size = size
	c.set_doc_position(DVec2.from_v2(center))
	_style_new(c)
	return add(c)

## Polígono regular de `sides` lados (3 = triángulo … 64 ≈ círculo).
func add_polygon(center: Vector2, radius: float, sides: int, corner_radius: float = 0.0, name: String = "") -> Node2D:
	var p := VectorPolygon.new()
	p.name = name if name != "" else "Polígono %d" % sides
	p.set_doc_position(DVec2.from_v2(center))
	p.radius = radius
	p.corner_radius = corner_radius
	p.sides = clampi(sides, 3, 128)
	p.is_regular = true
	_style_new(p)
	return add(p)

## Estrella de `points` puntas; `inner_ratio` = radio interior / exterior.
func add_star(center: Vector2, radius: float, points: int = 5, inner_ratio: float = 0.5, name: String = "Estrella") -> Node2D:
	var s := VectorStar.new()
	s.name = name
	s.size = Vector2(radius, radius) * 2.0
	s.points_count = clampi(points, 3, 64)
	s.inner_radius_ratio = clampf(inner_ratio, 0.05, 0.95)
	s.set_doc_position(DVec2.from_v2(center))
	_style_new(s)
	return add(s)

## Polígono libre por sus vértices (coordenadas del artboard).
func add_shape(points: PackedVector2Array, name: String = "Forma") -> Node2D:
	if points.size() < 3:
		error("add_shape: hacen falta 3 puntos o más")
		return null
	var c := Vector2.ZERO
	for v in points:
		c += v
	c /= points.size()
	var local := PackedVector2Array()
	for v in points:
		local.append(v - c)
	var p := VectorPolygon.new()
	p.name = name
	p.is_regular = false
	p.set_doc_position(DVec2.from_v2(c))
	p.set_doc_vertices(DVec2.array_from_v2(local))
	_style_new(p)
	return add(p)

## Trazado por puntos (líneas rectas). `closed` cierra y rellena.
func add_path(points: PackedVector2Array, closed: bool = false, name: String = "Trazado") -> Node2D:
	var curve := Curve2D.new()
	for v in points:
		curve.add_point(v)
	return add_curve(curve, closed, name)

## Trazado Bézier: Curve2D con tiradores (in/out) en coordenadas del artboard.
func add_curve(curve: Curve2D, closed: bool = false, name: String = "Trazado") -> Node2D:
	if curve == null or curve.point_count < 2:
		error("add_curve: hacen falta 2 puntos o más")
		return null
	var path := VectorPath.new()
	path.name = name
	path.curve = curve
	path.closed = closed
	_style_new(path)
	if not closed:
		path.fill_color = Color(0, 0, 0, 0)
	return add(path)

## Línea recta de `a` a `b`.
func add_line(a: Vector2, b: Vector2, width: float = 2.0, color: Color = Color.BLACK) -> Node2D:
	var n := add_path(PackedVector2Array([a, b]), false, "Línea")
	if n:
		n.stroke_width = width
		n.stroke_color = color
	return n

## Texto; `pos` = esquina superior izquierda.
func add_text(pos: Vector2, text: String, font_size: int = 24, color: Color = Color.BLACK) -> Node2D:
	var t := Node2D.new()
	t.name = "Texto"
	t.set_meta("shape_type", "text_title")
	t.set_meta("text", text)
	t.set_meta("font_size", font_size)
	t.set_meta("text_color", color)
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = font_size
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	t.add_child(label)
	var edit := TextEdit.new()
	edit.name = "TitleEdit"
	edit.visible = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	t.add_child(edit)
	if ClassDB.class_exists("VectorRichText"):
		var vrt = ClassDB.instantiate("VectorRichText")
		vrt.name = "VectorRichText"
		vrt.set_is_paragraph(false)
		TextCore.apply_vrt_fonts(vrt, t)
		# set_text() reinicia el formato del nativo: primero el texto, después
		# color y tamaño (antes salía siempre a 24 px y en negro).
		vrt.set_text(text)
		vrt.set_text_color(color)
		vrt.set_font_size(float(font_size))
		t.add_child(vrt)
		label.visible = false
	t.position = pos
	var size := label.get_theme_font(&"font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) \
		if label.get_theme_font(&"font") else Vector2(text.length() * font_size * 0.6, font_size * 1.2)
	t.set_meta("size", size)
	return add(t)

## Importa un SVG (texto) como grupo de objetos editables (trazados Bézier,
## texto, imágenes). `pos` = esquina sup.-izq. del SVG en el artboard.
func import_svg(svg_text: String, pos: Vector2 = Vector2.ZERO, name: String = "SVG") -> Node2D:
	var data := SvgImport.parse(svg_text)
	if (data["items"] as Array).is_empty():
		error("import_svg: el SVG no tiene nada que importar")
		return null
	var g := SvgImport.build(data, name)
	g.position = pos
	return add(g)

# ── organizar ────────────────────────────────────────────────────────────────
## Borra objetos (con deshacer).
func delete(nodes: Variant) -> void:
	var list: Array = nodes if nodes is Array else [nodes]
	var recs: Array = []
	var sm := _n("SelectionManager")
	for n in list:
		if is_instance_valid(n) and n.get_parent():
			recs.append([n, n.get_parent(), n.get_index()])
	if recs.is_empty():
		return
	for r in recs:
		if sm and sm.is_selected(r[0]):
			sm.deselect(r[0])
		r[1].remove_child(r[0])
	_record("Eliminar",
		func() -> void:
			for r in recs:
				if is_instance_valid(r[0]) and r[0].get_parent() == r[1]:
					r[1].remove_child(r[0]),
		func() -> void:
			for i in range(recs.size() - 1, -1, -1):
				var r: Array = recs[i]
				if is_instance_valid(r[0]) and is_instance_valid(r[1]) and r[0].get_parent() == null:
					r[1].add_child(r[0])
					r[1].move_child(r[0], mini(r[2], r[1].get_child_count() - 1)),
		false)
	var ge := _n("GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_deleted")

## Copia un objeto (desplazado `offset`) y devuelve la copia.
func duplicate(node: Node2D, offset: Vector2 = Vector2(20, 20)) -> Node2D:
	if not is_instance_valid(node) or node.get_parent() == null:
		return null
	var c: Node2D = node.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	var added := add(c, node.get_parent())
	if added and offset != Vector2.ZERO:
		if added is VectorShape:
			added.set_doc_position(DVec2.from_v2(node.get_doc_position().to_v2() + offset))
		else:
			added.position = node.position + offset
	return added

## Agrupa objetos del mismo padre en un grupo nuevo.
func group(nodes: Array, name: String = "Grupo") -> Node2D:
	var valid: Array = nodes.filter(func(n) -> bool: return is_instance_valid(n) and n.get_parent() != null)
	if valid.is_empty():
		return null
	var parent: Node = valid[0].get_parent()
	valid.sort_custom(func(a, b) -> bool: return a.get_index() < b.get_index())
	var g := Node2D.new()
	g.name = NameUtils.unique_child_name(parent, name)
	g.set_meta("shape_type", "group")
	var first_idx: int = valid[0].get_index()
	var moves: Array = []   # [node, index]
	for n in valid:
		moves.append([n, n.get_index()])
	var do_fn := func() -> void:
		if g.get_parent() == null:
			parent.add_child(g)
			parent.move_child(g, mini(first_idx, parent.get_child_count() - 1))
			g.owner = parent if "artboard_size" in parent else parent.owner
		for m in moves:
			if is_instance_valid(m[0]) and m[0].get_parent() == parent:
				parent.remove_child(m[0])
				g.add_child(m[0])
				m[0].owner = g.owner
	var undo_fn := func() -> void:
		for i in range(moves.size()):
			var m: Array = moves[i]
			if is_instance_valid(m[0]) and m[0].get_parent() == g:
				g.remove_child(m[0])
				parent.add_child(m[0])
				parent.move_child(m[0], mini(m[1], parent.get_child_count() - 1))
				m[0].owner = g.owner
		if g.get_parent() == parent:
			parent.remove_child(g)
	do_fn.call()
	_record("Agrupar", do_fn, undo_fn, false)
	return g

# ── orden (capas) ────────────────────────────────────────────────────────────
## Cambia el orden de apilado: "front" (arriba del todo), "back", "up", "down".
func arrange(node: Node, where: String) -> void:
	if not is_instance_valid(node) or node.get_parent() == null:
		return
	var p := node.get_parent()
	var before := node.get_index()
	var last := p.get_child_count() - 1
	var after := before
	match where:
		"front": after = last
		"back": after = 0
		"up": after = mini(before + 1, last)
		"down": after = maxi(before - 1, 0)
		_:
			error("arrange: usa front, back, up o down")
			return
	if after == before:
		return
	p.move_child(node, after)
	_record("Orden",
		func() -> void:
			if is_instance_valid(node) and node.get_parent() == p: p.move_child(node, after),
		func() -> void:
			if is_instance_valid(node) and node.get_parent() == p: p.move_child(node, before),
		false)
	_tx_dirty = true
	if _tx_depth == 0:
		_flush()

# ── alinear, distribuir, booleanas ───────────────────────────────────────────
## Alinea objetos (o la selección si `nodes` está vacío). `mode`: left,
## center_h, right, top, middle, bottom (o una lista de ellos). Con un solo
## objeto se alinea al artboard.
func align(nodes: Array, mode: Variant) -> void:
	_with_selection(nodes, func() -> void:
		var ic := _n("InspectorCore")
		if ic: ic.align(mode))

## Reparte 3 objetos o más con el mismo espacio. `axis`: "h" o "v".
func distribute(nodes: Array, axis: String) -> void:
	_with_selection(nodes, func() -> void:
		var ic := _n("InspectorCore")
		if ic: ic.distribute(axis))

## Operación booleana: "union", "subtract", "intersect", "exclude",
## "flatten" (convertir en trazado) o "release" (deshacer la booleana).
## Devuelve el objeto resultante.
func boolean(op: String, nodes: Array) -> Node:
	var bc := _n("BooleanCore")
	if bc == null:
		return null
	var res: Array = [null]
	_absorb("Booleana " + op, func() -> void:
		res[0] = bc.apply_operation(op, nodes))
	if res[0] == null and not (op in ["release"]):
		error("boolean: no se pudo aplicar «%s» (¿2 objetos o más?)" % op)
	return res[0]

## Selecciona `nodes` (si hay), ejecuta `fn` y restaura la selección.
func _with_selection(nodes: Array, fn: Callable) -> void:
	var prev := selection()
	if not nodes.is_empty():
		select(nodes)
	var ic := _n("InspectorCore")
	if ic:
		ic._sync_selection()
	_absorb("Alinear", fn)
	if not nodes.is_empty():
		select(prev)

## Ejecuta `fn` (que usa un sistema de la app con su propio deshacer) y
## convierte los pasos que registró en parte de ESTE paso/transacción.
func _absorb(action_name: String, fn: Callable) -> void:
	var hm := _n("HistoryManager")
	var ur = hm._undo_redo if hm and "_undo_redo" in hm else null
	if ur == null:
		fn.call()
		return
	var n0: int = ur.undo_stack.size()
	fn.call()
	if ur.undo_stack.size() <= n0:
		return
	var actions: Array = ur.undo_stack.slice(n0)
	ur.undo_stack.resize(n0)
	_record(action_name,
		func() -> void:
			for a in actions:
				for c in a.do_callables:
					c.call(),
		func() -> void:
			for i in range(actions.size() - 1, -1, -1):
				var cs: Array = actions[i].undo_callables
				for j in range(cs.size() - 1, -1, -1):
					cs[j].call(),
		false)
	ur.version_changed.emit(ur.can_undo(), ur.can_redo())

# ── efectos, filtros y shaders ───────────────────────────────────────────────
## Tipos de efecto: Drop Shadow, Inner Shadow, Outline, Blur, Color Overlay,
## Gradient Overlay, Inner Glow, 3D, Bevel Emboss, Extrusion.
func effect_types() -> Array:
	return Array(EffectsPanel.EFFECT_ORDER)

## Añade un efecto con sus valores por defecto + `params`. Devuelve el efecto.
func add_effect(node: Node, type: String, params: Dictionary = {}) -> Dictionary:
	if not (type in EffectsPanel.EFFECT_ORDER):
		error("add_effect: tipo desconocido «%s». Usa effect_types()" % type)
		return {}
	var fx := EffectsPanel.default_effect(type)
	fx.merge(params, true)
	var list: Array = get_prop(node, "effects") if get_prop(node, "effects") is Array else []
	list.append(fx)
	set_prop(node, "effects", list)
	return fx

## Quita todos los efectos (o solo los de `type`).
func clear_effects(node: Node, type: String = "") -> void:
	var list: Array = get_prop(node, "effects") if get_prop(node, "effects") is Array else []
	set_prop(node, "effects", [] if type == "" else list.filter(func(f) -> bool: return String(f.get("type", "")) != type))

## Tipos de filtro: glass, grain, duotone, neon, halftone, pixelate, chromatic…
func filter_types() -> Array:
	return FilterFx.DEFAULTS.keys()

## Añade un filtro con sus valores por defecto + `params`.
func add_filter(node: Node, type: String, params: Dictionary = {}) -> Dictionary:
	var f := FilterFx.make(type)
	if not FilterFx.DEFAULTS.has(String(f["type"])):
		error("add_filter: tipo desconocido «%s». Usa filter_types()" % type)
		return {}
	f.merge(params, true)
	var list: Array = (get_prop(node, "filters") as Array).duplicate(true) if get_prop(node, "filters") is Array else []
	list.append(f)
	set_prop(node, "filters", list)
	return f

func clear_filters(node: Node) -> void:
	set_prop(node, "filters", [])

## Nombres de los shaders guardados en la biblioteca (pestaña Shader).
func shaders() -> Array:
	return ShaderLib.list().map(func(it) -> String: return String(it["name"]))

## Nombres de las plantillas de shader.
func shader_templates() -> Array:
	return ShaderLib.TEMPLATES.keys()

## Código de un shader guardado o de una plantilla ("" si no existe).
func shader_code(name: String) -> String:
	for it in ShaderLib.list():
		if String(it["name"]) == name:
			return ShaderLib.load_code(String(it["path"]))
	if ShaderLib.TEMPLATES.has(name):
		return ShaderLib.template_code(name)
	return ""

## Guarda un shader en la biblioteca. Devuelve los errores ([] = compila).
func save_shader(name: String, code: String) -> Array:
	var errs := ShaderLib.validate(code)
	if errs.is_empty():
		ShaderLib.save(name, code)
	else:
		error("save_shader: «%s» no compila (línea %d: %s)" % [name, int(errs[0]["line"]), errs[0]["msg"]])
	return errs

## Aplica un shader a uno o varios objetos: nombre de la biblioteca, nombre
## de plantilla o código directamente. Devuelve false si no compila.
func apply_shader(nodes: Variant, shader: String) -> bool:
	var nm := shader
	var code := shader_code(shader)
	if code == "":
		if "shader_type" in shader:
			code = shader
			nm = "Shader"
		else:
			error("apply_shader: no hay ningún shader llamado «%s»" % shader)
			return false
	var errs := ShaderLib.validate(code)
	if not errs.is_empty():
		error("apply_shader: «%s» no compila (línea %d: %s)" % [nm, int(errs[0]["line"]), errs[0]["msg"]])
		return false
	var value := {"name": nm, "code": code, "margin": ShaderLib.margin_of(code), "params": {}, "enabled": true}
	begin("Shader · " + nm)
	for n in (nodes if nodes is Array else [nodes]):
		set_prop(n, "custom_shader", value.duplicate(true))
	end()
	return true

func remove_shader(nodes: Variant) -> void:
	begin("Quitar shader")
	for n in (nodes if nodes is Array else [nodes]):
		set_prop(n, "custom_shader", {})
	end()

## Shader aplicado a un objeto ({} si no tiene).
func get_shader(node: Node) -> Dictionary:
	var v = get_prop(node, "custom_shader")
	return v if v is Dictionary else {}

# ── artboards, imágenes, exportar, vectorizar ────────────────────────────────
## Crea un artboard nuevo (a la derecha del último) y lo activa.
func add_artboard(size: Vector2 = Vector2(794, 1123), name: String = "Artboard") -> Node2D:
	var first := artboard()
	var cont := first.get_parent() if first else null
	if cont == null:
		error("add_artboard: no hay contenedor de artboards")
		return null
	var pos := Vector2.ZERO
	for a in artboards():
		pos.x = maxf(pos.x, a.global_position.x + a.artboard_size.x + 80.0)
		pos.y = a.global_position.y if pos.y == 0.0 else pos.y
	var ab := Node2D.new()
	ab.set_script(load("res://scripts/canvas/artboard.gd"))
	ab.name = NameUtils.unique_child_name(cont, name)
	ab.artboard_size = size
	cont.add_child(ab)
	ab.global_position = pos
	set_active_artboard(ab)
	_record("Nuevo artboard",
		func() -> void:
			if is_instance_valid(ab) and ab.get_parent() == null:
				cont.add_child(ab)
				ab.global_position = pos,
		func() -> void:
			if is_instance_valid(ab) and ab.get_parent() == cont:
				cont.remove_child(ab)
				if is_instance_valid(first): set_active_artboard(first),
		false)
	return ab

## Imagen (ruta de archivo o Image) centrada en `center`.
func add_image(source: Variant, center: Vector2, name: String = "Imagen") -> Node2D:
	var img: Image = source if source is Image else null
	if img == null:
		img = Image.new()
		if img.load(String(source)) != OK:
			error("add_image: no se pudo cargar «%s»" % source)
			return null
		if name == "Imagen":
			name = "Foto_" + String(source).get_file().get_basename()
	var sp := Sprite2D.new()
	sp.name = name
	sp.texture = ImageTexture.create_from_image(img)
	sp.centered = false
	sp.position = center - Vector2(img.get_size()) / 2.0
	return add(sp)

## Exporta un artboard según la extensión: .svg .pdf .eps .png .jpg .webp
## .vop .tscn .scn. `options`: scale (imagen), quality 1-100, transparent.
## Usar con await. Devuelve true si se escribió.
func export(path: String, ab: Node2D = null, options: Dictionary = {}) -> bool:
	var a := ab if ab else artboard()
	var iem := _n("ImportExportManager")
	if a == null or iem == null:
		error("export: no hay artboard o exportador")
		return false
	var fmt := {"svg": "SVG", "pdf": "PDF", "eps": "EPS", "png": "PNG", "jpg": "JPEG", "jpeg": "JPEG",
		"webp": "WEBP", "vop": "VOP", "tscn": "TSCN", "scn": "SCN"}
	var ext := path.get_extension().to_lower()
	if not fmt.has(ext):
		error("export: formato no soportado «.%s»" % ext)
		return false
	var err: Error = await iem.export_artboard(a, iem.ExportFormat[fmt[ext]], path, options)
	if err != OK:
		error("export: no se pudo escribir «%s» (%s)" % [path, error_string(err)])
	return err == OK

## SVG del artboard como texto.
func svg(ab: Node2D = null) -> String:
	var iem := _n("ImportExportManager")
	var a := ab if ab else artboard()
	return iem.export_to_svg_string(a) if iem and a else ""

## Presets de vectorización: Logo / icono, Ilustración, Foto (más detalle),
## Blanco y negro, Pixel art.
func vectorize_presets() -> Array:
	return VecPanel.PRESETS.keys()

## Vectoriza una imagen (Sprite2D) en trazados Bézier. Usar con await.
## Devuelve el grupo creado (o null).
func vectorize(sprite: Sprite2D, preset: String = "Ilustración", hide_original: bool = true) -> Node2D:
	if not ClassDB.class_exists("VectorizerJob"):
		error("vectorize: el vectorizador nativo no está cargado")
		return null
	if not is_instance_valid(sprite) or sprite.texture == null:
		error("vectorize: hace falta una imagen")
		return null
	var opts: Dictionary = (VecPanel.PRESETS.get(preset, VecPanel.PRESETS["Ilustración"]) as Dictionary).duplicate()
	opts["hierarchical"] = "stacked"
	opts["path_precision"] = 3
	var src := VecPanel._tmp_path("api_in.png")
	var out := VecPanel._tmp_path("api_out.svg")
	var img := sprite.texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.save_png(src)
	var j = ClassDB.instantiate("VectorizerJob")
	j.start_vectorize(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(out), opts,
		false, false, ProjectSettings.globalize_path("user://"))
	while not j.is_done():
		await _host.get_tree().process_frame
	var err: String = j.get_error()
	var text := FileAccess.get_file_as_string(out)
	VecPanel._cleanup([src, out])
	if err != "" or text == "":
		error("vectorize: " + (err if err != "" else "sin resultado"))
		return null
	var g := VecPanel.build_group(sprite, text)
	if g == null:
		error("vectorize: la imagen no produjo trazados")
		return null
	begin("Vectorizar")
	add(g, sprite.get_parent())
	if hide_original:
		set_prop(sprite, "visible", false)
	end()
	return g

# ── deshacer / transacciones ─────────────────────────────────────────────────
## Abre una transacción: todo hasta end() es UN paso de deshacer.
func begin(action_name: String = "Script") -> void:
	if _tx_depth == 0:
		_tx = []
		_tx_name = action_name
	_tx_depth += 1

## Cierra la transacción abierta con begin().
func end() -> void:
	if _tx_depth == 0:
		return
	_tx_depth -= 1
	if _tx_depth > 0:
		return
	var steps := _tx
	_tx = []
	_flush()
	if steps.is_empty():
		return
	var notify := func() -> void: _notify_changed()
	var hm := _n("HistoryManager")
	if hm:
		hm.register_action(_tx_name)
		hm.add_do(func() -> void:
			for s in steps:
				s["do"].call()
			notify.call())
		hm.add_undo(func() -> void:
			for i in range(steps.size() - 1, -1, -1):
				steps[i]["undo"].call()
			notify.call())
		hm.commit()

## Ejecuta `fn` como UN paso de deshacer llamado `action_name`.
func transaction(action_name: String, fn: Callable) -> void:
	begin(action_name)
	fn.call()
	end()

## Descarta una transacción abierta (p.ej. tras un error) DESHACIENDO lo hecho.
func rollback() -> void:
	var steps := _tx
	_tx = []
	_tx_depth = 0
	for i in range(steps.size() - 1, -1, -1):
		steps[i]["undo"].call()
	_flush()

func in_transaction() -> bool:
	return _tx_depth > 0

func undo() -> void:
	var hm := _n("HistoryManager")
	if hm:
		hm.undo()

func redo() -> void:
	var hm := _n("HistoryManager")
	if hm:
		hm.redo()

func _record(action_name: String, do_fn: Callable, undo_fn: Callable, is_prop: bool) -> void:
	if _tx_depth > 0:
		_tx.append({"do": do_fn, "undo": undo_fn})
		return
	var hm := _n("HistoryManager")
	if hm:
		hm.register_action(action_name)
		hm.add_do(func() -> void:
			do_fn.call()
			_notify_changed())
		hm.add_undo(func() -> void:
			undo_fn.call()
			_notify_changed())
		hm.commit()
	if is_prop:
		_flush()

## Un solo aviso a la UI (Inspector, capas, caja de selección) por lote.
func _flush() -> void:
	if not _tx_dirty:
		return
	_tx_dirty = false
	_notify_changed()

func _notify_changed() -> void:
	var ic := _n("InspectorCore")
	if ic and ic.has_method("_post_write"):
		ic._sync_selection()
		ic._post_write()

# ── complementos: operadores ─────────────────────────────────────────────────
## Registra una acción con nombre que el usuario puede ejecutar desde la
## pestaña Complementos (y otros scripts con run_operator). `fn` no recibe
## argumentos; corre como UN paso de deshacer.
func register_operator(id: String, label: String, fn: Callable, tooltip: String = "", owner: String = "") -> void:
	_ops[id] = {"id": id, "label": label, "callable": fn, "tooltip": tooltip, "owner": owner}

func unregister_operator(id: String) -> void:
	_ops.erase(id)

func operators(owner: String = "") -> Array:
	var out: Array = []
	for id in _ops:
		if owner == "" or _ops[id]["owner"] == owner:
			out.append(_ops[id])
	return out

## Ejecuta un operador registrado. Devuelve false si no existe o falló.
func run_operator(id: String) -> bool:
	if not _ops.has(id):
		error("Operador desconocido: %s" % id)
		return false
	var fn: Callable = _ops[id]["callable"]
	if not fn.is_valid():
		error("El operador «%s» ya no es válido" % id)
		return false
	begin(String(_ops[id]["label"]))
	fn.call()
	end()
	return true

const TextCore = preload("res://script_gdscript/text/text_core.gd")
const ShaderLib = preload("res://script_gdscript/shapes/shader_library.gd")
const FilterFx = preload("res://script_gdscript/shapes/filter_fx.gd")
const EffectsPanel = preload("res://script_gdscript/ui/panels/effects/effects.gd")
const VecPanel = preload("res://script_gdscript/ui/panels/effects/vectorize_panel.gd")
