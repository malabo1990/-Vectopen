# =============================================================================
# RUTA: res://script_gdscript/ui/panels/effects/vectorize_panel.gd
# Pestaña "Vectorizar" del panel Efectos (antes una maqueta: 4 campos
# "pixels" y un botón que emitía una señal que nadie escuchaba).
#
# Convierte la IMAGEN seleccionada (Sprite2D) en trazados Bézier editables
# (VectorPath, los mismos de la pluma) con el GDExtension nativo:
#   [quitar fondo con IA] → [mejorar ×4 con IA] → vtracer (curvas Bézier) →
#   grupo "Vectorizado" colocado EXACTAMENTE sobre la imagen (deshacer).
# El trabajo nativo corre en un hilo de Rust (VectorizerJob): la app no se
# congela con fotos grandes. También: "Quitar fondo" / "Mejorar ×4" sobre la
# propia imagen (con deshacer).
# =============================================================================
extends VBoxContainer

const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const PANEL_NAME := "VectorizePanel"

const PRESETS := {
	"Logo / icono": {"color_mode": "color", "color_precision": 6, "filter_speckle": 4, "corner_threshold": 60, "layer_difference": 16, "mode": "spline"},
	"Ilustración": {"color_mode": "color", "color_precision": 7, "filter_speckle": 6, "corner_threshold": 60, "layer_difference": 12, "mode": "spline"},
	"Foto (más detalle)": {"color_mode": "color", "color_precision": 8, "filter_speckle": 10, "corner_threshold": 90, "layer_difference": 8, "mode": "spline"},
	"Blanco y negro": {"color_mode": "binary", "filter_speckle": 4, "corner_threshold": 60, "mode": "spline"},
	"Pixel art": {"color_mode": "color", "color_precision": 8, "filter_speckle": 0, "corner_threshold": 180, "layer_difference": 0, "mode": "pixel"},
}

var _status: Label = null
var _preview: TextureRect = null
var _opt_preset: OptionButton = null
var _opt_mode: OptionButton = null
var _chk_bw: CheckBox = null
var _sl_detail: HSlider = null
var _sl_colors: HSlider = null
var _sl_corners: HSlider = null
var _chk_bg: CheckBox = null
var _chk_up: CheckBox = null
var _chk_hide: CheckBox = null
var _btn_go: Button = null
var _btn_bg: Button = null
var _btn_up: Button = null
var _labels: Array[Label] = []
var _busy := false
var _task_result: Dictionary = {}

static func install(effects_panel: Control) -> Control:
	if effects_panel == null:
		return null
	var content := effects_panel.get_parent()
	var host := content.get_node_or_null("Vectorizar") as Control if content else null
	if host == null:
		return null
	var existing := host.find_child(PANEL_NAME, true, false)
	if existing:
		return existing
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	var panel: Control = load("res://script_gdscript/ui/panels/effects/vectorize_panel.gd").new()
	panel.name = PANEL_NAME
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_top = 8
	panel.offset_bottom = -8
	# Como las demás pestañas: el anfitrión ocupa el alto (antes medía 0).
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(panel)
	return panel

