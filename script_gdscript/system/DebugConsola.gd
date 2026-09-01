# =============================================================================
# VECTOPEN — CONSOLA DE DIAGNÓSTICO (autoload "DebugConsola")
# =============================================================================
# Vigila en TIEMPO REAL los tres subsistemas más frágiles del editor y saca por
# consola SOLO las anomalías (invariantes rotas) + los eventos clave, con
# prefijos grepables para leerlos por MCP:
#
#   [DBG:BBOX]        bounding box  (gizmo de selección / handles)
#   [DBG:CAPAS]       panel de capas (LayerSystem ↔ árbol)
#   [DBG:JERARQUIA]   relación padre↔hijo (escena ↔ TreeItem)
#   [DBG:EVENTO]      mutación estructural (reparent / drop / agrupar…)
#   [DBG:SYS]         estado de la propia consola
#
# Salida DOBLE: `print()` (lo ve get_console_log) y MCPRuntime.push_runtime_log
# (lo ve get_runtime_log, filtrable por `since_ms`). Cada anomalía se registra
# una vez y luego se agrupa (contador) para no inundar.
#
# Teclas:  F10 = alterna modo verboso + vuelca un informe completo AHORA.
# =============================================================================
extends Node

var verbose: bool = false

# Referencias vivas (las registran los propios subsistemas en su _ready/activate).
var _bbox: Node = null
var _layersys: Node = null
var _movetool: Node = null

var _t_acc: float = 0.0
const _INTERVALO: float = 0.3          # s entre barridos de invariantes

## PUERTA TRASERA DE DEPURACIÓN. Se puede escribir por MCP
## (`modify_node_property /root/DebugConsola.cmd = "..."`) y se ejecuta en el
## siguiente `_process`. Comandos:
##   informe                     → informe_completo()
##   estado                      → vuelca gui_is_dragging + todos los flags
##   anidar <hijo> <padre>       → layer_tree.mover_capas([hijo], padre, fin)
##   sacar <nodo>                → mueve <nodo> al artboard raíz que lo contiene
##   crear_rect [n]              → n rectángulos en el artboard activo (por defecto 1)
var cmd: String = ""

## Dedupe de anomalías: clave estable → { n:int, primera_ms:int, ultima_ms:int }
var _anomalias: Dictionary = {}
## Contadores de persistencia (nº de barridos consecutivos con la condición viva).
var _persist: Dictionary = {}

# ── Registro ────────────────────────────────────────────────────────────────
func registrar_bbox(n: Node) -> void:
	_bbox = n
	_log("SYS", "BoundingBox registrado (%s)" % n)

func registrar_layersystem(n: Node) -> void:
	_layersys = n
	_log("SYS", "LayerSystem registrado")

func registrar_movetool(n: Node) -> void:
	_movetool = n
	if verbose:
		_log("SYS", "MoveTool registrado")

# ── Ciclo de vida ───────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log("SYS", "Consola de diagnóstico activa. F10 = informe completo / verboso.")
	# Eventos estructurales globales.
	if _has(GlobalEvents, "selection_changed") and not GlobalEvents.selection_changed.is_connected(_on_seleccion):
		GlobalEvents.selection_changed.connect(_on_seleccion)
	if _has(GlobalEvents, "object_transformed") and not GlobalEvents.object_transformed.is_connected(_on_transformado):
		GlobalEvents.object_transformed.connect(_on_transformado)

func _process(delta: float) -> void:
	if cmd != "":
		var c := cmd
		cmd = ""
		_ejecutar_cmd(c)
	_t_acc += delta
	if _t_acc < _INTERVALO:
		return
	_t_acc = 0.0
	_barrer_bbox()
	_barrer_capas()
	_barrer_jerarquia()

# ── Puerta trasera de depuración ────────────────────────────────────────────
func _ejecutar_cmd(c: String) -> void:
	var partes := c.strip_edges().split(" ", false)
	if partes.is_empty():
		return
	_log("SYS", "cmd → %s" % c)
	match partes[0]:
		"informe":
			informe_completo()
		"estado":
			_estado_drag()
		"anidar":
			if partes.size() >= 3:
				_cmd_anidar(partes[1], partes[2])
			else:
				_log("SYS", "uso: anidar <hijo> <padre>")
		"sacar":
			if partes.size() >= 2:
				_cmd_sacar(partes[1])
		"crear_rect":
			_cmd_crear_rect(int(partes[1]) if partes.size() >= 2 else 1)
		_:
			_log("SYS", "comando desconocido: %s" % partes[0])

