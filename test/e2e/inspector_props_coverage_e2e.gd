# =============================================================================
# UX-06: cobertura del Inspector. En Modern y Pro, con cada tipo de objeto
# seleccionado, se usan TODOS los controles visibles del inspector (y de los
# desplegables que abren) y se apunta qué propiedades de InspectorCore.PROPS
# se escriben de verdad (señal prop_written: valor cambiado + paso de
# deshacer). Falla si una propiedad que el objeto tiene no se puede editar
# desde la interfaz, o si deshacer no devuelve el objeto a como estaba.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/inspector_props_coverage_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
## No se editan desde el inspector, a propósito:
const EXCLUDED := {
	"text": "el contenido se escribe en el lienzo",
	"custom_shader": "lo pone la sección Shader al aplicar código",
	"model_path": "se elige con un diálogo de archivo",
}
## Alias: escribir una cuenta como la otra (el color plano es un «paint» sólido).
const ALIAS := {"fill_paint": "fill_color", "stroke_paint": "stroke_color"}
## Botones que no se pulsan (borran, abren diálogos, convierten el objeto…).
const DENY := ["eliminar", "borrar", "export", "instalar", "carpeta", "abrir", "cargar",
	"importar", "desinstalar", "guardar", "ejecutar", "vectoriz", "crear", "cerrar",
	"unir", "restar", "intersec", "excluir", "combinar", "separar", "agrupar",
	"convertir", "curvas", "duplicar", "aplanar", "rasteriz", "recargar", "api",
	"buscar", "bloquear", "close", "✕", "×", "reemplazar", "descargar", "google", "pegar", "copiar",
	"cambiar archivo", "📂"]

var fails := 0
var cur_obj: Node2D = null
var covered := 0
var written := {}
var _done := {}
var _sib := {}
var _opt_rounds := {}
var _retry := {}
## Propiedades que tiene algún objeto probado (para «PROPS sin control»).
var seen_props := {}

## Huella barata de lo visible bajo el inspector y sus desplegables: si un
## clic muestra u oculta algo (pestaña, sección, desplegable) cambia.
func _vis_sig(panel_root: Control) -> int:
	var ids := PackedInt64Array()
	var texts := PackedStringArray()
	for r in [panel_root] + _popups():
		if not is_instance_valid(r):
			continue
		for c in (r as Node).find_children("*", "Control", true, false):
			if (c as Control).is_visible_in_tree():
				ids.append(c.get_instance_id())
				if c is Label:
					texts.append((c as Label).text)   # «Relleno» → «Trazo», estado…
	return hash([ids, texts])

## ¿Se juzga si este control «hace algo»? Solo los de valor o acción
## (botones, campos, deslizadores, desplegables). Un clic en un panel, una
## etiqueta o un widget de arrastre (reloj de rotación, editor de perfil)
## no tiene por qué hacer nada.
func _judged(c: Control) -> bool:
	if c is RichTextLabel or c is Label:
		return false
	return c is BaseButton or c is Range or c is LineEdit \
			or c.has_signal("value_changed") or c.has_signal("color_changed")

## Huella del documento: el objeto (todas sus propiedades), la página y la
## cámara. Botones de vista 3D, formato de página… cambian esto.
func _doc_sig(obj: Node, expected: Dictionary) -> String:
	var ic := root.get_node("InspectorCore")
	var parts: Array = []
	if is_instance_valid(obj):
		for p in expected:
			parts.append(str(ic._read(obj, p)))
		for k in ["view_yaw", "view_pitch", "view_target", "camera_distance"]:
			if k in obj:
				parts.append(str(obj.get(k)))
	var cv = get_first_node_in_group("_vectopen_canvas")
	if cv and cv.get("camera"):
		parts.append(str(cv.camera.zoom) + str(cv.camera.position))
	var m = cv.get_node_or_null("manager_script") if cv else null
	var ab = m.get_active_artboard() if m and m.has_method("get_active_artboard") else null
	if ab:
		parts.append(str(ab.get("size")) + str(ab.get_parent().get_child_count()))
	return "|".join(parts)

