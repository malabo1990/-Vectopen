# =============================================================================
# FASE B · ENCARGO 27 — Shader: degradado animado con ruido (modo Pro)
# Foco: shader simple, parámetros en el Inspector.
# Fondo 1280 × 720 con un shader propio: degradado entre dos colores que se
# desplaza con TIME y lleva ruido de valor. Uniforms con rango
# (velocidad, escala del ruido, intensidad) y dos colores. Se aplica, se ve
# ANIMADO (dos fotogramas distintos), los parámetros salen en la sección
# Shader del Inspector y cambiarlos se ve (con deshacer), se guarda en la
# biblioteca, se exporta PNG con el shader, se reabre con sus parámetros.
#   test/run_e2e.sh proyecto_27_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/27"
const CODE := """shader_type canvas_item;
uniform vec4 color_a : source_color = vec4(0.12, 0.05, 0.35, 1.0);
uniform vec4 color_b : source_color = vec4(0.95, 0.35, 0.25, 1.0);
uniform float speed : hint_range(0.0, 5.0, 0.05) = 1.0;
uniform float noise_scale : hint_range(1.0, 200.0, 1.0) = 40.0;
uniform float noise_amount : hint_range(0.0, 1.0, 0.01) = 0.15;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float t = fract(UV.x * 0.8 + UV.y * 0.2 + TIME * speed * 0.1);
	float n = vnoise(UV * noise_scale + vec2(TIME * speed, 0.0));
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.0, 1.0, abs(t * 2.0 - 1.0)));
	col += (n - 0.5) * noise_amount;
	COLOR = vec4(col, base.a);
}
"""
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func region_sig(ab: Node2D) -> float:
	var img := root.get_texture().get_image()
	var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var acc := 0.0
	for k in 40:
		var p: Vector2 = xf * (ab.global_position + Vector2(100 + k * 27, 360))
		acc += img.get_pixelv(Vector2i(p)).r + img.get_pixelv(Vector2i(p)).b * 2.0
	return acc

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1280, 720), "Fondo animado", Color.BLACK)
	var bg = api.add_rect(Vector2(640, 360), Vector2(1280, 720), 0.0, "Fondo")
	api.set_props(bg, {"fill_color": Color.WHITE, "stroke_width": 0.0})
	var ok: bool = api.apply_shader(bg, CODE)
	K.check("el shader compila y se aplica", ok and not api.get_shader(bg).is_empty())
	var bad: bool = api.apply_shader(bg, "shader_type canvas_item; void fragment() { COLOR = vec4(1.0) }")
	K.check("un shader con errores se rechaza sin romper el objeto", not bad and String(api.get_shader(bg).get("code", "")) == CODE)
	await K.look_at(ab)
	await K.frames(10)
	await RenderingServer.frame_post_draw
	var s0 := region_sig(ab)
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var s1 := region_sig(ab)
	K.check("animado: dos fotogramas distintos", absf(s1 - s0) > 0.05, "%.3f → %.3f" % [s0, s1])
	# Parámetros en la sección Shader del Inspector
	api.select([bg])
	await K.frames(8)
	var box: Node = null
	for n in root.find_children("ShaderParams", "", true, false):
		box = n
	if box == null:
		# Smart: Efectos ▸ pestaña Shader (se instala al mostrarse).
		for h in root.find_children("Shader", "Control", true, false):
			var q: Node = h
			while q and q is CanvasItem:
				(q as CanvasItem).visible = true
				q = q.get_parent()
		await K.frames(10)
		for n in root.find_children("ShaderParams", "", true, false):
			box = n
	K.check("parámetros del shader en el Inspector", box != null)
	if box:
		box.refresh()
		await K.frames(2)
		var names: Array = box.get_children().map(func(r): return String(r.name))
		K.check("un control por uniform (5)", names.size() == 5 and "Param_speed" in names and "Param_color_b" in names, str(names))
		var sl: HSlider = box.get_node_or_null("Param_speed/Slider")
		K.check("velocidad con su rango 0–5", sl != null and is_equal_approx(sl.max_value, 5.0) and is_equal_approx(sl.value, 1.0), str([sl.max_value, sl.value]) if sl else "-")
		box.set_param("speed", 0.0)
		box.set_param("noise_amount", 0.0)
		await K.frames(4)
		K.check("cambiar la velocidad desde el Inspector", is_equal_approx(float(api.get_shader(bg)["params"].get("speed", -1.0)), 0.0))
		# Velocidad 0 y sin ruido: quieto
		await RenderingServer.frame_post_draw
		var q0 := region_sig(ab)
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var q1 := region_sig(ab)
		K.check("velocidad 0: deja de moverse", absf(q1 - q0) < 0.02, "%.3f → %.3f" % [q0, q1])
		box.set_param("color_b", Color("#2ec4b6"))
		await K.frames(4)
		K.check("color del shader cambiado", api.get_shader(bg)["params"].has("color_b"))
		api.undo()
		await K.frames(2)
		K.check("deshacer el color", not api.get_shader(bg)["params"].has("color_b"))
		await RenderingServer.frame_post_draw
		var img_u := root.get_texture().get_image()
		var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
		var edge := img_u.get_pixelv(Vector2i(xf * (ab.global_position + Vector2(60, 360))))
		K.check("…y en pantalla vuelve el color original (rojizo, no turquesa)", edge.r > edge.g + 0.2, str(edge))
	# Biblioteca
	var errs: Array = api.save_shader("Degradado con ruido", CODE)
	K.check("guardado en la biblioteca de shaders", errs.is_empty() and api.shaders().any(func(s) -> bool: return String(s).contains("Degradado con ruido") or (s is Dictionary and String(s.get("name", "")).contains("Degradado"))), str(api.shaders()))
	await K.shot("01_shader")
	# PNG con el shader
	var png := ProjectSettings.globalize_path(OUT.path_join("fondo.png"))
	var okp: bool = await api.export(png, ab)
	var img := Image.load_from_file(png) if okp else null
	var px := img.get_pixel(640, 360) if img else Color.WHITE
	K.check("PNG con el shader aplicado (no blanco)", img != null and not px.is_equal_approx(Color.WHITE), str(px))
	await K.frames(30)
	var abs: Array = await K.save_reload("shader")
	for a in abs:
		if String(a.name) == "Fondo animado":
			var b2: Node = a.find_child("Fondo", false, false)
			var sh2: Dictionary = api.get_shader(b2) if b2 else {}
			K.check("reabrir: shader y parámetros", not sh2.is_empty() and is_equal_approx(float(sh2.get("params", {}).get("speed", -1.0)), 0.0))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
