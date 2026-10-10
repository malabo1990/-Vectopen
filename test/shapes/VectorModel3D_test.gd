extends GdUnitTestSuite

const VectorModel3DScript = preload("res://script_gdscript/shapes/VectorModel3D.gd")
const MoveToolScript = preload("res://script_gdscript/tools/MoveTool.gd")

func test_default_properties() -> void:
	var m: Node2D = auto_free(VectorModel3DScript.new())
	add_child(m)

	assert_vector(m.size).is_equal(Vector2(160, 160))
	assert_str(m.model_path).is_equal("")
	assert_vector(m.model_rotation).is_equal(Vector3.ZERO)
	assert_float(m.camera_distance).is_equal_approx(3.5, 0.001)
	assert_float(m.camera_fov).is_equal_approx(45.0, 0.001)
	assert_float(m.light_energy).is_equal_approx(1.2, 0.001)
	assert_bool(m.is_3d_editing).is_false()

func test_orbit_rotation() -> void:
	var m: Node2D = auto_free(VectorModel3DScript.new())
	add_child(m)

	m.rotate_orbit(10.0, 5.0)
	assert_float(m.model_rotation.y).is_not_equal(0.0)
	assert_float(m.model_rotation.x).is_not_equal(0.0)

	m.reset_view()
	assert_vector(m.model_rotation).is_equal(Vector3.ZERO)
	assert_float(m.camera_distance).is_equal_approx(3.5, 0.001)

func test_camera_zoom() -> void:
	var m: Node2D = auto_free(VectorModel3DScript.new())
	add_child(m)

	var orig_dist: float = m.camera_distance
	m.zoom_camera(2.0)
	assert_float(m.camera_distance).is_less(orig_dist)

func test_state_serialization() -> void:
	var m: Node2D = auto_free(VectorModel3DScript.new())
	add_child(m)

	m.size = Vector2(200, 250)
	m.model_rotation = Vector3(15, 30, 0)
	m.camera_distance = 4.0

	var st: Dictionary = m.get_state()
	assert_dict(st).contains_keys(["size", "model_path", "model_rotation", "camera_distance", "camera_fov", "light_energy", "light_rotation"])
	assert_vector(st["size"] as Vector2).is_equal(Vector2(200, 250))
	assert_vector(st["model_rotation"] as Vector3).is_equal(Vector3(15, 30, 0))
	assert_float(st["camera_distance"] as float).is_equal_approx(4.0, 0.001)

func test_movetool_3d_mode_entry_and_escape() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var container: Node2D = auto_free(Node2D.new())
	container.name = "ArtboardsContainer"
	root.add_child(container)

	var m: Node2D = auto_free(VectorModel3DScript.new())
	container.add_child(m)
	m.position = Vector2(100, 100)

	var mt: MoveTool = auto_free(MoveToolScript.new())
	root.add_child(mt)
	mt.canvas = root

	# Simular doble clic en el modelo
	var handled := mt._on_double_click(m.global_position)
	assert_bool(handled).is_true()
	assert_that(mt.active_3d_model).is_equal(m)
	assert_bool(m.is_3d_editing).is_true()

	# Simular Escape para salir
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_ESCAPE
	var esc_handled := mt.handle_input(key_event)
	assert_bool(esc_handled).is_true()
	assert_that(mt.active_3d_model).is_null()
	assert_bool(m.is_3d_editing).is_false()

func test_movetool_3d_wheel_zoom_and_outside_exit() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var container: Node2D = auto_free(Node2D.new())
	container.name = "ArtboardsContainer"
	root.add_child(container)

	var m: Node2D = auto_free(VectorModel3DScript.new())
	container.add_child(m)
	m.position = Vector2(200, 200)

	var mt: MoveTool = auto_free(MoveToolScript.new())
	root.add_child(mt)
	mt.canvas = root

	mt._enter_3d_mode(m)
	assert_that(mt.active_3d_model).is_equal(m)

	var orig_dist: float = m.camera_distance
	var wheel_event := InputEventMouseButton.new()
	wheel_event.pressed = true
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	var handled := mt.handle_input(wheel_event)
	assert_bool(handled).is_true()
	assert_float(m.camera_distance).is_less(orig_dist)

	# Clic fuera del modelo 3D (a 800, 800) sale del modo 3D
	var click_outside := InputEventMouseButton.new()
	click_outside.pressed = true
	click_outside.button_index = MOUSE_BUTTON_LEFT
	click_outside.position = Vector2(800, 800)
	mt.handle_input(click_outside)
	assert_that(mt.active_3d_model).is_null()
	assert_bool(m.is_3d_editing).is_false()