func _estado_drag() -> void:
	var vp := get_viewport()
	var arrastrando := "?"
	if vp:
		arrastrando = str(vp.gui_is_dragging())
	_log("SYS", "gui_is_dragging=%s   LMB=%s   mouse_mask=%d" % [
		arrastrando, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), Input.get_mouse_button_mask()])
	var mt := _movetool_vivo()
	if is_instance_valid(mt):
		var flags := {}
		for f in ["is_dragging_shape", "is_marquee", "is_resizing", "is_rotating",
				"is_dragging_artboard", "is_resizing_artboard"]:
			if f in mt:
				flags[f] = bool(mt.get(f))
		_log("SYS", "MoveTool flags = %s" % str(flags))
	if is_instance_valid(_bbox) and "_is_dragging_canvas_area" in _bbox:
		_log("SYS", "bbox._is_dragging_canvas_area = %s" % str(_bbox._is_dragging_canvas_area))
	if is_instance_valid(_layersys):
		var b := "?"
		if "_bloquear_sincronizacion" in _layersys:
			b = str(bool(_layersys._bloquear_sincronizacion))
		var r := "?"
		if "_reflejando_seleccion" in _layersys:
			r = str(bool(_layersys._reflejando_seleccion))
		var p := -1
		if "_pending_changes" in _layersys:
			p = (_layersys._pending_changes as Array).size()
		_log("SYS", "LayerSystem  bloqueado=%s  reflejando=%s  pending=%d" % [b, r, p])

func _cmd_anidar(hijo_nom: String, padre_nom: String) -> void:
	var lt := _layer_tree()
	if lt == null or not lt.has_method("mover_capas"):
		_log("SYS", "sin LayerTree con mover_capas"); return
	var hijo := _buscar_nodo(hijo_nom)
	var padre := _buscar_nodo(padre_nom)
	if not is_instance_valid(hijo) or not is_instance_valid(padre):
		_log("SYS", "no encontrado: hijo=%s padre=%s" % [hijo, padre]); return
	_log("EVENTO", "cmd anidar: %s dentro de %s  (padre actual de %s = %s)" % [
		hijo_nom, padre_nom, hijo_nom, str(hijo.get_parent().name)])
	lt.mover_capas([hijo], padre, padre.get_child_count())
	await get_tree().process_frame
	await get_tree().process_frame
	_log("EVENTO", "resultado: %s.get_parent() = %s" % [hijo_nom, str(hijo.get_parent().name)])
	_estado_drag()

func _cmd_sacar(nom: String) -> void:
	var lt := _layer_tree()
	var n := _buscar_nodo(nom)
	if lt == null or not is_instance_valid(n):
		return
	var ab := n
	while is_instance_valid(ab) and not ("artboard_size" in ab):
		ab = ab.get_parent()
	if is_instance_valid(ab):
		lt.mover_capas([n], ab, ab.get_child_count())
		_log("EVENTO", "cmd sacar: %s → %s" % [nom, str(ab.name)])

func _cmd_crear_rect(n: int) -> void:
	var cont := _cont_artboards()
	if not is_instance_valid(cont):
		return
	var ab: Node = null
	for c in cont.get_children():
		if "artboard_size" in c:
			ab = c; break
	if not is_instance_valid(ab):
		return
	for i in maxi(n, 1):
		var r = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
		r.name = "DbgRect"
		ab.add_child(r)
		r.size = Vector2(120, 90)
		r.global_position = ab.global_position + Vector2(200 + i * 40, 200 + i * 40)
	_log("EVENTO", "cmd crear_rect: %d creados" % maxi(n, 1))

func _buscar_nodo(nombre: String) -> Node:
	var cont := _cont_artboards()
	if not is_instance_valid(cont):
		return null
	return _buscar_rec(cont, nombre)

func _buscar_rec(raiz: Node, nombre: String) -> Node:
	for c in raiz.get_children():
		if String(c.name) == nombre:
			return c
		var r := _buscar_rec(c, nombre)
		if r != null:
			return r
	return null

func _cont_artboards() -> Node:
	if is_instance_valid(_layersys) and "artboard_container" in _layersys \
			and is_instance_valid(_layersys.artboard_container):
		return _layersys.artboard_container
	var esc := get_tree().current_scene if get_tree() else null
	return esc.find_child("ArtboardsContainer", true, false) if esc else null

