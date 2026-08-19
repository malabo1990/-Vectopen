extends Node

enum DeviceClass { POTATO, LOW, BALANCED, HIGH, ULTRA }
enum RendererAPI { VULKAN_FORWARD_PLUS, VULKAN_MOBILE, GL_COMPATIBILITY, UNKNOWN }
enum DeviceType { DESKTOP, LAPTOP, TABLET, PHONE, UNKNOWN }

const PRESET_NAMES: Dictionary = {
	DeviceClass.POTATO: "potato",
	DeviceClass.LOW: "low",
	DeviceClass.BALANCED: "balanced",
	DeviceClass.HIGH: "high",
	DeviceClass.ULTRA: "ultra",
}

const TIER_SCORE: Dictionary = {
	DeviceClass.POTATO: 0,
	DeviceClass.LOW: 1,
	DeviceClass.BALANCED: 2,
	DeviceClass.HIGH: 3,
	DeviceClass.ULTRA: 4,
}

## Fuente única de verdad para el target_fps de cada tier — la usan tanto
## _apply_hardware_profile() (perfil activo) como _adaptive_tick() (para mirar
## el target de la tier SIGUIENTE antes de subir, ver _stage_up()/§1.10).
const TARGET_FPS_BY_TIER: Dictionary = {
	DeviceClass.POTATO: 30,
	DeviceClass.LOW: 30,
	DeviceClass.BALANCED: 60,
	DeviceClass.HIGH: 60,
	DeviceClass.ULTRA: 144,
}

## Umbral mínimo (como fracción del target_fps de la tier SIGUIENTE) para
## considerar seguro subir de tier — más exigente que el 0.95 usado contra
## el target de la tier actual, precisamente para no subir a una tier cuyo
## objetivo no se vaya a sostener y tener que bajar de inmediato otra vez.
const _STAGE_UP_NEXT_TIER_RATIO: float = 0.8

# ── Estado detectado ─────────────────────────────────────────────────
var device_class: int = DeviceClass.BALANCED
var device_type: int = DeviceType.UNKNOWN
var renderer_api: int = RendererAPI.UNKNOWN

var gpu_name: String = ""
var gpu_driver: String = ""
var gpu_vram_mb: int = 0
var cpu_count: int = 0
var cpu_name: String = ""
var ram_mb: int = 0
var is_battery_powered: bool = false
var is_mobile: bool = false

# ── Preset activo ────────────────────────────────────────────────────
var quality_preset: String = "balanced"
var target_fps: int = 60
var adaptive_quality: bool = true
var show_overlay: bool = false

# ── Escalado dinámico ────────────────────────────────────────────────
var resolution_scale: float = 1.0
var texture_quality: int = 0
var shadow_atlas_size: int = 2048
var max_particles: int = 500

var _fps_history: Array[float] = []
var _frame_time_history: Array[float] = []
var _overlay_label: Label = null
var _stats_timer: Timer = null
var _adapt_timer: Timer = null

# Enfriamiento tras cambiar de tier: sin esto, _adaptive_tick() rebotaba sin
# parar entre dos tiers cada 5s (p.ej. ultra→high→ultra→high...) porque el
# ratio avg_fps/target_fps se reevaluaba con un historial que todavía
# mezclaba muestras de antes y después del cambio — encontrado el 19/08/2026
# al verificar el arreglo de target_fps congelado (ver _stage_down/_stage_up).
const _STAGE_COOLDOWN_MS: int = 10000
var _last_stage_change_ms: int = 0

# Señales
signal quality_changed(preset: String)
signal device_classified(device_class: int, device_type: int)
signal performance_degraded(reason: String, value: float)

func _ready() -> void:
	_detect_everything()
	_classify_device()
	_apply_hardware_profile()
	_setup_timers()
	_apply_quality_settings()

func _detect_everything() -> void:
	_detect_renderer()
	_detect_gpu()
	_detect_cpu_and_ram()
	_detect_device_type()

