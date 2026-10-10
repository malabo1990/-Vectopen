@tool
extends VectorShape
class_name VectorModel3D

## VectorModel3D — Objeto 3D nativo para el lienzo 2D de Vectopen
## Renderiza modelos .glb / .gltf dentro de un SubViewport transparente bajo demanda (UPDATE_ONCE),
## permitiendo transformaciones 2D estándar y modo de edición 3D (rotación orbital y zoom de cámara).

@export var size: Vector2 = Vector2(160, 160):
	set(v):
		var nx = maxf(16.0, v.x)
		var ny = maxf(16.0, v.y)
		size = Vector2(nx, ny)
		if has_doc_extent():
			_doc_extent = DVec2.from_v2(size)
			_doc_extent_set = true
		_update_viewport_size()
		request_render_update()

var _is_loading: bool = false
var _cached_render_texture: ImageTexture = null
var is_interactive_rotating: bool = false
var is_interactive_zooming: bool = false
var _zoom_settle_token: int = 0
var _is_capturing: bool = false

@export var model_path: String = "":
	set(v):
		var changed := (model_path != v)
		model_path = v
		if is_inside_tree() and not model_path.is_empty() and changed and not _is_loading:
			load_model(model_path)

## Rotación del modelo en grados de Euler (X, Y, Z)
@export var model_rotation: Vector3 = Vector3.ZERO:
	set(v):
		model_rotation = v
		_apply_model_transform()
		request_render_update()

@export var camera_distance: float = 3.5:
	set(v):
		camera_distance = clampf(v, 0.2, 100.0)
		_apply_camera_transform()
		request_render_update()

@export var camera_fov: float = 45.0:
	set(v):
		camera_fov = clampf(v, 5.0, 120.0)
		if is_instance_valid(_camera):
			_camera.fov = camera_fov
		request_render_update()

@export var light_energy: float = 1.2:
	set(v):
		light_energy = maxf(0.0, v)
		if is_instance_valid(_light):
			_light.light_energy = light_energy
		request_render_update()

@export var light_rotation: Vector3 = Vector3(-35.0, 45.0, 0.0):
	set(v):
		light_rotation = v
		if is_instance_valid(_light):
			_light.rotation_degrees = light_rotation
		request_render_update()

var is_3d_editing: bool = false:
	set(v):
		is_3d_editing = v
		queue_redraw()

# Nodos del pipeline 3D interno
var _viewport: SubViewport = null
var _world_node: Node3D = null
var _camera: Camera3D = null
var _light: DirectionalLight3D = null
var _model_container: Node3D = null
var _fallback_mesh: MeshInstance3D = null
var _current_imported_scene: Node = null

# Dimensiones base del AABB normalizado
var _model_base_scale: float = 1.0

func _init() -> void:
	_register_doc_extent("size")
	_setup_3d_pipeline()

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw_capture):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw_capture)

func _ready() -> void:
	_update_viewport_size()
	if not model_path.is_empty() and not is_instance_valid(_current_imported_scene):
		load_model(model_path)
	elif not is_instance_valid(_current_imported_scene):
		_show_fallback_cube()
	_initial_display_kick()

func _initial_display_kick() -> void:
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	queue_redraw()
	call_deferred("_settle_initial_display")

func _settle_initial_display() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_interactive_rotating and not is_interactive_zooming:
		capture_high_quality()

func _setup_3d_pipeline() -> void:
	if is_instance_valid(_viewport):
		return

	_viewport = SubViewport.new()
	_viewport.name = "SubViewport3D"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_viewport.use_debanding = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(maxi(16, int(round(size.x))), maxi(16, int(round(size.y))))
	add_child(_viewport, false, INTERNAL_MODE_FRONT)

	_world_node = Node3D.new()
	_world_node.name = "World3D"
	_viewport.add_child(_world_node)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = camera_fov
	_camera.current = true
	_world_node.add_child(_camera)
	_apply_camera_transform()

	_light = DirectionalLight3D.new()
	_light.name = "DirectionalLight3D"
	_light.light_energy = light_energy
	_light.rotation_degrees = light_rotation
	_world_node.add_child(_light)

	# Luz ambiental sutil para que las partes ocultas no se vean completamente negras
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.4, 1.0)
	env.ambient_light_energy = 0.8
	var camera_env := WorldEnvironment.new()
	camera_env.environment = env
	_world_node.add_child(camera_env)

	_model_container = Node3D.new()
	_model_container.name = "ModelContainer"
	_world_node.add_child(_model_container)

	_create_fallback_mesh()

func _create_fallback_mesh() -> void:
	_fallback_mesh = MeshInstance3D.new()
	_fallback_mesh.name = "FallbackMesh"
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 1.5, 1.5)
	_fallback_mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.52, 0.92, 1.0)
	mat.roughness = 0.4
	mat.metallic = 0.1
	_fallback_mesh.material_override = mat

	_model_container.add_child(_fallback_mesh)

func _show_fallback_cube() -> void:
	if is_instance_valid(_fallback_mesh):
		_fallback_mesh.visible = true
	if is_instance_valid(_current_imported_scene):
		_current_imported_scene.visible = false

