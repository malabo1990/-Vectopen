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
		_apply_camera_transform()
		request_render_update()

@export var light_energy: float = 1.2:
	set(v):
		light_energy = maxf(0.0, v)
		_apply_lighting()
		request_render_update()

@export var light_rotation: Vector3 = Vector3(-35.0, 45.0, 0.0):
	set(v):
		light_rotation = v
		_apply_lighting()
		request_render_update()

# ── Vista (cámara orbital estilo Blender / Godot) ──────────────────────────
## Ángulos de la cámara alrededor del punto de interés, en grados.
@export var view_yaw: float = 0.0:
	set(v):
		view_yaw = wrapf(v, -180.0, 180.0)
		_apply_camera_transform()
		request_render_update()
@export var view_pitch: float = 0.0:
	set(v):
		view_pitch = clampf(v, -89.5, 89.5)
		_apply_camera_transform()
		request_render_update()
## Punto al que mira la cámara (desplazar con Mayús + arrastrar).
@export var view_target: Vector3 = Vector3.ZERO:
	set(v):
		view_target = v
		_apply_camera_transform()
		request_render_update()
## Proyección ortográfica (5 del teclado numérico, como Blender).
@export var camera_ortho: bool = false:
	set(v):
		camera_ortho = v
		_apply_camera_transform()
		request_render_update()

# ── Iluminación ─────────────────────────────────────────────────────────────
const LIGHT_PRESETS := {
	"Estudio": {"key": [1.35, Color(1.0, 0.97, 0.92), Vector3(-40, 35, 0)], "fill": [0.45, Color(0.85, 0.9, 1.0), Vector3(-15, -60, 0)],
		"rim": [0.8, Color(1, 1, 1), Vector3(-10, 175, 0)], "ambient": 0.35, "sky_top": Color(0.62, 0.66, 0.72), "sky_horizon": Color(0.8, 0.8, 0.82), "ground": Color(0.25, 0.24, 0.23)},
	"Exterior": {"key": [2.0, Color(1.0, 0.95, 0.85), Vector3(-55, 30, 0)], "fill": [0.0, Color.WHITE, Vector3.ZERO],
		"rim": [0.0, Color.WHITE, Vector3.ZERO], "ambient": 0.75, "sky_top": Color(0.35, 0.55, 0.9), "sky_horizon": Color(0.75, 0.82, 0.92), "ground": Color(0.3, 0.27, 0.22)},
	"Suave": {"key": [0.9, Color(1, 1, 1), Vector3(-50, 20, 0)], "fill": [0.6, Color(1, 1, 1), Vector3(-20, -70, 0)],
		"rim": [0.3, Color(1, 1, 1), Vector3(-10, 170, 0)], "ambient": 0.8, "sky_top": Color(0.8, 0.8, 0.82), "sky_horizon": Color(0.85, 0.85, 0.86), "ground": Color(0.5, 0.5, 0.5)},
	"Dramático": {"key": [2.2, Color(1.0, 0.9, 0.78), Vector3(-20, 80, 0)], "fill": [0.05, Color(0.6, 0.7, 1.0), Vector3(-10, -80, 0)],
		"rim": [1.3, Color(0.55, 0.7, 1.0), Vector3(-5, -170, 0)], "ambient": 0.08, "sky_top": Color(0.1, 0.1, 0.14), "sky_horizon": Color(0.15, 0.15, 0.2), "ground": Color(0.05, 0.05, 0.05)},
	"Plano": {"key": [0.5, Color(1, 1, 1), Vector3(-30, 0, 0)], "fill": [0.0, Color.WHITE, Vector3.ZERO],
		"rim": [0.0, Color.WHITE, Vector3.ZERO], "ambient": 1.1, "sky_top": Color(1, 1, 1), "sky_horizon": Color(1, 1, 1), "ground": Color(0.9, 0.9, 0.9)},
}
## Esquema de luces (Estudio, Exterior, Suave, Dramático, Plano).
@export var light_preset: String = "Estudio":
	set(v):
		light_preset = v if LIGHT_PRESETS.has(v) else "Estudio"
		_apply_lighting()
		request_render_update()
@export var model_shadows: bool = true:
	set(v):
		model_shadows = v
		_apply_lighting()
		request_render_update()
@export var light_color: Color = Color(1, 1, 1):
	set(v):
		light_color = v
		_apply_lighting()
		request_render_update()
@export var ambient_energy: float = 1.0:
	set(v):
		ambient_energy = clampf(v, 0.0, 4.0)
		_apply_lighting()
		request_render_update()

var _fill_light: DirectionalLight3D = null
var _rim_light: DirectionalLight3D = null
var _env: Environment = null

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

	# Luces de relleno y contraluz (esquema de tres luces de estudio)
	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "FillLight"
	_world_node.add_child(_fill_light)
	_rim_light = DirectionalLight3D.new()
	_rim_light.name = "RimLight"
	_world_node.add_child(_rim_light)

	# Entorno: cielo procedural SOLO para la luz ambiental y los reflejos
	# (el fondo sigue transparente), tonemapping fílmico
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env.sky = sky
	# ambiente por COLOR (instantáneo); el cielo solo para reflejos: su luz
	# ambiental se calcula en varios fotogramas y llegaba tarde a la imagen
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	var camera_env := WorldEnvironment.new()
	camera_env.environment = _env
	_world_node.add_child(camera_env)
	_apply_lighting()

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