func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(96, 96)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_preview)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(_label("VECTORIZAR IMAGEN", true))
	_status = _label("Selecciona una imagen del lienzo.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_status)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	grid.add_child(_label("Preajuste"))
	_opt_preset = OptionButton.new()
	for k in PRESETS:
		_opt_preset.add_item(k)
	_opt_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_preset.item_selected.connect(func(i: int) -> void: _apply_preset(_opt_preset.get_item_text(i)))
	grid.add_child(_opt_preset)
	grid.add_child(_label("Trazados"))
	_opt_mode = OptionButton.new()
	_opt_mode.add_item("Curvas Bézier")
	_opt_mode.add_item("Polígonos")
	_opt_mode.add_item("Píxeles")
	_opt_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_opt_mode)
	grid.add_child(_label("Detalle"))
	_sl_detail = _slider(grid, 0, 32, 4, "Ignora manchas más pequeñas que N px (menos = más detalle)")
	grid.add_child(_label("Colores"))
	_sl_colors = _slider(grid, 1, 8, 6, "Precisión de color (más = más capas de color)")
	grid.add_child(_label("Esquinas"))
	_sl_corners = _slider(grid, 0, 180, 60, "Ángulo a partir del cual un vértice es esquina (°)")
	_chk_bw = _check(self, "Blanco y negro", "Trazos negros sobre fondo transparente (logos, firmas)")
	_chk_bg = _check(self, "Quitar el fondo antes (IA)", "Elimina el fondo con un modelo de IA antes de vectorizar")
	_chk_up = _check(self, "Mejorar ×4 antes (IA, imágenes pequeñas)", "Escala la imagen ×4 con IA: curvas más limpias en imágenes pequeñas")
	_chk_hide = _check(self, "Ocultar la imagen original", "La imagen se oculta (no se borra) tras vectorizar")
	_chk_hide.button_pressed = true

	_btn_go = _button(self, "Vectorizar", "Convierte la imagen seleccionada en trazados Bézier")
	_btn_go.custom_minimum_size.y = 30
	_btn_go.pressed.connect(vectorize_selection)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	add_child(tools)
	_btn_bg = _button(tools, "Quitar fondo (IA)", "Quita el fondo de la imagen seleccionada")
	_btn_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_bg.pressed.connect(func() -> void: process_image("bg"))
	_btn_up = _button(tools, "Mejorar ×4 (IA)", "Aumenta la resolución ×4 de la imagen seleccionada")
	_btn_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_up.pressed.connect(func() -> void: process_image("up"))
	_apply_preset(PRESETS.keys()[0])

func _ready() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(func(_p) -> void: _refresh_target())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: restyle())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_refresh_target())
	restyle()
	_refresh_target()

# ── selección ────────────────────────────────────────────────────────────────
func _image_sprite() -> Sprite2D:
	var ic := get_node_or_null("/root/InspectorCore")
	var sel: Array = ic.selection() if ic and ic.has_method("selection") else []
	for s in sel:
		if s is Sprite2D and (s as Sprite2D).texture:
			return s
	return null

func _refresh_target() -> void:
	if _busy:
		return
	var sp := _image_sprite()
	var native := ClassDB.class_exists("VectorizerJob")
	_preview.texture = sp.texture if sp else null
	for b in [_btn_go, _btn_bg, _btn_up]:
		b.disabled = sp == null or not native
	if not native:
		_set_status("El vectorizador nativo no está cargado (vectopen_vectorizer.gdextension).", true)
	elif sp == null:
		_set_status("Selecciona una imagen del lienzo.", false)
	else:
		var sz := sp.texture.get_size()
		_set_status("%s · %d × %d px" % [sp.name, int(sz.x), int(sz.y)], false)

func _apply_preset(name: String) -> void:
	var p: Dictionary = PRESETS.get(name, {})
	_sl_detail.value = float(p.get("filter_speckle", 4))
	_sl_colors.value = float(p.get("color_precision", 6))
	_sl_corners.value = float(p.get("corner_threshold", 60))
	_chk_bw.button_pressed = String(p.get("color_mode", "color")) == "binary"
	_opt_mode.select({"spline": 0, "polygon": 1, "pixel": 2}.get(String(p.get("mode", "spline")), 0))

## Opciones de vtracer (ImageVectorizer.vectorize_ex) según la interfaz.
func options() -> Dictionary:
	var preset: Dictionary = PRESETS.get(_opt_preset.get_item_text(_opt_preset.selected), {})
	return {
		"color_mode": "binary" if _chk_bw.button_pressed else "color",
		"mode": ["spline", "polygon", "pixel"][_opt_mode.selected],
		"filter_speckle": int(_sl_detail.value),
		"color_precision": int(_sl_colors.value),
		"corner_threshold": int(_sl_corners.value),
		"layer_difference": int(preset.get("layer_difference", 16)),
		"hierarchical": "stacked",
		"path_precision": 3,
	}