func _layer_tree() -> Node:
	if is_instance_valid(_layersys) and "layer_tree" in _layersys:
		return _layersys.layer_tree
	return null

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kc: int = event.keycode if event.keycode != 0 else event.physical_keycode
	match kc:
		KEY_F10:
			verbose = not verbose
			_log("SYS", "verbose = %s" % verbose)
			informe_completo()
			get_viewport().set_input_as_handled()
		KEY_F7:
			_estado_drag()
			get_viewport().set_input_as_handled()
		KEY_F8:
			_paso_crear.call_deferred()
			get_viewport().set_input_as_handled()
		KEY_F6:
			_paso_nest.call_deferred(1)   # EXP2 → EXP1
			get_viewport().set_input_as_handled()
		KEY_F5:
			_paso_nest.call_deferred(2)   # EXP3 → EXP1
			get_viewport().set_input_as_handled()
		KEY_F4:
			_paso_sacar.call_deferred(2)  # EXP3 → artboard
			get_viewport().set_input_as_handled()
		KEY_F3:
			_paso_gesto_dnd.call_deferred()   # simula _get_drag_data → _drop_data REAL
			get_viewport().set_input_as_handled()
		KEY_F2:
			_paso_drag_hijo.call_deferred()   # arrastrar en el LIENZO una figura ANIDADA
			get_viewport().set_input_as_handled()
		KEY_F1:
			_paso_doble_click.call_deferred()   # doble clic estilo Affinity: baja al hijo
			get_viewport().set_input_as_handled()

## Reproduce EXACTAMENTE lo que reporta el usuario: 1er anidado OK, 2º bloquea.
## Ctrl+F10.  Crea 3 rects, anida el 2º en el 1º, luego el 3º en el 1º, y vuelca
## el estado tras cada paso para ver DÓNDE se traba.
## Experimento por PASOS (una tecla cada uno) para aislar en cuál se cae la app.
##   F8 crear · F6 nest EXP2→EXP1 · F5 nest EXP3→EXP1 · F4 sacar EXP3
var _exp_rects: Array = []

func _exp_ab() -> Node:
	var cont := _cont_artboards()
	if not is_instance_valid(cont):
		return null
	for c in cont.get_children():
		if "artboard_size" in c:
			return c
	return null

func _paso_crear() -> void:
	_log("SYS", ">>> F8 crear 3 rects")
	var ab := _exp_ab()
	if not is_instance_valid(ab):
		_log("SYS", "sin artboard"); return
	for c in ab.get_children():
		if String(c.name).begins_with("EXP"):
			c.free()
	_exp_rects.clear()
	await get_tree().process_frame
	for i in 3:
		var r = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
		r.name = "EXP%d" % (i + 1)
		ab.add_child(r)
		r.size = Vector2(120, 90)
		r.global_position = ab.global_position + Vector2(150 + i * 70, 150 + i * 70)
		_exp_rects.append(r)
	_log("SYS", "<<< F8 hecho: 3 rects. (esperar sync…)")

## Figuras hijas DIRECTAS del artboard (por orden), sin el título ni auxiliares.
func _figuras_artboard() -> Array:
	var ab := _exp_ab()
	if not is_instance_valid(ab):
		return []
	var out: Array = []
	for c in ab.get_children():
		if c is Node2D and String(c.name) not in ["ArtboardTitle", "Contorno_Stroke", "VectorDrawingLayer"]:
			out.append(c)
	return out

func _paso_nest(cual: int) -> void:
	_log("SYS", ">>> nest figura[%d] dentro de figura[0]" % cual)
	var figs := _figuras_artboard()
	_log("SYS", "  figuras nivel-1 del artboard: %s" % str(figs.map(func(n): return n.name)))
	if figs.size() < 2 or cual >= figs.size():
		_log("SYS", "no hay suficientes figuras (pulsa el botón cuadrado varias veces)"); return
	var hijo: Node = figs[cual]
	var padre: Node = figs[0]
	if not is_instance_valid(hijo) or not is_instance_valid(padre):
		_log("SYS", "figuras liberadas"); return
	var lt := _layer_tree()
	_log("SYS", "  antes: %s.parent=%s" % [hijo.name, str(hijo.get_parent().name)])
	_estado_drag()
	lt.mover_capas([hijo], padre, padre.get_child_count())
	_log("SYS", "  mover_capas devolvió")
	await get_tree().process_frame
	_log("SYS", "  +1 frame: %s.parent=%s" % [hijo.name, str(hijo.get_parent().name)])
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	_log("SYS", "  +batch: %s.parent=%s" % [hijo.name, str(hijo.get_parent().name)])
	_estado_drag()
	_verificar_arbol(hijo, padre)
	_log("SYS", "<<< nest hecho")