## Cámara ORBITAL: gira alrededor de `view_target` a `camera_distance`
## (como Blender / el editor de Godot), en perspectiva u ortográfica.
func _apply_camera_transform() -> void:
	if not is_instance_valid(_camera):
		return
	var yaw := deg_to_rad(view_yaw)
	var pitch := deg_to_rad(view_pitch)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var pos := view_target + dir * camera_distance
	var up := Vector3.UP if absf(view_pitch) < 89.0 else Vector3(0, 0, -signf(view_pitch))
	# sin look_at(): funciona también antes de entrar en la escena (al cargar)
	_camera.transform = Transform3D(Basis.looking_at(view_target - pos, up), pos)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if camera_ortho else Camera3D.PROJECTION_PERSPECTIVE
	_camera.size = 2.0 * camera_distance * tan(deg_to_rad(camera_fov) * 0.5)
	_camera.near = 0.02
	_camera.far = 200.0

## Aplica el esquema de luces + color/intensidad/rotación de la luz principal.
func _apply_lighting() -> void:
	if not is_instance_valid(_light):
		return
	var pr: Dictionary = LIGHT_PRESETS.get(light_preset, LIGHT_PRESETS["Estudio"])
	_light.light_energy = float(pr["key"][0]) * light_energy / 1.2
	_light.light_color = (pr["key"][1] as Color) * light_color
	_light.rotation_degrees = light_rotation
	_light.shadow_enabled = model_shadows
	_light.shadow_blur = 1.5
	_light.directional_shadow_max_distance = 30.0
	for pair in [[_fill_light, "fill"], [_rim_light, "rim"]]:
		var l: DirectionalLight3D = pair[0]
		if is_instance_valid(l):
			var spec: Array = pr[pair[1]]
			l.light_energy = float(spec[0])
			l.light_color = spec[1]
			# las luces secundarias acompañan a la principal al girarla
			l.rotation_degrees = (spec[2] as Vector3) + Vector3(0, light_rotation.y - 45.0, 0)
			l.visible = float(spec[0]) > 0.0
			l.shadow_enabled = false
	if _env:
		var sm := _env.sky.sky_material as ProceduralSkyMaterial
		sm.sky_top_color = pr["sky_top"]
		sm.sky_horizon_color = pr["sky_horizon"]
		sm.ground_bottom_color = pr["ground"]
		sm.ground_horizon_color = pr["sky_horizon"]
		var top: Color = pr["sky_top"]
		_env.ambient_light_color = top.lerp(pr["sky_horizon"], 0.5).lerp(pr["ground"], 0.2)
		_env.ambient_light_energy = float(pr["ambient"]) * ambient_energy

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
	# Se renderiza de continuo y se copia la imagen tras DOS fotogramas
	# dibujados: con UPDATE_ONCE y copia en el primero, la copia salía con un
	# cambio de retraso (luz, sombras o vista anteriores).
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_is_capturing = true
	_capture_wait = 2
	if not RenderingServer.frame_post_draw.is_connected(_on_post_draw_capture):
		RenderingServer.frame_post_draw.connect(_on_post_draw_capture)
	# respaldo por si frame_post_draw no llega
	if is_inside_tree():
		get_tree().create_timer(0.5).timeout.connect(_fallback_capture)
	queue_redraw()

var _capture_wait := 0

func _on_post_draw_capture() -> void:
	_capture_wait -= 1
	if _capture_wait <= 0:
		_do_capture()

func _fallback_capture() -> void:
	if _is_capturing and _capture_wait <= 0:
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

## Orbitar la CÁMARA (arrastrar): derecha → gira alrededor, arriba → mira
## desde más arriba. El modelo no se mueve (como Blender / Godot).
func rotate_orbit(delta_x: float, delta_y: float) -> void:
	var sens := 0.45
	view_yaw = wrapf(view_yaw - delta_x * sens, -180.0, 180.0)
	view_pitch = clampf(view_pitch + delta_y * sens, -89.5, 89.5)
	_apply_camera_transform()
	request_render_update()

## Desplazar la vista (Mayús + arrastrar): mueve el punto de interés en el
## plano de la pantalla, a la velocidad del ratón.
func pan_view(delta_x: float, delta_y: float) -> void:
	if not is_instance_valid(_camera):
		return
	var world_per_px := (2.0 * camera_distance * tan(deg_to_rad(camera_fov) * 0.5)) / maxf(size.y, 1.0)
	var b := _camera.global_transform.basis
	view_target += (-b.x * delta_x + b.y * delta_y) * world_per_px
	_apply_camera_transform()
	request_render_update()