func _detect_renderer() -> void:
	var method = ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")
	match method:
		"forward_plus":
			renderer_api = RendererAPI.VULKAN_FORWARD_PLUS
		"mobile":
			renderer_api = RendererAPI.VULKAN_MOBILE
		"gl_compatibility":
			renderer_api = RendererAPI.GL_COMPATIBILITY
		_:
			renderer_api = RendererAPI.UNKNOWN

	if OS.has_feature("mobile"):
		renderer_api = RendererAPI.VULKAN_MOBILE

	var driver_arr = OS.get_video_adapter_driver_info()
	if driver_arr is Array:
		gpu_driver = "%s" % driver_arr[0] if driver_arr.size() >= 1 else ""
		if driver_arr.size() >= 2:
			gpu_driver += " %s" % driver_arr[1]
	else:
		gpu_driver = str(driver_arr) if driver_arr else "unknown"

func _detect_gpu() -> void:
	gpu_name = RenderingServer.get_video_adapter_name()

func _detect_cpu_and_ram() -> void:
	cpu_count = OS.get_processor_count()
	var mem_info := OS.get_memory_info()
	if mem_info.has("physical") and mem_info["physical"] > 0:
		ram_mb = int(mem_info["physical"] / 1048576)
	else:
		ram_mb = _estimate_ram_from_os()

func _estimate_ram_from_os() -> int:
	if OS.has_feature("windows"):
		return 2048
	elif OS.has_feature("android"):
		return 2048
	elif OS.has_feature("linux") or OS.has_feature("macos"):
		return 4096
	return 2048

func _detect_device_type() -> void:
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	is_battery_powered = is_mobile

	if OS.has_feature("android") or OS.has_feature("ios"):
		var is_tablet = _is_tablet_size()
		device_type = DeviceType.TABLET if is_tablet else DeviceType.PHONE
	elif OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos"):
		device_type = DeviceType.DESKTOP
	else:
		device_type = DeviceType.UNKNOWN

func _is_tablet_size() -> bool:
	var screen = DisplayServer.screen_get_size()
	var diag = Vector2(screen.x, screen.y).length() / DisplayServer.screen_get_dpi()
	return diag > 7.0

func _classify_device() -> void:
	var score := 0.0

	var gpu_lower = gpu_name.to_lower()
	if gpu_lower.is_empty():
		score += 0
	elif "gtx 10" in gpu_lower or "gtx 16" in gpu_lower or "rx 5" in gpu_lower or "uhd" in gpu_lower or "hd gra" in gpu_lower:
		score += 1
	elif "gtx 20" in gpu_lower or "rtx 20" in gpu_lower or "rx 6" in gpu_lower or "vega" in gpu_lower or "iris xe" in gpu_lower:
		score += 2
	elif "rtx 30" in gpu_lower or "rx 7" in gpu_lower or "arc" in gpu_lower or "m1" in gpu_lower:
		score += 3
	elif "rtx 40" in gpu_lower or "rx 9" in gpu_lower or "m2" in gpu_lower or "m3" in gpu_lower or "m4" in gpu_lower:
		score += 4
	else:
		score += 1

	if cpu_count <= 2:
		score -= 0.5
	elif cpu_count <= 4:
		pass
	elif cpu_count <= 8:
		score += 0.5
	else:
		score += 1

	if ram_mb < 2048:
		score -= 1
	elif ram_mb < 4096:
		score -= 0.5
	elif ram_mb < 8192:
		pass
	else:
		score += 0.5

	if is_mobile:
		score -= 0.5

	score = clamp(score, 0, 4)
	var dc = roundi(score)
	if dc <= 0:
		device_class = DeviceClass.POTATO
	elif dc == 1:
		device_class = DeviceClass.LOW
	elif dc == 2:
		device_class = DeviceClass.BALANCED
	elif dc == 3:
		device_class = DeviceClass.HIGH
	else:
		device_class = DeviceClass.ULTRA

	quality_preset = PRESET_NAMES[device_class]
	print("Vectopen classified: %s (gpu=%s cpu=%d ram=%dMB mobile=%s)" % [
		quality_preset, gpu_name, cpu_count, ram_mb, is_mobile])

	device_classified.emit(device_class, device_type)