var _resize_settle_token: int = 0

func _update_viewport_size() -> void:
	if not is_instance_valid(_viewport):
		return
	var target_w = maxi(16, int(round(size.x)))
	var target_h = maxi(16, int(round(size.y)))
	if _viewport.size != Vector2i(target_w, target_h):
		_viewport.size = Vector2i(target_w, target_h)
		# NOTE: NO anular _cached_render_texture aquí para evitar parpadeos negros al escalar con BoundingBox
		if is_inside_tree():
			_schedule_resize_settle()

func _schedule_resize_settle() -> void:
	_resize_settle_token += 1
	var token := _resize_settle_token
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	queue_redraw()
	if not is_inside_tree():
		return
	get_tree().create_timer(0.15).timeout.connect(func():
		if token == _resize_settle_token and not is_interactive_rotating and not is_interactive_zooming:
			capture_high_quality()
	)

func _apply_camera_transform() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.position = Vector3(0.0, 0.0, camera_distance)
	_camera.rotation = Vector3.ZERO

func _apply_model_transform() -> void:
	if not is_instance_valid(_model_container):
		return
	_model_container.rotation_degrees = model_rotation

## Carga un modelo 3D GLB o GLTF usando GLTFDocument
func load_model(path: String) -> bool:
	if _is_loading:
		return false
	_is_loading = true
	model_path = path

	if not FileAccess.file_exists(path):
		_show_fallback_cube()
		request_render_update()
		_is_loading = false
		return false

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("VectorModel3D: Fallo al parsear archivo GLTF/GLB: %s (error %d)" % [path, err])
		_show_fallback_cube()
		request_render_update()
		_is_loading = false
		return false

	var new_scene = doc.generate_scene(state)
	if not is_instance_valid(new_scene):
		push_warning("VectorModel3D: No se pudo generar la escena 3D para: %s" % path)
		_show_fallback_cube()
		request_render_update()
		_is_loading = false
		return false

	if is_instance_valid(_current_imported_scene):
		_current_imported_scene.queue_free()
		_current_imported_scene = null

	if is_instance_valid(_fallback_mesh):
		_fallback_mesh.visible = false

	_current_imported_scene = new_scene
	_model_container.add_child(_current_imported_scene)

	normalize_and_center_model()
	_apply_model_transform()
	if is_inside_tree():
		request_render_update()
	else:
		if is_instance_valid(_viewport):
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_is_loading = false
	return true

## Calcula el AABB global acumulado y centra/escala el modelo
func normalize_and_center_model() -> void:
	if not is_instance_valid(_current_imported_scene):
		return

	var aabb := _calculate_accumulated_aabb(_current_imported_scene)
	if aabb.size.length_squared() <= 0.0001:
		aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

	var center := aabb.get_center()
	var max_dim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if is_zero_approx(max_dim):
		max_dim = 1.0

	# Normalizar para que quepa en una esfera/caja de ~2.2 unidades de diámetro
	var target_dim := 2.2
	_model_base_scale = target_dim / max_dim

	# Desplazar la escena interna para que su centro geométrico coincida con el origen (0, 0, 0)
	_current_imported_scene.position = -center * _model_base_scale
	_current_imported_scene.scale = Vector3.ONE * _model_base_scale

func _calculate_accumulated_aabb(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var total_aabb := AABB()
	var first := true

	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh_aabb: AABB = (node as MeshInstance3D).mesh.get_aabb()
		var global_mesh_aabb := _transform_aabb(mesh_aabb, current_transform)
		total_aabb = global_mesh_aabb
		first = false

	for child in node.get_children():
		var child_aabb := _calculate_accumulated_aabb(child, current_transform)
		if child_aabb.size.length_squared() > 0.0:
			if first:
				total_aabb = child_aabb
				first = false
			else:
				total_aabb = total_aabb.merge(child_aabb)

	return total_aabb

func _transform_aabb(box: AABB, xform: Transform3D) -> AABB:
	var corners := [
		xform * box.position,
		xform * Vector3(box.position.x + box.size.x, box.position.y, box.position.z),
		xform * Vector3(box.position.x, box.position.y + box.size.y, box.position.z),
		xform * Vector3(box.position.x, box.position.y, box.position.z + box.size.z),
		xform * Vector3(box.position.x + box.size.x, box.position.y + box.size.y, box.position.z),
		xform * Vector3(box.position.x + box.size.x, box.position.y, box.position.z + box.size.z),
		xform * Vector3(box.position.x, box.position.y + box.size.y, box.position.z + box.size.z),
		xform * (box.position + box.size)
	]
	var min_p: Vector3 = corners[0]
	var max_p: Vector3 = corners[0]
	for c in corners:
		min_p.x = minf(min_p.x, c.x); min_p.y = minf(min_p.y, c.y); min_p.z = minf(min_p.z, c.z)
		max_p.x = maxf(max_p.x, c.x); max_p.y = maxf(max_p.y, c.y); max_p.z = maxf(max_p.z, c.z)
	return AABB(min_p, max_p - min_p)

## Métodos de interacción 3D
func begin_interactive_orbit() -> void:
	is_interactive_rotating = true
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = Viewport.MSAA_DISABLED
		_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_viewport.use_debanding = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	queue_redraw()

func end_interactive_orbit() -> void:
	is_interactive_rotating = false
	capture_high_quality()

func capture_high_quality() -> void:
	if not is_instance_valid(_viewport):
		return
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_viewport.use_debanding = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_is_capturing = true
	if not RenderingServer.frame_post_draw.is_connected(_on_post_draw_capture):
		RenderingServer.frame_post_draw.connect(_on_post_draw_capture, CONNECT_ONE_SHOT)
	call_deferred("_fallback_capture")
	queue_redraw()

func _on_post_draw_capture() -> void:
	_do_capture()

func _fallback_capture() -> void:
	if _is_capturing:
		_do_capture()

func _do_capture() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw_capture):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw_capture)
	if not is_instance_valid(_viewport) or not is_inside_tree():
		_is_capturing = false
		return
	var tex := _viewport.get_texture()
	if tex:
		var img := tex.get_image()
		if img and not img.is_empty():
			_cached_render_texture = ImageTexture.create_from_image(img)
	if not is_interactive_rotating and not is_interactive_zooming and is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_is_capturing = false
	queue_redraw()