func test_canvas_serializer_roundtrip() -> void:
	var cs = preload("res://scripts/canvas/canvas_serializer.gd")
	var container: Node2D = auto_free(Node2D.new())
	var m: Node2D = VectorModel3DScript.new()
	m.name = "Test3D"
	m.size = Vector2(300, 240)
	m.model_rotation = Vector3(10, 20, 30)
	m.camera_distance = 5.0
	m.camera_fov = 60.0
	m.light_energy = 2.0
	m.light_rotation = Vector3(10, -45, 0)
	container.add_child(m)

	var data: Dictionary = cs.serialize_container(container)
	assert_dict(data).contains_keys(["artboards", "loose"])
	assert_int(data["loose"].size()).is_equal(1)
	var serialized: Dictionary = data["loose"][0]
	assert_str(serialized["kind"]).is_equal("3d")
	assert_str(serialized["name"]).is_equal("Test3D")

	var cont2: Node2D = auto_free(Node2D.new())
	cs.rebuild_container(cont2, data)
	assert_int(cont2.get_child_count()).is_equal(1)
	var loaded: Node2D = cont2.get_child(0)
	assert_str(loaded.name).is_equal("Test3D")
	assert_vector(loaded.size).is_equal(Vector2(300, 240))
	assert_vector(loaded.model_rotation).is_equal(Vector3(10, 20, 30))
	assert_float(loaded.camera_distance).is_equal_approx(5.0, 0.001)
	assert_float(loaded.camera_fov).is_equal_approx(60.0, 0.001)
	assert_float(loaded.light_energy).is_equal_approx(2.0, 0.001)
	assert_vector(loaded.light_rotation).is_equal(Vector3(10, -45, 0))

func test_blender_style_middle_mouse_orbit() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var container: Node2D = auto_free(Node2D.new())
	container.name = "ArtboardsContainer"
	root.add_child(container)

	var m: Node2D = auto_free(VectorModel3DScript.new())
	container.add_child(m)
	m.position = Vector2(100, 100)
	m.size = Vector2(160, 160)

	var mt: MoveTool = auto_free(MoveToolScript.new())
	root.add_child(mt)
	mt.canvas = root

	# 1. Clic medio (MMB) sobre el modelo 3D inicia rotación interactiva estilo Blender
	var mmb_press := InputEventMouseButton.new()
	mmb_press.pressed = true
	mmb_press.button_index = MOUSE_BUTTON_MIDDLE
	mmb_press.position = Vector2(100, 100)
	var handled_press := mt.handle_input(mmb_press)
	assert_bool(handled_press).is_true()
	assert_bool(mt.is_middle_dragging_3d).is_true()
	assert_bool(m.is_interactive_rotating).is_true()

	# 2. Arrastre de ratón con MMB rota el modelo
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120, 110)
	var handled_motion := mt.handle_input(motion)
	assert_bool(handled_motion).is_true()
	assert_float(m.model_rotation.y).is_not_equal(0.0)

	# 3. Soltar MMB concluye el gesto y congela el buffer en alta calidad
	var mmb_release := InputEventMouseButton.new()
	mmb_release.pressed = false
	mmb_release.button_index = MOUSE_BUTTON_MIDDLE
	mmb_release.position = Vector2(120, 110)
	var handled_release := mt.handle_input(mmb_release)
	assert_bool(handled_release).is_true()
	assert_bool(mt.is_middle_dragging_3d).is_false()
	assert_bool(m.is_interactive_rotating).is_false()

func test_high_quality_resting_buffer() -> void:
	var m: Node2D = auto_free(VectorModel3DScript.new())
	add_child(m)

	# Modo activo: UPDATE_ALWAYS y MSAA apagado para fluidez de interacción
	m.begin_interactive_orbit()
	assert_bool(m.is_interactive_rotating).is_true()
	assert_int(m._viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)
	assert_int(m._viewport.msaa_3d).is_equal(Viewport.MSAA_DISABLED)

	# Al terminar la interacción: se activa alta calidad (MSAA 4X, FXAA)
	m.end_interactive_orbit()
	assert_bool(m.is_interactive_rotating).is_false()
	assert_int(m._viewport.msaa_3d).is_equal(Viewport.MSAA_4X)
	assert_int(m._viewport.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_FXAA)
	assert_bool(m._viewport.use_debanding).is_true()

	# Al completar la captura: viewport desactivado (UPDATE_DISABLED) para rendimiento ultra rápido
	m._do_capture()
	assert_int(m._viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)

