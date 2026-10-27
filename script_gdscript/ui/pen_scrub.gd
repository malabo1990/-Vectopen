# =============================================================================
# VECTOPEN — ARRASTRE NUMÉRICO PARA LÁPIZ EN LOS SpinBox NATIVOS
# RUTA: res://script_gdscript/ui/pen_scrub.gd
# Como spin_box.tscn / ProNumField: arrastrar sobre el número cambia el valor
# en horizontal (derecha = más) o en vertical (arriba = más), según hacia dónde
# se mueva primero (Shift ×0.1, Ctrl ×10). Se mide con la posición ABSOLUTA,
# sin capturar el ratón, así va fluido con un lápiz de tableta. Un clic sin
# arrastrar entra a escribir (selecciona todo); con el texto ya en edición,
# el ratón vuelve a ser el de un campo de texto normal.
# VectopenInput lo engancha a cada SpinBox que entra en el árbol.
# =============================================================================
extends RefCounted

const META := &"_pen_scrub"

static func attach(sb: SpinBox) -> void:
	if not is_instance_valid(sb) or sb.has_meta(META):
		return
	var le := sb.get_line_edit()
	if le == null:
		return
	sb.set_meta(META, true)
	# Sin foco al pulsar (si no, Godot lo daría antes del arrastre y el campo
	# pasaría a modo texto): solo un toque sin arrastrar entra a escribir.
	var st := {"active": false, "moved": false, "axis": -1, "start": Vector2.ZERO, "v0": 0.0,
		"editing": false, "focus_mode": le.focus_mode}
	_scrub_mode(le, st)
	le.gui_input.connect(func(ev: InputEvent) -> void: _on_input(sb, le, st, ev))
	le.focus_exited.connect(func() -> void: _scrub_mode(le, st))

static func _scrub_mode(le: LineEdit, st: Dictionary) -> void:
	st["editing"] = false
	le.focus_mode = Control.FOCUS_NONE
	le.mouse_default_cursor_shape = Control.CURSOR_HSIZE

static func _on_input(sb: SpinBox, le: LineEdit, st: Dictionary, ev: InputEvent) -> void:
	if not sb.editable or st["editing"]:
		return   # escribiendo: selección de texto normal
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			st["active"] = true
			st["moved"] = false
			st["axis"] = -1
			st["start"] = ev.global_position
			st["v0"] = sb.value
		elif st["active"]:
			st["active"] = false
			if not st["moved"]:
				st["editing"] = true
				le.focus_mode = st["focus_mode"]
				le.mouse_default_cursor_shape = Control.CURSOR_IBEAM
				le.grab_focus()
				le.select_all()
		le.accept_event()
	elif ev is InputEventMouseMotion and st["active"]:
		var d: Vector2 = ev.global_position - (st["start"] as Vector2)
		if not st["moved"]:
			if d.length() < 3.0:
				return
			st["moved"] = true
			st["axis"] = 0 if absf(d.x) >= absf(d.y) else 1
		var acc: float = d.x if int(st["axis"]) == 0 else -d.y
		var mul := 1.0
		if Input.is_key_pressed(KEY_SHIFT):
			mul = 0.1
		elif Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
			mul = 10.0
		var stp := sb.step if sb.step > 0.0 else 1.0
		sb.value = float(st["v0"]) + roundf(acc / 2.0) * stp * mul
		le.accept_event()