func _paso_sacar(_cual: int) -> void:
	_log("SYS", ">>> sacar la última figura ANIDADA que encuentre")
	var ab := _exp_ab()
	if not is_instance_valid(ab):
		return
	# busca la primera figura nivel-1 que tenga hijos, y saca su primer hijo
	var n: Node = null
	for f in _figuras_artboard():
		for h in f.get_children():
			if h is Node2D:
				n = h
				break
		if n != null:
			break
	if not is_instance_valid(n):
		_log("SYS", "no hay ninguna figura anidada"); return
	var lt := _layer_tree()
	lt.mover_capas([n], ab, ab.get_child_count())
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	_log("SYS", "<<< sacar: %s.parent=%s" % [n.name, str(n.get_parent().name)])
	_estado_drag()

## Ejercita la RUTA REAL del drag&drop del Tree (`_get_drag_data` → `_can_drop_data`
## → `_drop_data`), que es lo único que el `mover_capas` directo NO prueba y
## donde vive el bloqueo. Anida figura[1] en figura[0]. Púlsalo DOS veces:
## la 2ª es la que el usuario ve trabada.
var _gesto_n := 0
func _paso_gesto_dnd() -> void:
	_gesto_n += 1
	_log("SYS", "════ GESTO DnD #%d ════" % _gesto_n)
	var lt := _layer_tree()
	if lt == null:
		_log("SYS", "sin LayerTree"); return
	var vp := get_viewport()
	_log("SYS", "  gui_is_dragging ANTES = %s" % str(vp.gui_is_dragging()))

	var figs := _figuras_artboard()
	_log("SYS", "  figuras: %s" % str(figs.map(func(n): return n.name)))
	if figs.size() < 2:
		_log("SYS", "  necesito ≥2 figuras nivel-1"); return
	var hijo: Node = figs[1]
	var padre: Node = figs[0]

	var mapa: Dictionary = _layersys._node_to_item_map
	var it_src = mapa.get(hijo)
	var it_dst = mapa.get(padre)
	if not is_instance_valid(it_src) or not is_instance_valid(it_dst):
		_log("SYS", "  sin TreeItem para src/dst (src=%s dst=%s)" % [it_src, it_dst]); return

	var r_src: Rect2 = lt.get_item_area_rect(it_src, 0)
	var r_dst: Rect2 = lt.get_item_area_rect(it_dst, 0)
	var p_src := r_src.position + Vector2(8, r_src.size.y * 0.5)
	# probamos varias alturas dentro de la fila destino
	for frac in [0.15, 0.5, 0.85]:
		var pp := r_dst.position + Vector2(8, r_dst.size.y * frac)
		var s_motor: int = lt.get_drop_section_at_position(pp)
		var s_robusto: int = 999
		if lt.has_method("_seccion_drop"):
			s_robusto = lt._seccion_drop(pp, it_dst)
		_log("SYS", "  y-frac %.2f: get_drop_section=%d  _seccion_drop=%d  (0 = anida)" % [frac, s_motor, s_robusto])
	var p_dst := r_dst.position + Vector2(8, r_dst.size.y * 0.5)

	var data = lt._get_drag_data(p_src)
	_log("SYS", "  _get_drag_data → %s" % ("null" if data == null else "dict con %d nodos" % (data.get("nodes", []) as Array).size()))
	if data == null:
		return
	var puede = lt._can_drop_data(p_dst, data)
	_log("SYS", "  _can_drop_data → %s" % str(puede))
	# forzamos anidado (sección 0) llamando mover_capas como haría _drop_data con sección 0
	_log("SYS", "  → forzando anidado directo (mover_capas)")
	lt.mover_capas(data["nodes"], padre, padre.get_child_count())
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	_log("SYS", "  gui_is_dragging DESPUÉS = %s" % str(vp.gui_is_dragging()))
	_log("SYS", "  %s.parent = %s (esperado %s)" % [hijo.name, str(hijo.get_parent().name), padre.name])
	_estado_drag()
	_log("SYS", "════ FIN GESTO #%d ════" % _gesto_n)

