# =============================================================================
# PRUEBA DE INTERFAZ REAL del objeto 3D (con ventana, ratón y teclado
# simulados): navegación estilo Blender / Godot (orbitar, desplazar, zoom,
# vistas del teclado numérico, gizmo de ejes, encuadrar), girar la luz,
# esquemas de iluminación, sombras, y que todo se guarde en el proyecto.
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/model3d_ui_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0
var _mouse := Vector2.ZERO

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

## Por Input (no push_input): así Input.is_mouse_button_pressed / is_key_pressed
## ven el estado real, como con un ratón de verdad.
func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func move(to: Vector2, mask: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - _mouse
	ev.button_mask = mask
	_mouse = to
	_send(ev)
	await process_frame

func button(at: Vector2, pressed: bool, btn: int = MOUSE_BUTTON_LEFT, dbl: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.global_position = at
	ev.button_index = btn
	ev.pressed = pressed
	ev.double_click = dbl
	ev.button_mask = 0
	if pressed:
		ev.button_mask = {MOUSE_BUTTON_LEFT: MOUSE_BUTTON_MASK_LEFT, MOUSE_BUTTON_MIDDLE: MOUSE_BUTTON_MASK_MIDDLE}.get(btn, 0)
	_send(ev)
	await process_frame

func drag(from: Vector2, to: Vector2, btn: int = MOUSE_BUTTON_LEFT, steps: int = 8) -> void:
	await move(from)
	await button(from, true, btn)
	var mask: int = MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	for i in range(1, steps + 1):
		await move(from.lerp(to, float(i) / steps), mask)
	await button(to, false, btn)
	await frames(3)

func key(code: int, ctrl := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		_send(ev)
		await process_frame

## Mantiene pulsado un modificador durante `fn` (Input.is_key_pressed lo ve).
func with_mod(mod: int, fn: Callable) -> void:
	var ev := InputEventKey.new()
	ev.keycode = mod
	ev.physical_keycode = mod
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await fn.call()
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

## GLB de prueba: base, cubo, esfera y toro (exportado con GLTFDocument).
func make_glb(path: String) -> void:
	var root3 := Node3D.new()
	var mk := func(mesh: Mesh, pos: Vector3, col: Color) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = pos
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.45
		mi.material_override = m
		root3.add_child(mi)
		mi.owner = root3
	var base := BoxMesh.new()
	base.size = Vector3(3, 0.15, 2)
	mk.call(base, Vector3(0, -0.6, 0), Color(0.75, 0.75, 0.78))
	var cube := BoxMesh.new()
	cube.size = Vector3(0.8, 0.8, 0.8)
	mk.call(cube, Vector3(-0.9, -0.1, 0), Color(0.9, 0.3, 0.25))
	mk.call(SphereMesh.new(), Vector3(0.1, -0.05, 0.2), Color(0.25, 0.55, 0.95))
	var torus := TorusMesh.new()
	mk.call(torus, Vector3(1.0, -0.3, -0.2), Color(0.95, 0.75, 0.2))
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_scene(root3, st)
	doc.write_to_filesystem(st, path)
	root3.free()

func _run() -> void:
	Input.use_accumulated_input = false
	var dir := ProjectSettings.globalize_path("user://m3d_e2e")
	DirAccess.make_dir_recursive_absolute(dir)
	var glb := dir.path_join("escena.glb")
	make_glb(glb)
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(90)
	var api = root.get_node("PluginManager").api
	for c in api.shapes():
		c.get_parent().remove_child(c)
	var ab = api.artboard()
	var m := VectorModel3D.new()
	m.name = "Modelo"
	m.size = Vector2(420, 320)
	m.set_doc_position(DVec2.from_v2(ab.artboard_size / 2.0))
	api.add(m)
	m.model_path = glb
	await create_timer(0.6).timeout
	check("el GLB se carga", is_instance_valid(m._current_imported_scene))
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var to_screen := func(local: Vector2) -> Vector2: return canvas.get_viewport().get_canvas_transform() * m.to_global(local)
	var center: Vector2 = to_screen.call(Vector2.ZERO)

	# entrar en modo 3D con doble clic
	await move(center)
	await button(center, true)
	await button(center, false)
	await button(center, true, MOUSE_BUTTON_LEFT, true)
	await button(center, false)
	await frames(4)
	check("doble clic entra en modo 3D", m.is_3d_editing)

	# orbitar con arrastre: gira la CÁMARA (el modelo no se mueve)
	var yaw0: float = m.view_yaw
	var rot0: Vector3 = m.model_rotation
	await drag(center, center + Vector2(120, 0))
	check("arrastrar orbita la cámara", absf(m.view_yaw - yaw0) > 20.0 and m.model_rotation == rot0, "yaw %.1f → %.1f" % [yaw0, m.view_yaw])
	var pitch0: float = m.view_pitch
	await drag(center, center + Vector2(0, -80))
	check("arrastrar arriba/abajo cambia la altura de la vista", absf(m.view_pitch - pitch0) > 15.0, "pitch %.1f" % m.view_pitch)

	# botón central también orbita
	yaw0 = m.view_yaw
	await drag(center, center + Vector2(-80, 0), MOUSE_BUTTON_MIDDLE)
	check("botón central orbita", absf(m.view_yaw - yaw0) > 15.0)

	# Mayús + arrastrar desplaza
	var t0: Vector3 = m.view_target
	await with_mod(KEY_SHIFT, func() -> void: await drag(center, center + Vector2(60, 30)))
	check("Mayús + arrastrar desplaza la vista", m.view_target.distance_to(t0) > 0.05, str(m.view_target))

	# Ctrl + arrastrar y rueda: zoom
	var d0: float = m.camera_distance
	await with_mod(KEY_CTRL, func() -> void: await drag(center, center + Vector2(0, -60)))
	check("Ctrl + arrastrar hace zoom", m.camera_distance < d0, "%.2f → %.2f" % [d0, m.camera_distance])
	d0 = m.camera_distance
	await button(center, true, MOUSE_BUTTON_WHEEL_DOWN)
	await button(center, false, MOUSE_BUTTON_WHEEL_DOWN)
	await frames(2)
	check("rueda aleja", m.camera_distance > d0)

	# Alt + arrastrar gira la luz
	var lr0: Vector3 = m.light_rotation
	await with_mod(KEY_ALT, func() -> void: await drag(center, center + Vector2(90, 20)))
	check("Alt + arrastrar gira la luz", m.light_rotation.distance_to(lr0) > 10.0, str(m.light_rotation))

	# teclado numérico
	await key(KEY_KP_7)
	check("7: vista desde arriba", m.view_pitch > 89.0)
	await key(KEY_KP_1)
	check("1: vista de frente", absf(m.view_yaw) < 0.01 and absf(m.view_pitch) < 0.01)
	await key(KEY_KP_1, true)
	check("Ctrl+1: vista de atrás", absf(absf(m.view_yaw) - 180.0) < 0.01)
	await key(KEY_KP_3)
	check("3: vista derecha", absf(m.view_yaw - 90.0) < 0.01)
	await key(KEY_KP_5)
	check("5: ortográfica", m.camera_ortho and m._camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	await key(KEY_KP_5)
	check("5 otra vez: perspectiva", not m.camera_ortho)
	await key(KEY_F)
	check("F encuadra (centro y distancia)", m.view_target == Vector3.ZERO and m.camera_distance < 4.5)

	# clic en el gizmo de ejes → vista
	await key(KEY_KP_9)
	await frames(3)
	var y_axis: Array = m._gizmo_axes().filter(func(a) -> bool: return a[2] == "Y")
	check("hay gizmo de ejes", not y_axis.is_empty())
	if not y_axis.is_empty():
		var p: Vector2 = to_screen.call(y_axis[0][0])
		await move(p)
		await button(p, true)
		await button(p, false)
		await frames(3)
		check("clic en el eje Y del gizmo → vista desde arriba", m.view_pitch > 89.0, "pitch %.1f" % m.view_pitch)

	# iluminación desde el Inspector (o InspectorCore)
	var ic = root.get_node("InspectorCore")
	api.select([m])
	ic._sync_selection()
	ic.apply("light_preset", "Dramático")
	check("esquema Dramático: contraluz fuerte y ambiente bajo", m._rim_light.light_energy > 1.0 and m._env.ambient_light_energy < 0.2)
	ic.apply("model_shadows", false)
	check("sombras desactivables", not m._light.shadow_enabled)
	ic.apply("model_shadows", true)
	root.get_node("HistoryManager").undo()
	check("Ctrl+Z deshace el cambio de sombras", not m.model_shadows)
	ic.apply("light_color", Color(1, 0.5, 0.2))
	check("color de la luz principal", m._light.light_color.g < 0.7)

	# capturas de los esquemas de luz (para revisar a ojo)
	await key(KEY_KP_9)
	m.frame_model()
	var img_names := []
	for preset in ["Estudio", "Exterior", "Dramático", "Plano"]:
		ic.apply("light_preset", preset)
		ic.apply("model_shadows", true)
		ic.apply("light_color", Color.WHITE)
		await create_timer(1.0).timeout
		var r: Rect2 = Rect2(to_screen.call(-m.size / 2.0), m.size * canvas.get_viewport().get_canvas_transform().get_scale())
		root.get_texture().get_image().get_region(Rect2i(r)).save_png("user://m3d_%s.png" % preset)
		img_names.append(preset)

	# se guarda con el proyecto
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	m.view_yaw = 33.0
	m.view_pitch = 21.0
	m.camera_ortho = true
	var d: Dictionary = Ser._serialize_element(m)
	var m2 = Ser._element_from(JSON.parse_string(JSON.stringify(d)))
	check("vista e iluminación se guardan en el proyecto",
		absf(m2.view_yaw - 33.0) < 0.01 and absf(m2.view_pitch - 21.0) < 0.01 and m2.camera_ortho and m2.light_preset == "Plano",
		"%s %s %s %s" % [m2.view_yaw, m2.view_pitch, m2.camera_ortho, m2.light_preset])
	m2.free()

	# Esc sale del modo 3D
	await key(KEY_ESCAPE)
	check("Esc sale del modo 3D", not m.is_3d_editing)
	root.get_node("PluginManager")._remove_dir(dir)
	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
