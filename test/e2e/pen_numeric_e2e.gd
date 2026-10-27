# =============================================================================
# PRUEBA DE INTERFAZ REAL: campos numéricos con LÁPIZ de tableta (eventos con
# posición absoluta y `relative` = 0, como OpenTabletDriver en modo artista).
# ProNumField, SpinBox nativo (PenScrub) y spin_box.tscn (SpinBoxValue):
#   · arrastrar en horizontal (derecha = más) y en vertical (arriba = más);
#   · el ratón NO se captura (con lápiz la captura hacía saltar el valor);
#   · un clic sin arrastrar entra a escribir.
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/pen_numeric_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

## Como un lápiz: solo posición absoluta (sin `relative`), con presión.
func pen_move(to: Vector2, down: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = Vector2.ZERO
	ev.pressure = 0.6 if down else 0.0
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

func pen_button(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.global_position = at
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

## Trazo de lápiz desde el centro de `c` desplazándose `delta`.
func pen_drag(c: Control, delta: Vector2) -> void:
	var a := c.get_global_rect().get_center()
	await pen_move(a, false)
	await pen_button(a, true)
	for i in range(1, 11):
		await pen_move(a + delta * (float(i) / 10.0), true)
	await pen_button(a + delta, false)
	await frames(2)

func pen_tap(c: Control) -> void:
	var a := c.get_global_rect().get_center()
	await pen_move(a, false)
	await pen_button(a, true)
	await pen_button(a, false)
	await frames(2)

func _run() -> void:
	Input.use_accumulated_input = false
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	await frames(5)
	var ui := VBoxContainer.new()
	ui.position = Vector2(200, 200)
	ui.custom_minimum_size = Vector2(260, 0)
	ui.add_theme_constant_override("separation", 40)
	root.add_child(ui)

	var pro := ProNumField.new("", "W", "Ancho")
	pro.min_value = 0.0
	pro.max_value = 1000.0
	pro.step = 1.0
	pro.value = 100.0
	ui.add_child(pro)
	var sb := SpinBox.new()
	sb.min_value = 0.0
	sb.max_value = 1000.0
	sb.step = 1.0
	sb.value = 100.0
	sb.custom_minimum_size = Vector2(160, 28)
	ui.add_child(sb)
	var sv = load("res://scenes/ui/spin_box.tscn").instantiate()
	sv.custom_minimum_size = Vector2(240, 28)
	ui.add_child(sv)
	sv.max_value = 1000.0
	sv.value = 100.0
	await frames(5)

	# ── ProNumField ────────────────────────────────────────────────────────
	await pen_drag(pro, Vector2(80, 0))
	check("ProNumField: lápiz a la derecha sube", pro.value > 120.0, "%.1f" % pro.value)
	check("ProNumField: el ratón no queda capturado", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var v1 := pro.value
	await pen_drag(pro, Vector2(0, -80))
	check("ProNumField: lápiz hacia arriba sube", pro.value > v1 + 20.0, "%.1f → %.1f" % [v1, pro.value])
	var v2 := pro.value
	await pen_drag(pro, Vector2(-60, 0))
	check("ProNumField: lápiz a la izquierda baja", pro.value < v2 - 15.0, "%.1f → %.1f" % [v2, pro.value])
	await pen_tap(pro)
	check("ProNumField: toque sin arrastrar entra a escribir", pro._edit.has_focus())
	pro._edit.release_focus()
	await frames(2)

	# ── SpinBox nativo (PenScrub) ──────────────────────────────────────────
	check("SpinBox: tiene el arrastre para lápiz", sb.has_meta(&"_pen_scrub"))
	var le := sb.get_line_edit()
	await pen_drag(le, Vector2(80, 0))
	check("SpinBox: lápiz a la derecha sube", sb.value > 120.0, "%.1f" % sb.value)
	var s1 := sb.value
	await pen_drag(le, Vector2(0, -80))
	check("SpinBox: lápiz hacia arriba sube", sb.value > s1 + 20.0, "%.1f → %.1f" % [s1, sb.value])
	await pen_tap(le)
	check("SpinBox: toque sin arrastrar entra a escribir", le.has_focus())
	le.release_focus()
	await frames(2)

	# ── spin_box.tscn (SpinBoxValue / ControlVertical) ────────────────────
	var bar: Control = sv.get_node("BoxContainer/ProgressBar")
	var w0: float = sv.get_value()
	await pen_drag(bar, Vector2(0, -60))
	check("spin_box.tscn: lápiz hacia arriba sube", sv.get_value() > w0 + 10.0, "%.1f → %.1f" % [w0, sv.get_value()])
	var w1: float = sv.get_value()
	await pen_drag(bar, Vector2(60, 0))
	check("spin_box.tscn: lápiz a la derecha sube", sv.get_value() > w1 + 10.0, "%.1f → %.1f" % [w1, sv.get_value()])

	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