## F2 — ¿se puede arrastrar en el LIENZO una figura que está ANIDADA dentro de
## otra? Selecciona el hijo, cambia a la herramienta mover, y conduce
## `_on_press`/`_on_motion`/`_on_release` de MoveTool con la posición mundo del
## hijo. Comprueba que (a) el hit-test NO deselecciona, (b) el hijo se mueve.
func _paso_drag_hijo() -> void:
	_log("SYS", "════ F2: arrastrar figura anidada en el lienzo ════")
	# 1) localizar un hijo anidado
	var hijo: Node2D = null
	var padre: Node2D = null
	for f in _figuras_artboard():
		for c in f.get_children():
			if c is Node2D and String(c.name) != "Contorno_Stroke":
				hijo = c
				padre = f
				break
		if hijo != null:
			break
	if not is_instance_valid(hijo):
		_log("SYS", "  no hay ninguna figura anidada (anida algo primero con drag en el panel)")
		return
	_log("SYS", "  hijo = %s  (dentro de %s)" % [hijo.name, padre.name])

	# 2) cambiar a la herramienta mover
	var st := get_tree()
	var canvas := st.get_first_node_in_group("_vectopen_canvas") if st else null
	if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
		canvas.switch_tool("move")
	await get_tree().process_frame
	await get_tree().process_frame

	# 3) seleccionar el hijo por SelectionManager
	var sm := get_node_or_null("/root/SelectionManager")
	if sm and sm.has_method("select"):
		sm.select(hijo)
	await get_tree().process_frame

	var mt := _movetool_vivo()
	if not is_instance_valid(mt) or not ("selected_shapes" in mt):
		_log("SYS", "  MoveTool no activo (tool = %s)" % str(mt)); return
	_log("SYS", "  MoveTool.selected_shapes = %s" % str((mt.selected_shapes as Array).map(func(n): return n.name if is_instance_valid(n) else "?")))

	var p0: Vector2 = hijo.global_position
	var centro := p0   # global_position de VectorShape ES el centro
	_log("SYS", "  hijo.global_position ANTES = %s" % p0)

	# 4) hit-test en la posición del hijo
	if mt.has_method("_shape_at"):
		var h = mt._shape_at(centro)
		_log("SYS", "  _shape_at(centro) = %s   (_es_grupo=%s)" % [
			h.name if is_instance_valid(h) else "null",
			str(mt._es_grupo_movetool(h)) if is_instance_valid(h) and mt.has_method("_es_grupo_movetool") else "?"])

	# 5) simular el arrastre
	mt._on_press(centro)
	_log("SYS", "  tras _on_press: selected=%s  is_dragging_shape=%s" % [
		str((mt.selected_shapes as Array).map(func(n): return n.name if is_instance_valid(n) else "?")),
		str(mt.is_dragging_shape)])
	mt._on_motion(centro + Vector2(60, 40))
	mt._on_release(centro + Vector2(60, 40))
	await get_tree().process_frame

	var p1: Vector2 = hijo.global_position
	var delta := p1 - p0
	_log("SYS", "  hijo.global_position DESPUÉS = %s   (Δ = %s, esperado ≈ (60,40))" % [p1, delta])
	if delta.is_equal_approx(Vector2(60, 40)):
		_log("SYS", "  ✓ el hijo anidado SE MUEVE con el arrastre")
	else:
		_log("SYS", "  ✗ el hijo anidado NO se movió correctamente")
	_log("SYS", "════ FIN F2 ════")

## F1 — doble clic estilo Affinity: cada uno baja un nivel hacia la hoja bajo el
## cursor. Requiere una figura con al menos un hijo anidado.
func _paso_doble_click() -> void:
	_log("SYS", "════ F1: doble clic → entrar al hijo ════")
	var hijo: Node2D = null
	for f in _figuras_artboard():
		for c in f.get_children():
			if c is Node2D and String(c.name) != "Contorno_Stroke":
				hijo = c; break
		if hijo != null:
			break
	if not is_instance_valid(hijo):
		_log("SYS", "  anida algo primero (drag en el panel)"); return

	var st := get_tree()
	var canvas := st.get_first_node_in_group("_vectopen_canvas") if st else null
	if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
		canvas.switch_tool("move")
	await get_tree().process_frame
	await get_tree().process_frame
	var mt := _movetool_vivo()
	if not is_instance_valid(mt) or not mt.has_method("_entrar_en_hijo"):
		_log("SYS", "  MoveTool no activo/sin _entrar_en_hijo"); return

	var centro: Vector2 = hijo.global_position
	var sm := get_node_or_null("/root/SelectionManager")
	if sm:
		sm.clear()
	await get_tree().process_frame

	mt._on_press(centro)   # clic sencillo → contenedor de primer nivel
	_log("SYS", "  clic sencillo → selected = %s" % str((mt.selected_shapes as Array).map(func(n): return n.name if is_instance_valid(n) else "?")))
	var d1: bool = mt._entrar_en_hijo(centro)   # 1er doble clic
	_log("SYS", "  doble clic #1 (bajó=%s) → selected = %s" % [str(d1), str((mt.selected_shapes as Array).map(func(n): return n.name if is_instance_valid(n) else "?"))])
	var d2: bool = mt._entrar_en_hijo(centro)   # 2º doble clic
	_log("SYS", "  doble clic #2 (bajó=%s) → selected = %s" % [str(d2), str((mt.selected_shapes as Array).map(func(n): return n.name if is_instance_valid(n) else "?"))])
	# ¿el bounding box del hijo está visible?
	if is_instance_valid(_bbox):
		_log("SYS", "  bounding box: visible=%s" % str(_bbox.get("visible")))
	_log("SYS", "════ FIN F1 ════")