## Estado propio del control (marcado, valor, texto, color, selección).
func _own_state(c: Control) -> Variant:
	if not is_instance_valid(c):
		return null
	if c is OptionButton:
		return (c as OptionButton).selected
	if c is Button:
		# Los botones «interruptor» de estilo propio cambian su caja de fondo.
		var sb = c.get_theme_stylebox("normal") if c.has_theme_stylebox_override("normal") else null
		return [(c as Button).button_pressed, (c as Button).text, (c as Button).icon, (c as Button).modulate,
			c.tooltip_text, sb.get_instance_id() if sb else 0, (sb as StyleBoxFlat).bg_color if sb is StyleBoxFlat else Color()]
	if c is BaseButton:
		return (c as BaseButton).button_pressed
	if c is Range:
		return (c as Range).value
	if c is LineEdit:
		return (c as LineEdit).text
	for k in ["value", "color"]:
		if k in c:
			return c.get(k)
	return null

func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and str(a) == str(b)

func _init() -> void:
	_run.call_deferred()
	create_timer(1500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _label(c: Control) -> String:
	var t := ""
	if c is Button:
		t = (c as Button).text
	return (t + " " + c.tooltip_text + " " + String(c.name)).to_lower()

func _skip_subtree(c: Node) -> bool:
	var n := c
	var fx_done := written.has("effects")
	var fl_done := written.has("filters")
	while n:
		if String(n.name) in ["SecScript", "SecShader", "SecVectorize", "ScriptContent", "ShaderContent", "VectorizeContent"]:
			return true
		# Formato de PÁGINA (papel / redes / icono): no es del objeto.
		if String(n.scene_file_path).ends_with("panel_config_windows_element.tscn"):
			return true
		# Con el efecto / filtro ya probado, sus tarjetas (decenas de
		# controles cada una) no aportan nada.
		if fx_done and String(n.name) in ["EffectsList", "FullEffects"]:
			return true
		if fl_done and String(n.name) in ["FilterList", "FiltersContent"]:
			return true
		n = n.get_parent()
	return false

## Orden: valores primero, luego casillas y desplegables, y al final botones
## (que pueden cambiar de pestaña u ocultar lo anterior).
var _tab_ids := {}

func _prio(c: Control) -> int:
	# Pestañas de página (Pro): al final, cuando ya se usó lo de la página
	# visible; si no, la página se ocultaba antes de probar sus controles.
	if _tab_ids.has(c.get_instance_id()):
		return 3
	if not (c is BaseButton):
		return 0
	if c is CheckBox or c is CheckButton or c is OptionButton:
		return 1
	return 2

func _interactive(c: Control) -> bool:
	# Rejillas de muestras (paletas): con 3 iguales basta.
	var par := c.get_parent()
	if par and par.get_child_count() > 6:
		var key := "%d|%s|%s" % [par.get_instance_id(), c.get_class(), str(c.get_script())]
		var n: int = _sib.get(key, 0)
		if n >= 3 and not _sib.has(c.get_instance_id()):
			return false
		if not _sib.has(c.get_instance_id()):
			_sib[c.get_instance_id()] = true
			_sib[key] = n + 1
	return _interactive_kind(c)

func _interactive_kind(c: Control) -> bool:
	if c is BaseButton or c is Range or c is LineEdit:
		return not (c is ScrollBar)
	if c.has_signal("value_changed") or c.has_signal("color_changed"):
		return true
	return c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_script() != null and not (c is Container)

## Orden estable por prioridad (sort_custom no es estable: el orden entre
## iguales cambiaba de una ejecución a otra).
func _sorted(arr: Array) -> Array:
	var keyed: Array = []
	for i in arr.size():
		keyed.append([_prio(arr[i]), i, arr[i]])
	keyed.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	return keyed.map(func(k): return k[2])

func _controls(roots: Array) -> Array:
	var out := []
	for r in roots:
		if not is_instance_valid(r):
			continue
		for c in (r as Node).find_children("*", "Control", true, false):
			if (c as Control).is_visible_in_tree() and not _done.has(c.get_instance_id()) and _interactive(c) and not _skip_subtree(c):
				out.append(c)
	return out

func _sig_args(c: Object, name: String) -> int:
	for sig in c.get_signal_list():
		if String(sig["name"]) == name:
			return (sig["args"] as Array).size()
	return -1

## Arrastre de un valor como lo hace el ratón: empieza, cambia, termina.
func _drag_value(c: Object, nv: float) -> void:
	if _sig_args(c, "drag_started") == 0:
		c.emit_signal("drag_started")
	c.set("value", nv)
	if not (c is Range):
		c.emit_signal("value_changed", c.get("value"))
	for n in ["drag_ended", "scrub_ended"]:
		var na := _sig_args(c, n)
		if na == 0:
			c.emit_signal(n)
		elif na == 1:
			c.emit_signal(n, true if c is Range else c.get("value"))

## Usa un control como lo haría el usuario (cambiar valor, elegir, marcar).
## `_acted` queda en false si el control se saltó a propósito (lista DENY,
## desactivado, cabecera ya abierta…): esos no cuentan como «sin efecto».
var _acted := false
## Un color DISTINTO en cada uso: con uno fijo, si un control anterior ya lo
## había puesto, el siguiente «no cambiaba nada» y contaba como sin efecto.
var _color_i := 0
func _next_color() -> Color:
	_color_i += 1
	return Color.from_hsv(fmod(0.13 + _color_i * 0.618034, 1.0), 0.7, 0.8)

func exercise(c: Control) -> void:
	_done[c.get_instance_id()] = true
	_acted = true
	await _exercise(c)

func _exercise(c: Control) -> void:
	if c is OptionButton:
		var ob := c as OptionButton
		if ob.item_count > 1:
			var i := (ob.selected + 1) % ob.item_count
			ob.select(i)
			ob.item_selected.emit(i)
	elif c is Range:
		var r := c as Range
		var span := r.max_value - r.min_value
		var nv := r.value + maxf(r.step, span * 0.13)
		if nv > r.max_value:
			nv = r.value - maxf(r.step, span * 0.13)
		_drag_value(r, nv)
	elif c is LineEdit:
		var le := c as LineEdit
		if not le.editable:
			_acted = false
			return
		var t := le.text.strip_edges()
		var nt := ""
		if t.trim_suffix(" pt").trim_suffix(" px").trim_suffix("%").trim_suffix("°").is_valid_float():
			nt = str(float(t.trim_suffix(" pt").trim_suffix(" px").trim_suffix("%").trim_suffix("°")) + 3.0)
		elif t.begins_with("#"):
			nt = "#336699"
		elif is_instance_valid(cur_obj) and t == String(cur_obj.name):
			nt = t + " e2e"
		elif String(le.name) == "DashPattern":
			nt = "12 4 2 4" if t != "12 4 2 4" else "9 3"   # patrón de guiones (UX-18)
		else:
			_acted = false
			return
		le.text = nt
		le.text_submitted.emit(nt)
	elif c is ColorPickerButton:
		var cp := c as ColorPickerButton
		cp.color = _next_color()
		cp.color_changed.emit(cp.color)
	elif c is BaseButton and not (c.has_signal("color_changed") and "color" in c):
		var b := c as BaseButton
		# Quitar un efecto o filtro recién añadido no aporta nada a la prueba.
		if String(b.name) == "Remove":
			_acted = false
			return
		if b.disabled:
			_acted = false
			return
		# Cabecera de una sección ya abierta: pulsarla la plegaría.
		if b is Button and (b as Button).text.begins_with("▾"):
			_acted = false
			return
		var lab := _label(c)
		for d in DENY:
			if lab.contains(d):
				_acted = false
				return
		if b.toggle_mode:
			b.button_pressed = not b.button_pressed
			if b.toggled.get_connections().is_empty():
				b.pressed.emit()
		else:
			b.pressed.emit()
	elif c.has_signal("value_changed") and "value" in c and c.get("value") is float:
		var v: float = c.get("value")
		var mx = c.get("max_value")
		var nv: float = v + maxf(float(c.get("step")) if c.get("step") != null else 1.0, 1.0)
		if mx != null and nv > float(mx):
			nv = v - 1.0
		_drag_value(c, nv)
	elif c.has_signal("color_changed") and "color" in c and c.get("color") is Color:
		c.set("color", _next_color())
		c.emit_signal("color_changed", c.get("color"))
	elif c.mouse_filter == Control.MOUSE_FILTER_STOP and not (c is Container and c.get_script() == null) \
			and not (c is LineEdit or c is TextEdit or c is ScrollBar or c is Label) \
			and (c.get_script() != null or not c.gui_input.get_connections().is_empty()):
		await real_click(c)
	await process_frame
	await _pick_menus()

func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

## Clic de ratón de verdad, solo si el control es lo que hay bajo el puntero.
func real_click(c: Control) -> void:
	# Dentro de una lista con desplazamiento: traerlo a la vista primero.
	var n := c.get_parent()
	while n:
		if n is ScrollContainer:
			(n as ScrollContainer).ensure_control_visible(c)
			await frames(2)
			break
		n = n.get_parent()
	if not is_instance_valid(c):
		return
	var r := c.get_global_rect()
	if r.size.x < 2 or r.size.y < 2:
		return
	var at := r.get_center()
	var vp := c.get_viewport()
	if vp != root:
		return
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	await _send(mv)
	var hit := root.gui_get_hovered_control()
	if not (hit == c or (hit != null and c.is_ancestor_of(hit))):
		return
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = at
		ev.global_position = at
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		await _send(ev)

## Si se abrió un menú (añadir efecto, filtro…), elegir su primera opción.
func _pick_menus() -> void:
	for m in root.find_children("*", "PopupMenu", true, false):
		var pm := m as PopupMenu
		if not pm.visible or _done.has(pm.get_instance_id()):
			continue
		_done[pm.get_instance_id()] = true
		for i in pm.item_count:
			if pm.is_item_separator(i) or pm.is_item_disabled(i) or pm.get_item_submenu_node(i) != null:
				continue
			var lab := pm.get_item_text(i).to_lower()
			var bad := false
			for d in DENY:
				if lab.contains(d):
					bad = true
			if bad:
				continue
			pm.hide()
			pm.id_pressed.emit(pm.get_item_id(i))
			pm.index_pressed.emit(i)
			await frames(2)
			break
		pm.hide()

func _popups() -> Array:
	var out := []
	# Desplegables propios (trazo, letras…): PanelContainer en su CanvasLayer.
	for c in root.find_children("*", "PanelContainer", true, false):
		var sc = c.get_script()
		if sc and String(sc.resource_path).ends_with("_popover.gd") and (c as Control).is_visible_in_tree():
			out.append(c)
	for w in root.find_children("*", "Window", true, false):
		if (w as Window).visible and w != root:
			out.append(w)
	for p in root.find_children("*", "PopupPanel", true, false):
		if (p as Window).visible:
			out.append(p)
	return out

func _close_popups() -> void:
	for c in root.find_children("*", "PanelContainer", true, false):
		var sc = c.get_script()
		if sc and String(sc.resource_path).ends_with("_popover.gd"):
			(c as Control).visible = false
	for w in _popups():
		if w is Popup or w is PopupPanel:
			(w as Window).hide()

func cover(mode: String, panel_root: Control, obj: Node2D, kind: String) -> void:
	var ic := root.get_node("InspectorCore")
	var api = root.get_node("PluginManager").api
	var hm := root.get_node("HistoryManager")
	_close_popups()
	written.clear()
	_done.clear()
	_sib.clear()
	_opt_rounds.clear()
	_retry.clear()
	cur_obj = obj
	api.select(obj)
	await frames(8)
	if OS.has_environment("UX06_SHOT"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("UX06_SHOT") + "/%s_%s.png" % [mode, kind])
		return
	var expected: Dictionary = ic._props_for(obj).duplicate()
	# UX06_PROPS: solo las propiedades que empiezan por alguno de estos
	# prefijos (p. ej. «stroke_» para la paridad del panel de trazos, UX-08).
	var only_props := OS.get_environment("UX06_PROPS")
	if only_props != "":
		for p in expected.keys():
			var keep := false
			for pre in only_props.split(","):
				if String(p).begins_with(pre):
					keep = true
			if not keep:
				expected.erase(p)
		check("%s/%s: propiedades «%s» a revisar" % [mode, kind, only_props], expected.size() > 0,
			", ".join(PackedStringArray(expected.keys())))
	var before := {}
	for p in expected:
		before[p] = ic._read(obj, p)
	var ur = hm._undo_redo
	var base_action: int = ur.undo_stack.size()
	var strict := OS.has_environment("UX12_STRICT")
	var dead: Array = []
	var on_w := func(p: String) -> void:
		written[ALIAS.get(p, p)] = true
	ic.prop_written.connect(on_w)
	# Cola en profundidad: lo que aparece al pulsar algo (una pestaña, un
	# desplegable) se usa ANTES de seguir, porque la siguiente pestaña lo oculta.
	# Pro: página a página (pestañas A: Color/Muestras/Trazo; B: Transformar/
	# Texto/Efectos), para no ocultar una página antes de usar sus controles.
	var tabs_a = panel_root.get("_tabs_a")
	var tabs_b = panel_root.get("_tabs_b")
	# Vistas: [pestaña A, pestaña B, sub-pestaña de Texto (General/Párrafo)].
	var views: Array = [[-1, -1, -1]]
	if tabs_a is Array and tabs_b is Array:
		views.clear()
		for i in maxi((tabs_a as Array).size(), (tabs_b as Array).size()):
			views.append([i, i, 0])
		views.append([0, 1, 1])          # Texto → Párrafo
		var subs: Array = [panel_root.get("_tab_typo_general"), panel_root.get("_tab_typo_parrafo")]
		for t in (tabs_a as Array) + (tabs_b as Array) + subs:
			if t is Object and is_instance_valid(t):
				_done[t.get_instance_id()] = true
	var queue: Array = []
	var seen := {}
	var guard := 0
	for v in views:
		if int(v[0]) >= 0:
			if int(v[0]) < (tabs_a as Array).size():
				panel_root.call("_select_tab_a", int(v[0]))
			if int(v[1]) < (tabs_b as Array).size():
				panel_root.call("_select_tab_b", int(v[1]))
			if panel_root.has_method("_switch_typography_subtab"):
				panel_root.call("_switch_typography_subtab", int(v[2]))
			_retry.clear()
			await frames(4)
		queue = _sorted(_controls([panel_root] + _popups()))
		if OS.has_environment("UX06_DEBUG"):
			for b in panel_root.find_children("Btn_italic", "Button", true, false):
				print("DBGQ italic vis=%s inq=%s skip=%s done=%s" % [b.is_visible_in_tree(), queue.has(b), _skip_subtree(b), _done.has(b.get_instance_id())])
		for c in queue:
			seen[c.get_instance_id()] = true
		while not queue.is_empty() and guard < 20000:
			guard += 1
			var c = queue.pop_front()
			if OS.has_environment("UX06_DEBUG") and is_instance_valid(c) and String(c.name) == "Btn_italic":
				print("DBGQ pop italic vis=%s done=%s" % [c.is_visible_in_tree(), _done.has(c.get_instance_id())])
			if not is_instance_valid(obj):
				print("DBGQ objeto liberado en el paso %d" % guard)
				break
			if not is_instance_valid(c) or _done.has(c.get_instance_id()):
				continue
			if not (c as Control).is_visible_in_tree():
				# Oculto ahora (otra pestaña, sección plegada…): reintentar luego.
				var r: int = _retry.get(c.get_instance_id(), 0)
				if r < 2:
					_retry[c.get_instance_id()] = r + 1
					queue.push_back(c)
				continue
			var n0 := written.size()
			var h0: int = ur.undo_stack.size()
			var vis0 := _vis_sig(panel_root) if strict else 0
			var doc0 := _doc_sig(obj, expected) if strict else ""
			var sel0: Array = ic.selection().duplicate()
			var st0 = _own_state(c) if strict else null
			# Opción que ya es el valor actual (p. ej. «Sólido» con el trazo
			# sólido): pulsarla no cambia nada y es lo correcto.
			var already: bool = strict and c.has_meta("prop") and c.has_meta("value") \
					and ic._approx_eq(ic._read(obj, String(c.get_meta("prop"))), c.get_meta("value"))
			var snap := {}
			if OS.has_environment("UX06_DEBUG"):
				for p in expected:
					snap[p] = ic._read(obj, p)
			var ft := panel_root.find_child("FullTypography", true, false) as Control
			var ft_before := ft != null and ft.is_visible_in_tree()
			await exercise(c)
			# Muestra de Relleno / Trazo (Pro): cambia a qué escribe el selector;
			# se vuelve a probar el selector con el nuevo destino.
			if is_instance_valid(c) and c.get_script() and String(c.tooltip_text) in [tr("Relleno"), tr("Trazo")] and c is BaseButton:
				var again: Array = []
				for g in panel_root.find_children("*", "", true, false):
					if g.get_script() and g.get_script().get_global_name() == "GestorColor":
						for gc in g.find_children("*", "Control", true, false):
							_done.erase(gc.get_instance_id())
						again.append_array(_controls([g]))
				queue = _sorted(again) + queue
			if strict and _acted and not already and is_instance_valid(c) and _judged(c):
				await process_frame
				var moved: bool = written.size() != n0 or ur.undo_stack.size() != h0 \
						or _vis_sig(panel_root) != vis0 or ic.selection() != sel0 \
						or not _same(st0, _own_state(c)) or _doc_sig(obj, expected) != doc0
				if not moved:
					dead.append(c)
			if OS.has_environment("UX06_DEBUG") and ft_before and is_instance_valid(ft) and not ft.is_visible_in_tree():
				print("DBGQ tipografía oculta tras %s «%s» %s sel=%s" % [c.get_class() if is_instance_valid(c) else "?", (c as Control).tooltip_text if is_instance_valid(c) else "", str(c.get_path()).right(60) if is_instance_valid(c) else "", ic.selection().size()])
			if OS.has_environment("UX06_DEBUG") and is_instance_valid(obj) and is_instance_valid(c):
				var sc = c.get_script()
				var silent := []
				for p in expected:
					if not ic._approx_eq(snap[p], ic._read(obj, p)) and not written.has(ALIAS.get(p, p)):
						silent.append(p)
				var path := str(c.get_path()).replace("/root/", "").right(70)
				print("DBG %s %s «%s» -> %s%s  @%s" % [c.get_class(), String(sc.resource_path).get_file() if sc else "", (c as Control).tooltip_text.left(30) if not (c is Button) else (c as Button).text.left(30), written.keys().slice(n0), ("  SIN-DESHACER " + str(silent)) if not silent.is_empty() else "", path])
			# Un desplegable se prueba con todas sus opciones (cada forma de la
			# elipse muestra campos distintos).
			if is_instance_valid(c) and c is OptionButton:
				var k: int = _opt_rounds.get(c.get_instance_id(), 1)
				if k < (c as OptionButton).item_count - 1:
					_opt_rounds[c.get_instance_id()] = k + 1
					_done.erase(c.get_instance_id())
					queue.push_back(c)
			if ic.selection() != [obj] and is_instance_valid(obj):
				api.select(obj)
				await process_frame
			var fresh: Array = []
			for n in _controls([panel_root] + _popups()):
				if not seen.has(n.get_instance_id()):
					seen[n.get_instance_id()] = true
					fresh.append(n)
			queue = _sorted(fresh) + queue
	if OS.has_environment("UX06_DEBUG"):
		print("DBGQ fin: pasos=%d cola=%d" % [guard, queue.size()])
	# Lista de fuentes: se rellena al abrirse y sus filas son muchas; se abre
	# y se elige una fuente instalada distinta de la actual.
	if expected.has("font_family") and not written.has("font_family") and is_instance_valid(obj):
		if panel_root.has_method("_switch_typography_subtab"):
			panel_root.call("_select_tab_b", 1)          # Texto → General
			panel_root.call("_switch_typography_subtab", 0)
			await frames(4)
		for fb in panel_root.find_children("Button_font", "BaseButton", true, false):
			if not (fb as Control).is_visible_in_tree():
				continue
			(fb as BaseButton).pressed.emit()
			await frames(6)
			# Quitar el filtro y la búsqueda que hayan quedado de antes.
			for le in fb.find_children("*", "LineEdit", true, false):
				(le as LineEdit).text = ""
				(le as LineEdit).text_changed.emit("")
			for tb in fb.find_children("*", "Button", true, false):
				if (tb as Button).text == "Todas":
					(tb as Button).pressed.emit()
			await frames(6)
			var cur := String(ic._read(obj, "font_family"))
			if OS.has_environment("UX06_DEBUG"):
				var rows := root.find_children("*", "Button", true, false).filter(func(r): return r.has_meta("google_state"))
				print("DBGQ filas de fuente: %d bajo el botón=%d actual=%s" % [rows.size(), fb.find_children("*", "Button", true, false).filter(func(r): return r.has_meta("google_state")).size(), cur])
			for row in fb.find_children("*", "Button", true, false):
				if row.has_meta("google_state") and String(row.get_meta("google_state")) not in ["remote", "downloading"] \
						and not String(row.tooltip_text + " " + row.name).contains(cur):
					(row as Button).pressed.emit()
					await frames(4)
					if written.has("font_family"):
						break
			break
	ic.prop_written.disconnect(on_w)
	_close_popups()
	await frames(4)
	if not is_instance_valid(obj):
		check("%s/%s: el objeto sigue existiendo" % [mode, kind], false)
		return
	var missing := []
	for p in expected:
		var key: String = ALIAS.get(p, p)
		if EXCLUDED.has(p) or written.has(key):
			continue
		# El radio común es la vista de los cuatro radios de esquina.
		if p == "corner_radius" and written.has("corner_tl"):
			continue
		missing.append(p)
	check("%s/%s: todas sus propiedades se editan desde el inspector" % [mode, kind], missing.is_empty(),
		"faltan: %s" % ", ".join(missing))
	for p in expected:
		seen_props[p] = true
	var after := {}
	if strict:
		# Segunda oportunidad: con el resto de controles ya usados, el estado
		# es otro (otra pestaña activa, otro estilo…). Si vuelve a no hacer
		# nada, no hace nada. Las opciones de un desplegable (meta «prop»)
		# ya se juzgaron contra el valor actual.
		var confirmed: Array = []
		for c in dead:
			if not is_instance_valid(c):
				continue
			if not c.has_meta("prop") and not (c as Control).is_visible_in_tree():
				print("INFO %s/%s: sin confirmar (oculto al repetir): %s «%s»" % [mode, kind, c.get_class(), _label(c).strip_edges().left(40)])
				continue
			if not c.has_meta("prop"):
				# Opción de un grupo (vistas, pestañas, muestras…): pulsar antes
				# OTRA del grupo, para que esta no sea ya la activa.
				var par: Node = c.get_parent()
				if par and c is BaseButton:
					for sib in par.get_children():
						if sib != c and sib is BaseButton and (sib as Control).is_visible_in_tree() and not (sib as BaseButton).disabled:
							var deny := false
							for d in DENY:
								if _label(sib).contains(d):
									deny = true
							if not deny:
								(sib as BaseButton).pressed.emit()
								await frames(2)
								break
				_done.erase(c.get_instance_id())
				var n1 := written.size()
				var h1: int = ur.undo_stack.size()
				var v1 := _vis_sig(panel_root)
				var s1 = _own_state(c)
				var d1 := _doc_sig(obj, expected)
				ic.prop_written.connect(on_w)
				await exercise(c)
				ic.prop_written.disconnect(on_w)
				await process_frame
				if written.size() != n1 or ur.undo_stack.size() != h1 or _vis_sig(panel_root) != v1 \
						or not _same(s1, _own_state(c)) or _doc_sig(obj, expected) != d1:
					continue
				_close_popups()
			if not is_instance_valid(c):
				continue
			confirmed.append("%s «%s» %s" % [c.get_class(), _label(c).strip_edges().left(40), str(c.get_path()).right(48)])
		check("%s/%s: ningún control sin efecto" % [mode, kind], confirmed.is_empty(), "%d: %s" % [confirmed.size(), " | ".join(confirmed.slice(0, 14))])
		for p in expected:
			after[p] = ic._read(obj, p)
	var steps: int = ur.undo_stack.size() - base_action
	# Deshacer todo lo hecho devuelve el objeto a como estaba.
	var safety := 0
	while ur.undo_stack.size() > base_action and hm.can_undo() and safety < 5000:
		hm.undo()
		safety += 1
	await frames(4)
	var diff := []
	for p in before:
		if p in ["name"]:
			continue
		var now = ic._read(obj, p) if is_instance_valid(obj) else null
		# Texto autoajustado: su alto/ancho se recalcula de la maquetación (no
		# se guarda); se admite una diferencia de unos píxeles (ver PENDIENTE.md).
		if kind == "text" and p in ["width", "height"] and now is float and absf(float(now) - float(before[p])) <= 6.0:
			continue
		if not ic._approx_eq(now, before[p]):
			diff.append("%s %s→%s" % [p, str(before[p]).left(160), str(now).left(160)])
	check("%s/%s: deshacer restaura todas las propiedades" % [mode, kind], diff.is_empty(), "difieren: %s" % ", ".join(diff))
	if strict and is_instance_valid(obj):
		# Rehacer todo deja el objeto como quedó tras usar los controles.
		var k := 0
		while hm.can_redo() and k < steps + 5:
			hm.redo()
			k += 1
		await frames(4)
		var rdiff := []
		for p in after:
			if p in ["name"]:
				continue
			var now = ic._read(obj, p)
			if kind == "text" and p in ["width", "height"] and now is float and absf(float(now) - float(after[p])) <= 6.0:
				continue
			if not ic._approx_eq(now, after[p]):
				rdiff.append("%s %s→%s" % [p, str(after[p]).left(160), str(now).left(160)])
		check("%s/%s: rehacer repite todos los cambios (%d pasos)" % [mode, kind, k], rdiff.is_empty(), "difieren: %s" % ", ".join(rdiff))
		var safety2 := 0
		while ur.undo_stack.size() > base_action and hm.can_undo() and safety2 < 5000:
			hm.undo()
			safety2 += 1
		await frames(4)
	covered += 1

func make_objects(api) -> Dictionary:
	var c := Vector2(500, 400)
	var o := {}
	o["rect"] = api.add_rect(c, Vector2(200, 120), 8.0)
	o["ellipse"] = api.add_ellipse(c + Vector2(260, 0), Vector2(160, 160))
	o["polygon"] = api.add_polygon(c + Vector2(0, 220), 80.0, 6)
	o["star"] = api.add_star(c + Vector2(260, 220), 80.0, 5, 0.5)
	var cv := Curve2D.new()
	cv.add_point(Vector2(0, 0), Vector2.ZERO, Vector2(60, -60))
	cv.add_point(Vector2(200, 0), Vector2(-60, 60), Vector2.ZERO)
	o["path"] = api.add_curve(cv, false)
	o["text"] = api.add_text(c + Vector2(-200, -200), "Texto de prueba", 24, Color.BLACK)
	# Gota paramétrica (como la crea su herramienta): curvatura editable.
	var dpts: PackedVector2Array = load("res://script_gdscript/tools/WaterDropTool.gd").drop_points(70.0, 0.0, 0.5)
	for i in dpts.size():
		dpts[i] += c + Vector2(520, 0)
	var drop = api.add_shape(dpts, "Gota")
	if drop:
		drop.set_meta("shape_kind", "drop")
		drop.set_meta("drop_radius", 70.0)
		drop.set_meta("drop_rotation", 0.0)
		drop.set_meta("drop_curvature", 0.5)
		o["drop"] = drop
	# Modelo 3D sin archivo: tiene todas sus propiedades (cámara, luz…).
	var m = load("res://script_gdscript/shapes/VectorModel3D.gd").new()
	m.name = "Modelo"
	m.size = Vector2(240, 180)
	o["model3d"] = api.add(m)
	m.set_doc_position(load("res://script_gdscript/core/DVec2.gd").from_v2(c + Vector2(-260, 260)))
	for k in o:
		var n = o[k]
		if n and "stroke_width" in n:
			n.stroke_width = 2.0
	return o

func inspector_root(mode: String) -> Control:
	if mode == "smart":
		# Smart: el panel flotante «Trazos y Borde» (PanelTrazos).
		for c in root.find_children("*", "PanelContainer", true, false):
			if c.get_script() and c.get_script().get_global_name() == "PanelTrazos":
				(c as Control).visible = true
				var p := c.get_parent()
				while p and p is CanvasItem:
					(p as CanvasItem).visible = true
					p = p.get_parent()
				return c
		return null
	var want := "docked_inspector.gd" if mode == "modern" else "pro_studio.gd"
	for c in root.find_children("*", "Control", true, false):
		var s = c.get_script()
		if s and String(s.resource_path).get_file() == want and (c as Control).is_visible_in_tree():
			return c
	return null

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var api = root.get_node("PluginManager").api
	# Sin límite de pasos: la prueba deshace TODO lo que hizo con cada objeto.
	root.get_node("HistoryManager")._undo_redo.max_history = 100000
	var only := OS.get_environment("UX06_ONLY")
	var modes := ["modern", "professional"]
	if OS.get_environment("UX06_MODE") != "":
		modes = [OS.get_environment("UX06_MODE")]
	if OS.get_environment("UX06_MODES") != "":
		modes = Array(OS.get_environment("UX06_MODES").split(","))
	for mode in modes:
		root.get_node("GlobalUI").set_ui_mode(mode)
		await frames(40)
		var objs := make_objects(api)
		await frames(10)
		for kind in objs:
			if only != "" and not only.split(",").has(kind):
				continue
			var pr := inspector_root(mode)
			check("%s: inspector visible" % mode, pr != null)
			if pr == null:
				break
			await cover(mode, pr, objs[kind], kind)
		api.clear_selection()
		for k in objs:
			if is_instance_valid(objs[k]):
				api.delete(objs[k])
		await frames(6)
	if OS.has_environment("UX12_STRICT") and only == "":
		var orphan := []
		for p in root.get_node("InspectorCore").PROPS:
			if not seen_props.has(p) and not EXCLUDED.has(p) and not ALIAS.has(p):
				orphan.append(p)
		check("cada propiedad declarada en PROPS la tiene algún objeto", orphan.is_empty(), ", ".join(orphan))
	var want := (8 if only == "" else only.split(",").size()) * modes.size()
	if not OS.has_environment("UX06_SHOT"):
		check("se revisaron todos los objetos en todos los modos", covered == want, "%d/%d" % [covered, want])
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		if f:
			f.store_string(ui_backup)
	print("RESULT: %s (%d fallos)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