# ── vectorizar ───────────────────────────────────────────────────────────────
## Vectoriza la imagen seleccionada. Devuelve el grupo creado (o null).
func vectorize_selection() -> Node2D:
	var sp := _image_sprite()
	if sp == null or _busy:
		return null
	var src := _tmp_path("in.png")
	var img := sp.texture.get_image()
	if img == null:
		_set_status("No se pudo leer la imagen.", true)
		return null
	if img.is_compressed():
		img.decompress()
	img.save_png(src)
	var job := {"src": src, "bg": _chk_bg.button_pressed, "up": _chk_up.button_pressed,
		"opts": options(), "svg": _tmp_path("out.svg")}
	_set_busy(true, "Vectorizando…")
	var res: Dictionary = await _run_job(job)
	_set_busy(false, "")
	if String(res.get("error", "")) != "":
		_set_status("Error: " + String(res["error"]), true)
		return null
	var svg := FileAccess.get_file_as_string(String(res["svg"]))
	_cleanup([src, String(res["svg"]), String(res.get("mid", ""))])
	if not is_instance_valid(sp):
		return null
	var group := build_group(sp, svg, 0.25 if bool(job["up"]) else 1.0)
	if group == null:
		_set_status("La imagen no produjo trazados (¿vacía o transparente?).", true)
		return null
	_commit_group(sp, group, _chk_hide.button_pressed)
	_set_status("✓ %d trazados Bézier creados" % group.get_child_count(), false)
	return group

## Paso nativo en SEGUNDO PLANO: VectorizerJob lanza un hilo de Rust
## ([quitar fondo] → [×4] → vtracer); aquí solo se espera frame a frame (la
## app sigue respondiendo). GDScript no puede llamar a la extensión desde un
## hilo propio: godot-rust lo prohíbe.
func _run_job(job: Dictionary) -> Dictionary:
	var j = ClassDB.instantiate("VectorizerJob")
	j.start_vectorize(ProjectSettings.globalize_path(String(job["src"])),
		ProjectSettings.globalize_path(String(job["svg"])), job["opts"],
		bool(job.get("bg", false)), bool(job.get("up", false)),
		ProjectSettings.globalize_path("user://"))
	while not j.is_done():
		await get_tree().process_frame
	return {"svg": job["svg"], "error": j.get_error()}

## Crea el grupo de trazados sobre `sp`. `px_scale` = unidades de imagen por
## píxel del SVG (0.25 si se vectorizó la versión ×4).
static func build_group(sp: Sprite2D, svg: String, px_scale: float = 1.0) -> Node2D:
	var group := Node2D.new()
	group.name = NameUtils.unique_child_name(sp.get_parent(), "Vectorizado") if sp.get_parent() else "Vectorizado"
	group.set_meta("shape_type", "group")
	var paths: Array = SvgImportService.build_from_svg(svg, group)
	if paths.is_empty():
		group.free()
		return null
	# Esquina superior izquierda de la imagen en el espacio del Sprite2D.
	var tex_size := sp.texture.get_size()
	if sp.region_enabled:
		tex_size = sp.region_rect.size
	var tl := sp.offset - (tex_size * 0.5 if sp.centered else Vector2.ZERO)
	group.transform = sp.transform * Transform2D(0.0, Vector2(px_scale, px_scale), 0.0, tl)
	for p in paths:
		# Relleno sin trazo (como la imagen original).
		if "stroke_width" in p:
			p.set("stroke_width", 0.0)
	return group

func _commit_group(sp: Sprite2D, group: Node2D, hide_original: bool) -> void:
	var parent := sp.get_parent()
	var idx := sp.get_index() + 1
	var was_visible := sp.visible
	var do_fn := func() -> void:
		if is_instance_valid(group) and group.get_parent() == null and is_instance_valid(parent):
			parent.add_child(group)
			parent.move_child(group, mini(idx, parent.get_child_count() - 1))
		if hide_original and is_instance_valid(sp):
			sp.visible = false
	var undo_fn := func() -> void:
		if is_instance_valid(group) and group.get_parent():
			group.get_parent().remove_child(group)
		if is_instance_valid(sp):
			sp.visible = was_visible
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Vectorizar imagen")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
	var sm := get_node_or_null("/root/SelectionManager")
	if sm and sm.has_method("set_selection"):
		sm.set_selection([group])