func _apply_hardware_profile() -> void:
	target_fps = TARGET_FPS_BY_TIER.get(device_class, 60)
	match device_class:
		DeviceClass.POTATO:
			resolution_scale = 0.5
			texture_quality = 2
			shadow_atlas_size = 512
			max_particles = 50
		DeviceClass.LOW:
			resolution_scale = 0.67
			texture_quality = 1
			shadow_atlas_size = 1024
			max_particles = 150
		DeviceClass.BALANCED:
			resolution_scale = 0.85
			texture_quality = 0
			shadow_atlas_size = 2048
			max_particles = 500
		DeviceClass.HIGH:
			resolution_scale = 1.0
			texture_quality = 0
			shadow_atlas_size = 4096
			max_particles = 2000
		DeviceClass.ULTRA:
			resolution_scale = 1.0
			texture_quality = 0
			shadow_atlas_size = 4096
			max_particles = 5000

	if is_mobile:
		target_fps = min(target_fps, 60)
		resolution_scale = min(resolution_scale, 0.85)

	Engine.max_fps = target_fps
	print("Profile: %s | FPS=%d | Scale=%.2f | Shadows=%d | Particles=%d" % [
		quality_preset, target_fps, resolution_scale, shadow_atlas_size, max_particles])

func _setup_timers() -> void:
	_stats_timer = Timer.new()
	_stats_timer.wait_time = 1.0
	_stats_timer.timeout.connect(_check_performance)
	add_child(_stats_timer)
	_stats_timer.start()

	_adapt_timer = Timer.new()
	_adapt_timer.wait_time = 5.0
	_adapt_timer.timeout.connect(_adaptive_tick)
	add_child(_adapt_timer)
	_adapt_timer.start()

func _check_performance() -> void:
	var fps = Engine.get_frames_per_second()
	var frame_time = Performance.get_monitor(Performance.TIME_PROCESS)
	var memory = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576

	_fps_history.push_back(fps)
	if _fps_history.size() > 60:
		_fps_history.pop_front()
	_frame_time_history.push_back(frame_time)
	if _frame_time_history.size() > 60:
		_frame_time_history.pop_front()

	if memory > (ram_mb * 0.7) and ram_mb > 0:
		performance_degraded.emit("high_memory", memory)
		_optimize_memory()

	var avg_fps_float = _avg(_fps_history)
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var verts = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var objs = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_update_overlay(avg_fps_float, _avg(_frame_time_history), memory, draw_calls, verts, objs)