func test_bounding_box_fit_and_resize_for_3d_model() -> void:
	var BBoxScript = preload("res://scenes/canvas/bounding_box.gd")
	var bbox = auto_free(BBoxScript.new())
	add_child(bbox)

	var m: Node2D = auto_free(VectorModel3DScript.new())
	add_child(m)
	m.position = Vector2(300, 200)
	m.size = Vector2(250, 180)

	# Verificar que el bounding box calcula exactamente el rectángulo del modelo (250x180 centrado en 300, 200)
	var r: Rect2 = bbox._global_rect_cloned(m)
	assert_vector(r.size).is_equal(Vector2(250, 180))
	assert_vector(r.position).is_equal(Vector2(175, 110))

	# Comprobar redimensionado y sincronización de doc_extent
	m.size = Vector2(400, 300)
	assert_vector(m.size).is_equal(Vector2(400, 300))
	assert_vector(m.get_doc_extent().to_v2()).is_equal(Vector2(400, 300))

func test_sketchfab_rotation_directions() -> void:
	var m: Node2D = auto_free(VectorModel3DScript.new())
	add_child(m)

	# Arrastre hacia la derecha (delta_x > 0) -> rotación Y aumenta (el modelo gira a la derecha como en Sketchfab)
	m.rotate_orbit(10.0, 0.0)
	assert_float(m.model_rotation.y).is_greater(0.0)

	m.reset_view()

	# Arrastre hacia arriba (delta_y < 0 en pantalla) -> rotación X aumenta (el modelo cabecea hacia el usuario para ver la parte superior)
	m.rotate_orbit(0.0, -10.0)
	assert_float(m.model_rotation.x).is_greater(0.0)

func test_zoom_deactivates_canvas_zoom_when_over_3d() -> void:
	var CanvasScript = preload("res://scripts/canvas/canvas.gd")
	var root = auto_free(CanvasScript.new())
	add_child(root)
	var container: Node2D = auto_free(Node2D.new())
	container.name = "ArtboardsContainer"
	root.add_child(container)

	var m: Node2D = auto_free(VectorModel3DScript.new())
	container.add_child(m)
	m.position = Vector2(200, 200)
	m.size = Vector2(160, 160)

	var mt: MoveTool = auto_free(MoveToolScript.new())
	root.add_child(mt)
	mt.canvas = root
	root.current_tool = mt

	var wheel_event := InputEventMouseButton.new()
	wheel_event.pressed = true
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP

	# 1. Cursor sobre el modelo 3D: handle_wheel_3d debe retornar TRUE (consume el evento y desactiva el zoom del editor)
	var handled_over_3d := mt.handle_wheel_3d(wheel_event, Vector2(200, 200))
	assert_bool(handled_over_3d).is_true()
	assert_bool(root.is_canvas_zoom_paused(Vector2(200, 200))).is_true()

	# 1.1 Liberación de la rueda sobre 3D también debe ser consumida
	var wheel_release := InputEventMouseButton.new()
	wheel_release.pressed = false
	wheel_release.button_index = MOUSE_BUTTON_WHEEL_UP
	var handled_rel := mt.handle_wheel_3d(wheel_release, Vector2(200, 200))
	assert_bool(handled_rel).is_true()

	# 2. Modo de edición 3D activo pausa explícitamente el zoom del canvas
	mt._enter_3d_mode(m)
	assert_bool(root.is_canvas_zoom_paused()).is_true()

	mt._exit_3d_mode()
	# 3. Cursor fuera del modelo 3D (espacio vacío): handle_wheel_3d debe retornar FALSE (permite que el editor haga su zoom normal)
	var handled_outside := mt.handle_wheel_3d(wheel_event, Vector2(800, 800))
	assert_bool(handled_outside).is_false()
	assert_bool(root.is_canvas_zoom_paused()).is_false()