var _exp_corriendo := false
func _experimento_doble_anidado() -> void:
	if _exp_corriendo:
		_log("SYS", "experimento ya en curso, ignorado")
		return
	_exp_corriendo = true
	_log("SYS", "════════ EXPERIMENTO: doble anidado ════════")
	var lt := _layer_tree()
	if lt == null or not lt.has_method("mover_capas"):
		_log("SYS", "abortado: sin LayerTree"); return
	# limpia rects de experimentos previos
	var cont := _cont_artboards()
	var ab: Node = null
	for c in cont.get_children():
		if "artboard_size" in c:
			ab = c
			break
	if not is_instance_valid(ab):
		_log("SYS", "abortado: sin artboard"); return
	for c in ab.get_children():
		if String(c.name).begins_with("EXP"):
			c.free()
	await get_tree().process_frame
	# crea 3
	var rects: Array = []
	for i in 3:
		var r = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
		r.name = "EXP%d" % (i + 1)
		ab.add_child(r)
		r.size = Vector2(120, 90)
		r.global_position = ab.global_position + Vector2(150 + i * 70, 150 + i * 70)
		rects.append(r)
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame
	_log("SYS", "── 3 rects creados ──")
	_estado_drag()

	# PASO 1: anidar EXP2 dentro de EXP1
	_log("SYS", "── PASO 1: mover_capas([EXP2], EXP1) ──")
	lt.mover_capas([rects[1]], rects[0], rects[0].get_child_count())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	_log("SYS", "  EXP2.parent = %s  (esperado EXP1)" % str(rects[1].get_parent().name))
	_estado_drag()
	_verificar_arbol(rects[1], rects[0])

	# PASO 2: anidar EXP3 dentro de EXP1  ← aquí es donde el usuario ve el bloqueo
	_log("SYS", "── PASO 2: mover_capas([EXP3], EXP1) ──")
	lt.mover_capas([rects[2]], rects[0], rects[0].get_child_count())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	_log("SYS", "  EXP3.parent = %s  (esperado EXP1)" % str(rects[2].get_parent().name))
	_estado_drag()
	_verificar_arbol(rects[2], rects[0])

	# PASO 3: sacar EXP3 de nuevo
	_log("SYS", "── PASO 3: sacar EXP3 al artboard ──")
	lt.mover_capas([rects[2]], ab, ab.get_child_count())
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	_log("SYS", "  EXP3.parent = %s  (esperado %s)" % [str(rects[2].get_parent().name), str(ab.name)])
	_estado_drag()
	_log("SYS", "════════ FIN EXPERIMENTO ════════")
	_exp_corriendo = false

func _verificar_arbol(hijo: Node, padre: Node) -> void:
	if not is_instance_valid(_layersys) or not ("_node_to_item_map" in _layersys):
		return
	var mapa: Dictionary = _layersys._node_to_item_map
	var it_h = mapa.get(hijo)
	var it_p = mapa.get(padre)
	if it_h == null:
		_log("JERARQUIA", "  ✗ %s NO tiene fila en el panel" % hijo.name)
	elif it_p == null:
		_log("JERARQUIA", "  ✗ %s NO tiene fila en el panel" % padre.name)
	elif not is_instance_valid(it_h) or not is_instance_valid(it_p):
		_log("JERARQUIA", "  ✗ fila liberada (it_h válido=%s, it_p válido=%s)" % [
			is_instance_valid(it_h), is_instance_valid(it_p)])
	elif it_h.get_parent() != it_p:
		_log("JERARQUIA", "  ✗ la fila de %s NO cuelga de la fila de %s" % [hijo.name, padre.name])
	else:
		_log("JERARQUIA", "  ✓ panel OK: %s bajo %s" % [hijo.name, padre.name])

# ── API pública para puntos de mutación (llamable desde cualquier script) ────
## Registra un EVENTO estructural con contexto. Ej.:
##   DebugConsola.evento("reparent", "%s: %s → %s (idx %d)" % [n.name, p0, p1, i])
func evento(tipo: String, detalle: String) -> void:
	_log("EVENTO", "%s · %s" % [tipo, detalle])

## Vuelca a la consola una foto completa del estado de los tres subsistemas.
func informe_completo() -> void:
	_log("SYS", "──────── INFORME COMPLETO ────────")
	_informe_bbox()
	_informe_capas()
	_informe_jerarquia()
	_log("SYS", "─────────────────────────────────")