func _avg(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var s: float = 0.0
	for v in arr:
		s += v
	return s / arr.size()

func _adaptive_tick() -> void:
	if not adaptive_quality:
		return
	if Time.get_ticks_msec() - _last_stage_change_ms < _STAGE_COOLDOWN_MS:
		return
	var avg_fps = _avg(_fps_history)
	if avg_fps <= 0:
		return
	var ratio = avg_fps / target_fps
	var tier = TIER_SCORE.get(device_class, 2)

	if ratio < 0.5 and tier > TIER_SCORE[DeviceClass.POTATO]:
		_stage_down()
	elif ratio < 0.7 and tier > TIER_SCORE[DeviceClass.LOW]:
		_stage_down()
	elif ratio > 0.95 and tier < TIER_SCORE[DeviceClass.ULTRA]:
		# No basta con cumplir de sobra el target de la tier ACTUAL (más fácil) —
		# hay que comprobar que el FPS real también aguantaría el target más
		# exigente de la tier SIGUIENTE, o subimos solo para tener que volver
		# a bajar en el próximo tick tras el enfriamiento. Encontrado el
		# 19/08/2026 como causa de la oscilación residual "ultra ↔ high" del §1.9.
		var next_tier_target: int = TARGET_FPS_BY_TIER.get(device_class + 1, target_fps)
		if avg_fps / float(next_tier_target) > _STAGE_UP_NEXT_TIER_RATIO:
			_stage_up()

func _stage_down() -> void:
	var t = TIER_SCORE.get(device_class, 2)
	if t <= TIER_SCORE[DeviceClass.POTATO]:
		_lower_resolution_scale()
		return
	device_class = t - 1
	quality_preset = PRESET_NAMES[device_class]
	# Re-sincroniza target_fps (y el resto del perfil) al de la nueva tier más
	# baja. Sin esto, target_fps se quedaba congelado en el valor de la tier
	# inicial (p.ej. 144 en "ultra") para siempre, así que el ratio avg_fps/
	# target_fps de _adaptive_tick() nunca mejoraba tras bajar de tier y el
	# sistema seguía degradando en cascada hasta "potato" aunque el hardware
	# fuera capaz de más — encontrado el 19/08/2026 viendo el log real bajar
	# de ultra a potato en ~20s en una RTX 3060.
	_apply_hardware_profile()
	resolution_scale = max(resolution_scale * 0.85, 0.35)
	_apply_quality_settings()
	_reset_adaptive_measurement_window()
	quality_changed.emit(quality_preset)
	performance_degraded.emit("downscaled", float(device_class))
	print("Vectopen stepped DOWN to: %s (scale=%.2f)" % [quality_preset, resolution_scale])

func _stage_up() -> void:
	var t = TIER_SCORE.get(device_class, 2)
	if t >= TIER_SCORE[DeviceClass.ULTRA]:
		return
	device_class = t + 1
	quality_preset = PRESET_NAMES[device_class]
	# Mismo motivo que en _stage_down(): re-sincroniza target_fps a la nueva
	# tier antes de reajustar resolution_scale sobre esa base.
	_apply_hardware_profile()
	resolution_scale = min(resolution_scale * 1.1, 1.0)
	_apply_quality_settings()
	_reset_adaptive_measurement_window()
	quality_changed.emit(quality_preset)
	print("Vectopen stepped UP to: %s" % quality_preset)

## Llamado tras cualquier cambio de tier — arranca el enfriamiento
## (_STAGE_COOLDOWN_MS) y descarta las muestras de FPS de la tier anterior,
## para que la siguiente decisión de _adaptive_tick() se base solo en el
## rendimiento real ya con el nuevo target_fps aplicado.
func _reset_adaptive_measurement_window() -> void:
	_last_stage_change_ms = Time.get_ticks_msec()
	_fps_history.clear()
	_frame_time_history.clear()

func _lower_resolution_scale() -> void:
	resolution_scale = max(resolution_scale * 0.75, 0.25)
	print("Vectopen lowered resolution scale to: %.2f" % resolution_scale)

func _optimize_memory() -> void:
	performance_degraded.emit("memory_optimized", 0.0)
	if has_node("/root/GlobalEvents"):
		GlobalEvents.memory_pressure_high.emit(float(ram_mb))

func _apply_quality_settings() -> void:
	if not is_inside_tree():
		return
	var vr = get_viewport().get_viewport_rid()
	var _msaa_ok := renderer_api != RendererAPI.GL_COMPATIBILITY

	if _msaa_ok:
		match quality_preset:
			"potato":
				RenderingServer.viewport_set_msaa_2d(vr, RenderingServer.VIEWPORT_MSAA_DISABLED)
			"low":
				RenderingServer.viewport_set_msaa_2d(vr, RenderingServer.VIEWPORT_MSAA_DISABLED)
			"balanced":
				RenderingServer.viewport_set_msaa_2d(vr, RenderingServer.VIEWPORT_MSAA_2X)
			"high":
				RenderingServer.viewport_set_msaa_2d(vr, RenderingServer.VIEWPORT_MSAA_4X)
			"ultra":
				RenderingServer.viewport_set_msaa_2d(vr, RenderingServer.VIEWPORT_MSAA_8X)
	else:
		RenderingServer.viewport_set_msaa_2d(vr, RenderingServer.VIEWPORT_MSAA_DISABLED)

	match quality_preset:
		"potato":
			RenderingServer.viewport_set_screen_space_aa(vr, RenderingServer.VIEWPORT_SCREEN_SPACE_AA_DISABLED)
			RenderingServer.viewport_set_scaling_3d_scale(vr, 0.5)
			RenderingServer.directional_shadow_atlas_set_size(512, false)
		"low":
			RenderingServer.viewport_set_screen_space_aa(vr, RenderingServer.VIEWPORT_SCREEN_SPACE_AA_DISABLED)
			RenderingServer.viewport_set_scaling_3d_scale(vr, 0.67)
			RenderingServer.directional_shadow_atlas_set_size(1024, false)
		"balanced":
			RenderingServer.viewport_set_screen_space_aa(vr, RenderingServer.VIEWPORT_SCREEN_SPACE_AA_FXAA)
			RenderingServer.viewport_set_scaling_3d_scale(vr, 0.85)
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
		"high":
			RenderingServer.viewport_set_scaling_3d_scale(vr, 1.0)
			RenderingServer.directional_shadow_atlas_set_size(4096, false)
		"ultra":
			RenderingServer.viewport_set_scaling_3d_scale(vr, 1.0)
			RenderingServer.directional_shadow_atlas_set_size(4096, false)

	if is_mobile and renderer_api == RendererAPI.VULKAN_MOBILE and _msaa_ok:
		RenderingServer.viewport_set_msaa_2d(vr, RenderingServer.VIEWPORT_MSAA_DISABLED)

func set_quality(preset: String) -> void:
	quality_preset = preset
	var found = -1
	for k in PRESET_NAMES:
		if PRESET_NAMES[k] == preset:
			found = k
			break
	if found >= 0:
		device_class = found
	_apply_hardware_profile()
	_apply_quality_settings()
	quality_changed.emit(preset)

func set_resolution_scale(scale: float) -> void:
	resolution_scale = clamp(scale, 0.25, 1.0)
	if is_inside_tree():
		var vr = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_scaling_3d_scale(vr, resolution_scale)

func get_readable_gpu_info() -> String:
	return "GPU: %s | Driver: %s" % [gpu_name, gpu_driver]

func get_readable_stats() -> String:
	var fps = Engine.get_frames_per_second()
	var mem = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576
	var dc = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var verts = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	return "FPS: %d | Mem: %dMB | Draw: %d | Verts: %d" % [fps, mem, dc, verts]

func get_readable_device_report() -> String:
	return (
		"Device: %s | Class: %s\n" % [_device_type_name(), quality_preset] +
		"GPU: %s\n" % gpu_name +
		"CPU: %d cores | RAM: %dMB\n" % [cpu_count, ram_mb] +
		"Renderer: %s\n" % _renderer_name() +
		"FPS: %d (target %d) | Scale: %.0f%%\n" % [Engine.get_frames_per_second(), target_fps, resolution_scale * 100] +
		"Shadows: %d | Particles: %d" % [shadow_atlas_size, max_particles]
	)

func _device_type_name() -> String:
	match device_type:
		DeviceType.DESKTOP: return "Desktop"
		DeviceType.LAPTOP: return "Laptop"
		DeviceType.TABLET: return "Tablet"
		DeviceType.PHONE: return "Phone"
		_: return "Unknown"

func _renderer_name() -> String:
	match renderer_api:
		RendererAPI.VULKAN_FORWARD_PLUS: return "Vulkan Forward+"
		RendererAPI.VULKAN_MOBILE: return "Vulkan Mobile"
		RendererAPI.GL_COMPATIBILITY: return "OpenGL (Compat)"
		_: return "Unknown"

func toggle_overlay() -> void:
	show_overlay = not show_overlay
	if _overlay_label:
		_overlay_label.visible = show_overlay

func _setup_overlay() -> void:
	if not is_inside_tree():
		await ready
	var canvas = CanvasLayer.new()
	canvas.layer = 128
	canvas.name = "_PerformanceOverlayLayer"
	add_child(canvas)
	_overlay_label = Label.new()
	_overlay_label.name = "_PerformanceOverlay"
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_overlay_label.position = Vector2(8, 8)
	_overlay_label.add_theme_color_override("font_color", Color(0, 1, 0))
	_overlay_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_overlay_label.add_theme_constant_override("shadow_offset_x", 1)
	_overlay_label.add_theme_constant_override("shadow_offset_y", 1)
	_overlay_label.add_theme_font_size_override("font_size", 11)
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_overlay_label.visible = show_overlay
	canvas.add_child(_overlay_label)

func _update_overlay(avg_fps: float, avg_ft: float, mem: float, dc: float, verts: float, objs: float) -> void:
	if not _overlay_label or not show_overlay:
		return
	var color = "green" if avg_fps >= target_fps * 0.9 else ("yellow" if avg_fps >= target_fps * 0.7 else "red")
	_overlay_label.text = (
		"[color=%s]FPS: %d (avg %d)[/color]\n" % [color, Engine.get_frames_per_second(), int(avg_fps)] +
		"Frame: %.2fms\n" % (avg_ft * 1000) +
		"Mem: %d/%dMB\n" % [int(mem), ram_mb] +
		"Draw: %d | Verts: %d\n" % [int(dc), int(verts)] +
		"Objects: %d\n" % int(objs) +
		"GPU: %s\n" % gpu_name +
		"Quality: %s | Scale: %.0f%%\n" % [quality_preset, resolution_scale * 100] +
		"Device: %s | %s" % [_device_type_name(), _renderer_name()]
	)