## Girar la luz principal (Alt + arrastrar).
func rotate_light(delta_x: float, delta_y: float) -> void:
	light_rotation = Vector3(clampf(light_rotation.x + delta_y * 0.5, -89.0, 89.0), wrapf(light_rotation.y + delta_x * 0.5, -180.0, 180.0), light_rotation.z)
	_apply_lighting()
	request_render_update()

## Zoom de cámara (rueda): acercar/alejar multiplicando la distancia.
func zoom_camera(delta: float) -> void:
	camera_distance = clampf(camera_distance * pow(0.88, delta), 0.3, 60.0)
	_apply_camera_transform()
	is_interactive_zooming = true
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	queue_redraw()
	_schedule_zoom_settle()

## Vistas rápidas: front, back, right, left, top, bottom, iso.
const VIEWS := {"front": [0.0, 0.0], "back": [180.0, 0.0], "right": [90.0, 0.0], "left": [-90.0, 0.0],
	"top": [0.0, 89.5], "bottom": [0.0, -89.5], "iso": [45.0, 30.0]}

func set_view(name: String) -> void:
	if not VIEWS.has(name):
		return
	view_yaw = VIEWS[name][0]
	view_pitch = VIEWS[name][1]
	_apply_camera_transform()
	request_render_update()

func toggle_ortho() -> void:
	camera_ortho = not camera_ortho

## Encuadrar (F): centra el modelo y ajusta la distancia para que quepa.
func frame_model() -> void:
	view_target = Vector3.ZERO
	camera_distance = 1.25 / tan(deg_to_rad(camera_fov) * 0.5) * 1.15
	_apply_camera_transform()
	request_render_update()

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
	view_yaw = 0.0
	view_pitch = 0.0
	view_target = Vector3.ZERO
	camera_ortho = false
	camera_distance = 3.5
	camera_fov = 45.0
	_apply_model_transform()
	_apply_camera_transform()
	request_render_update()

# ── gizmo de ejes (esquina superior derecha, como Godot / Blender) ─────────
const GIZMO_R := 26.0
const AXES := {"X": [Vector3.RIGHT, Color(0.93, 0.3, 0.33), "right", "left"],
	"Y": [Vector3.UP, Color(0.45, 0.82, 0.25), "top", "bottom"],
	"Z": [Vector3.BACK, Color(0.3, 0.55, 0.98), "front", "back"]}

func _gizmo_center() -> Vector2:
	var rect := Rect2(-size * 0.5, size)
	return Vector2(rect.end.x - GIZMO_R - 8.0, rect.position.y + GIZMO_R + 26.0)

## Ejes proyectados: [[pos 2D local, color, etiqueta, vista, delante?]…]
func _gizmo_axes() -> Array:
	var out: Array = []
	if not is_instance_valid(_camera):
		return out
	var inv := _camera.global_transform.basis.inverse()
	var c := _gizmo_center()
	for k in AXES:
		for sgn in [1.0, -1.0]:
			var v: Vector3 = inv * ((AXES[k][0] as Vector3) * sgn)
			out.append([c + Vector2(v.x, -v.y) * (GIZMO_R - 7.0), AXES[k][1], k if sgn > 0 else "", AXES[k][2] if sgn > 0 else AXES[k][3], v.z])
	out.sort_custom(func(a, b) -> bool: return a[4] < b[4])   # los de detrás primero
	return out

## Vista bajo un punto local del gizmo ("" si no hay eje ahí).
func gizmo_hit(local: Vector2) -> String:
	if not is_3d_editing:
		return ""
	var best := ""
	var best_d := 9.0
	for a in _gizmo_axes():
		var d: float = (a[0] as Vector2).distance_to(local)
		if d < best_d:
			best_d = d
			best = a[3]
	return best

func _draw_gizmo() -> void:
	var c := _gizmo_center()
	draw_circle(c, GIZMO_R, Color(0.08, 0.1, 0.14, 0.55))
	var font := ThemeDB.fallback_font
	for a in _gizmo_axes():
		var p: Vector2 = a[0]
		var col: Color = a[1]
		if String(a[2]) != "":
			draw_line(c, p, col, 2.0, true)
			draw_circle(p, 7.0, col)
			draw_string(font, p + Vector2(-3.5, 4.0), String(a[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.05, 0.05, 0.05))
		else:
			draw_circle(p, 6.0, Color(col, 0.35))
			draw_arc(p, 6.0, 0, TAU, 16, col, 1.2, true)

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
		var hint := "Arrastrar: orbitar · Mayús: desplazar · Rueda: zoom · Alt: luz · 1 3 7 5 · F · Esc"
		if rect.size.x < 330.0:
			hint = "Orbitar · Mayús desplazar · Alt luz · Esc"
		draw_string(font, rect.position + Vector2(6, 14), hint, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 10, Color.WHITE)
		_draw_gizmo()

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
	s["view_yaw"] = view_yaw
	s["view_pitch"] = view_pitch
	s["view_target"] = view_target
	s["camera_ortho"] = camera_ortho
	s["light_preset"] = light_preset
	s["model_shadows"] = model_shadows
	s["light_color"] = light_color
	s["ambient_energy"] = ambient_energy
	return s