# ── Barridos de invariantes ─────────────────────────────────────────────────
func _barrer_bbox() -> void:
	var mt: Node = _movetool_vivo()
	if is_instance_valid(mt):
		var sin_boton := not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		for flag in ["is_dragging_shape", "is_marquee", "is_resizing", "is_rotating",
				"is_dragging_artboard", "is_resizing_artboard"]:
			var activo: bool = (flag in mt) and bool(mt.get(flag))
			_persistencia("mt_%s_sin_boton" % flag, activo and sin_boton, 3,
				"[DBG:BBOX] %s lleva activo SIN botón izquierdo pulsado (gesto zombi)" % flag)

	if is_instance_valid(_bbox):
		var padre := _bbox.get_parent()
		if is_instance_valid(padre) and not (padre is CanvasItem):
			_anom("bbox_padre_no_canvasitem",
				"[DBG:BBOX] BoundingBox colgado de un nodo que NO es CanvasItem (%s) → to_local/global_rotation revientan" % padre.get_class())
		if _bbox.get("visible"):
			var sz: Vector2 = _bbox.get("size")
			if is_nan(sz.x) or is_nan(sz.y) or absf(sz.x) > 50000.0 or absf(sz.y) > 50000.0:
				_anom("bbox_tam_absurdo", "[DBG:BBOX] tamaño del gizmo fuera de rango: %s" % sz)
			var mt2: Node = _movetool_vivo()
			var sel_vacia: bool = is_instance_valid(mt2) and ("selected_shapes" in mt2) \
				and (mt2.selected_shapes as Array).is_empty()
			var sin_target: bool = not ("target_node" in _bbox) or not is_instance_valid(_bbox.get("target_node"))
			_persistencia("bbox_visible_sin_seleccion", sel_vacia and sin_target, 3,
				"[DBG:BBOX] gizmo VISIBLE sin ninguna figura seleccionada")

func _barrer_capas() -> void:
	if not is_instance_valid(_layersys):
		return
	var bloqueado: bool = ("_bloquear_sincronizacion" in _layersys) and bool(_layersys._bloquear_sincronizacion)
	_persistencia("capas_sync_bloqueada", bloqueado, 3,
		"[DBG:CAPAS] _bloquear_sincronizacion lleva bloqueado varios barridos (sync abortada a mitad?)")

	if "_pending_changes" in _layersys:
		var pend: int = (_layersys._pending_changes as Array).size()
		_persistencia("capas_pending_no_drena", pend > 0, 4,
			"[DBG:CAPAS] _pending_changes no se vacía (%d en cola)" % pend)

	if "_node_to_item_map" in _layersys:
		var muertas := 0
		for k in (_layersys._node_to_item_map as Dictionary).keys():
			var it = _layersys._node_to_item_map[k]
			if not is_instance_valid(k) or not is_instance_valid(it):
				muertas += 1
		if muertas > 0:
			_anom("capas_map_refs_muertas", "[DBG:CAPAS] _node_to_item_map con %d referencias muertas (nodo o TreeItem liberado)" % muertas)

func _barrer_jerarquia() -> void:
	if not is_instance_valid(_layersys) or not ("_node_to_item_map" in _layersys):
		return
	var mapa: Dictionary = _layersys._node_to_item_map
	var desajustes := 0
	for nodo in mapa.keys():
		if not is_instance_valid(nodo):
			continue
		var it = mapa[nodo]
		if not is_instance_valid(it):
			continue
		var padre_nodo = nodo.get_parent()
		if not is_instance_valid(padre_nodo) or not mapa.has(padre_nodo):
			continue   # el padre no es una fila del árbol (artboard raíz, sueltos…): no comparable
		var it_padre_esperado = mapa[padre_nodo]
		if is_instance_valid(it_padre_esperado) and it.get_parent() != it_padre_esperado:
			desajustes += 1
			if verbose and desajustes <= 3:
				_log("JERARQUIA", "desajuste árbol↔escena en '%s': su fila cuelga de otra fila" % nodo.name)
	_persistencia("jerarquia_desajuste", desajustes > 0, 2,
		"[DBG:JERARQUIA] %d fila(s) del panel NO cuelgan del mismo padre que en la escena" % maxi(desajustes, 1))