# ── quitar fondo / ×4 sobre la propia imagen ─────────────────────────────────
func process_image(kind: String) -> void:
	var sp := _image_sprite()
	if sp == null or _busy:
		return
	var src := _tmp_path("in.png")
	var img := sp.texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.save_png(src)
	var out := _tmp_path("res.png")
	_set_busy(true, "Quitando el fondo…" if kind == "bg" else "Mejorando ×4…")
	var j = ClassDB.instantiate("VectorizerJob")
	if kind == "bg":
		j.start_remove_background(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(out))
	else:
		j.start_upscale(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(out))
	while not j.is_done():
		await get_tree().process_frame
	_task_result = {"error": j.get_error()}
	_set_busy(false, "")
	if String(_task_result.get("error", "")) != "":
		_set_status("Error: " + String(_task_result["error"]), true)
		_cleanup([src, out])
		return
	var new_img := Image.load_from_file(ProjectSettings.globalize_path(out))
	_cleanup([src, out])
	if new_img == null or not is_instance_valid(sp):
		return
	var old_tex := sp.texture
	var new_tex := ImageTexture.create_from_image(new_img)
	var old_scale := sp.scale
	# ×4: la imagen ocupa lo mismo en el lienzo (escala ÷4).
	var new_scale := old_scale * (0.25 if kind == "up" else 1.0)
	var do_fn := func() -> void:
		if is_instance_valid(sp):
			sp.texture = new_tex
			sp.scale = new_scale
	var undo_fn := func() -> void:
		if is_instance_valid(sp):
			sp.texture = old_tex
			sp.scale = old_scale
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Quitar fondo" if kind == "bg" else "Mejorar imagen ×4")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
	_refresh_target()
	_set_status("✓ Fondo quitado" if kind == "bg" else "✓ Imagen mejorada ×4", false)

# ── utilidades ───────────────────────────────────────────────────────────────
static func _tmp_path(suffix: String) -> String:
	return "user://_vectorize_%d_%s" % [Time.get_ticks_usec(), suffix]

static func _cleanup(paths: Array) -> void:
	for p in paths:
		var s := String(p)
		if s == "":
			continue
		var abs := ProjectSettings.globalize_path(s) if s.begins_with("user://") else s
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)

func _set_busy(on: bool, msg: String) -> void:
	_busy = on
	for b in [_btn_go, _btn_bg, _btn_up]:
		b.disabled = on
	if on:
		_set_status(msg, false)

func _set_status(text: String, error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", FxUI.c("NEGATIVE") if error else FxUI.c("TEXT_SECONDARY"))

func _label(text: String, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.set_meta("title", title)
	_labels.append(l)
	return l

func _slider(parent: Control, lo: float, hi: float, v: float, tip: String) -> HSlider:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = v
	s.tooltip_text = tip
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var l := _label(str(int(v)))
	l.custom_minimum_size = Vector2(30, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)
	s.value_changed.connect(func(x: float) -> void: l.text = str(int(x)))
	return s

func _check(parent: Control, text: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 11)
	parent.add_child(c)
	return c

func _button(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 26)
	b.add_theme_font_size_override("font_size", 11)
	parent.add_child(b)
	return b

func restyle() -> void:
	for l in _labels:
		l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY") if bool(l.get_meta("title", false)) else FxUI.c("PANEL_TEXT"))
	for c in find_children("*", "CheckBox", true, false):
		ProUIStyle.style_check(c)
		c.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
		c.add_theme_font_size_override("font_size", 11)
	for o in [_opt_preset, _opt_mode]:
		ProUIStyle.style_option(o)
	for s in [_sl_detail, _sl_colors, _sl_corners]:
		ProUIStyle.style_slider(s)
	for b in find_children("*", "Button", true, false):
		if b is OptionButton or b is CheckBox:
			continue
		var main: bool = b == _btn_go
		if main:
			FxUI.style_primary_green(b)   # acción principal: verde, como Exportar
			continue
		b.add_theme_stylebox_override("normal", FxUI.flat(FxUI.c("ACCENT") if main else FxUI.c("INPUT_BG"), 4, FxUI.c("ACCENT") if main else FxUI.c("INPUT_BORDER"), 8, 0))
		b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("ACCENT_HOVER") if main and _has("ACCENT_HOVER") else FxUI.c("BUTTON_HOVER"), 4, FxUI.c("BORDER_STRONG"), 8, 0))
		b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 4, FxUI.c("ACCENT"), 8, 0))
		b.add_theme_stylebox_override("disabled", FxUI.flat(FxUI.c("INPUT_BG"), 4, FxUI.c("BORDER"), 8, 0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color.WHITE if main else FxUI.c("PANEL_TEXT"))
		b.add_theme_color_override("font_disabled_color", FxUI.c("TEXT_DISABLED"))

func _has(slot: String) -> bool:
	var tm := get_node_or_null("/root/ThemeManager")
	return tm != null and tm.Slot.has(slot)