func rotate_orbit(delta_x: float, delta_y: float) -> void:
	var sens := 0.6
	# Estilo Sketchfab (turntable): arrastrar hacia la derecha gira el modelo a la derecha,
	# arrastrar hacia la izquierda gira el modelo a la izquierda;
	# arrastrar hacia arriba inclina la vista para ver la parte superior del modelo.
	model_rotation.y += delta_x * sens
	model_rotation.x -= delta_y * sens
	# Mantener rotaciones dentro de rango -180..180 y limitar cabeceo para evitar gimbal lock
	model_rotation.y = wrapf(model_rotation.y, -180.0, 180.0)
	model_rotation.x = clampf(model_rotation.x, -89.0, 89.0)
	_apply_model_transform()
	request_render_update()

func zoom_camera(delta: float) -> void:
	camera_distance = clampf(camera_distance - delta * 0.25, 0.8, 25.0)
	_apply_camera_transform()
	is_interactive_zooming = true
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	queue_redraw()
	_schedule_zoom_settle()

func _schedule_zoom_settle() -> void:
	_zoom_settle_token += 1
	var token := _zoom_settle_token
	if not is_inside_tree():
		return
	get_tree().create_timer(0.25).timeout.connect(func():
		if token == _zoom_settle_token and not is_interactive_rotating:
			is_interactive_zooming = false
			capture_high_quality()
	)

func reset_view() -> void:
	model_rotation = Vector3.ZERO
	camera_distance = 3.5
	camera_fov = 45.0
	_apply_model_transform()
	_apply_camera_transform()
	request_render_update()

func set_3d_editing(active: bool) -> void:
	is_3d_editing = active
	if not active:
		capture_high_quality()
	queue_redraw()

func request_render_update() -> void:
	if is_interactive_rotating or is_interactive_zooming:
		if is_instance_valid(_viewport):
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		queue_redraw()
	else:
		capture_high_quality()

func get_effect_points() -> PackedVector2Array:
	var rect := Rect2(-size * 0.5, size)
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])

func _draw() -> void:
	var rect := Rect2(-size * 0.5, size)
	var pts := get_effect_points()
	draw_effects_shadows(pts)

	if is_interactive_rotating or is_interactive_zooming:
		if is_instance_valid(_viewport):
			var tex: Texture2D = _viewport.get_texture()
			if tex:
				draw_texture_rect(tex, rect, false)
			elif _cached_render_texture:
				draw_texture_rect(_cached_render_texture, rect, false)
	elif _cached_render_texture:
		draw_texture_rect(_cached_render_texture, rect, false)
	elif is_instance_valid(_viewport):
		var tex: Texture2D = _viewport.get_texture()
		if tex:
			draw_texture_rect(tex, rect, false)

	if is_3d_editing:
		# Indicador visual de modo 3D activo (borde punteado / cian y etiqueta de modo)
		var accent := Color(0.15, 0.65, 1.0, 0.95)
		draw_rect(rect, accent, false, 2.0)
		var font := ThemeDB.fallback_font
		var banner_bg := Rect2(rect.position, Vector2(rect.size.x, 20.0))
		draw_rect(banner_bg, Color(0.08, 0.12, 0.18, 0.85), true)
		draw_string(font, rect.position + Vector2(6, 14), "3D EDIT (MMB/Drag: Orbit, Wheel: Zoom)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	draw_effects_overlays(pts)

func get_state() -> Dictionary:
	var s := super.get_state()
	s["size"] = size
	s["model_path"] = model_path
	s["model_rotation"] = model_rotation
	s["camera_distance"] = camera_distance
	s["camera_fov"] = camera_fov
	s["light_energy"] = light_energy
	s["light_rotation"] = light_rotation
	return s