# ── Informes puntuales ──────────────────────────────────────────────────────
func _informe_bbox() -> void:
	var mt: Node = _movetool_vivo()
	if not is_instance_valid(mt):
		_log("BBOX", "no hay MoveTool activo")
	else:
		var flags := []
		for f in ["is_dragging_shape", "is_marquee", "is_resizing", "is_rotating",
				"is_dragging_artboard", "is_resizing_artboard"]:
			if (f in mt) and bool(mt.get(f)):
				flags.append(f)
		var n_sel: int = (mt.selected_shapes as Array).size() if "selected_shapes" in mt else -1
		_log("BBOX", "MoveTool  sel=%d  gestos=%s  LMB=%s" % [
			n_sel, str(flags), Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)])
	if is_instance_valid(_bbox):
		_log("BBOX", "gizmo  visible=%s  size=%s  pos=%s  padre=%s" % [
			_bbox.get("visible"), _bbox.get("size"), _bbox.get("position"),
			_bbox.get_parent().get_class() if is_instance_valid(_bbox.get_parent()) else "—"])

func _informe_capas() -> void:
	if not is_instance_valid(_layersys):
		_log("CAPAS", "LayerSystem NO registrado")
		return
	var mapa_n: int = (_layersys._node_to_item_map as Dictionary).size() if "_node_to_item_map" in _layersys else -1
	var pend: int = (_layersys._pending_changes as Array).size() if "_pending_changes" in _layersys else -1
	var bloq := "?"
	if "_bloquear_sincronizacion" in _layersys:
		bloq = str(bool(_layersys._bloquear_sincronizacion))
	_log("CAPAS", "map=%d filas  pending=%d  bloqueado=%s" % [mapa_n, pend, bloq])

func _informe_jerarquia() -> void:
	if not is_instance_valid(_layersys) or not ("artboard_container" in _layersys):
		return
	var cont = _layersys.artboard_container
	if not is_instance_valid(cont):
		_log("JERARQUIA", "artboard_container inválido")
		return
	var lineas: Array = []
	for ab in cont.get_children():
		_volcar_rama(ab, 0, lineas)
	_log("JERARQUIA", "escena real:\n  " + "\n  ".join(lineas))

func _volcar_rama(n: Node, prof: int, out: Array) -> void:
	if not (n is Node2D) or String(n.name) == "Contorno_Stroke":
		return
	out.append("%s%s [%s]" % ["  ".repeat(prof), n.name, n.get_class()])
	if prof > 12:
		out.append("%s… (corte por profundidad)" % "  ".repeat(prof + 1))
		return
	for h in n.get_children():
		_volcar_rama(h, prof + 1, out)

# ── Utilidades ──────────────────────────────────────────────────────────────
func _movetool_vivo() -> Node:
	if is_instance_valid(_movetool):
		return _movetool
	var tm := get_node_or_null("/root/ToolManager")
	if tm and tm.has_method("get_current_tool"):
		return tm.get_current_tool()
	return null

## Marca una condición que solo importa si PERSISTE `umbral` barridos seguidos
## (evita falsos positivos de estados transitorios de un solo frame).
func _persistencia(clave: String, condicion: bool, umbral: int, mensaje: String) -> void:
	if not condicion:
		if _persist.get(clave, 0) >= umbral:
			_log("SYS", "resuelto: %s" % clave)
		_persist[clave] = 0
		return
	var n: int = _persist.get(clave, 0) + 1
	_persist[clave] = n
	if n == umbral:
		_anom(clave, mensaje)

## Registra una anomalía con dedupe.
func _anom(clave: String, mensaje: String) -> void:
	var ahora := Time.get_ticks_msec()
	if _anomalias.has(clave):
		var e: Dictionary = _anomalias[clave]
		e["n"] += 1
		e["ultima_ms"] = ahora
		if e["n"] == 5 or e["n"] % 50 == 0:
			_log("SYS", "%s ×%d (repetida)" % [clave, e["n"]])
		return
	_anomalias[clave] = {"n": 1, "primera_ms": ahora, "ultima_ms": ahora}
	push_warning(mensaje)
	_log_raw(mensaje)

func _log(prefijo: String, texto: String) -> void:
	_log_raw("[DBG:%s] %s" % [prefijo, texto])

func _log_raw(linea: String) -> void:
	print(linea)
	var rt := get_node_or_null("/root/MCPRuntime")
	if rt and rt.has_method("push_runtime_log"):
		rt.push_runtime_log("info", linea)

func _has(obj: Object, sig: String) -> bool:
	return is_instance_valid(obj) and obj.has_signal(sig)

# ── Handlers de eventos ─────────────────────────────────────────────────────
func _on_seleccion(shapes: Variant) -> void:
	if not verbose:
		return
	var arr: Array = shapes if shapes is Array else []
	var nombres: Array = []
	for s in arr:
		if is_instance_valid(s):
			nombres.append(s.name)
	_log("EVENTO", "selección → %d %s" % [nombres.size(), str(nombres)])

func _on_transformado() -> void:
	if verbose:
		_log("EVENTO", "object_transformed")
