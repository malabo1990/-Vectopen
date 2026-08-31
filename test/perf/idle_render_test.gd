extends GdUnitTestSuite

## Render bajo demanda de PerformanceManager: sin input -> Engine.max_fps baja
## a IDLE_FPS tras IDLE_DELAY_MS; mark_activity() / input lo restaura.

func _pm() -> Node:
	return get_node_or_null("/root/PerformanceManager")

var _saved_fps := 0
var _saved_target := 0

func before_test() -> void:
	_saved_fps = Engine.max_fps
	var pm := _pm()
	if pm: _saved_target = pm.target_fps

func after_test() -> void:
	var pm := _pm()
	if pm:
		pm.target_fps = _saved_target
		pm.set_idle_render(true)
		pm.mark_activity()
	Engine.max_fps = _saved_fps

func test_baja_a_idle_sin_actividad_y_vuelve() -> void:
	var pm := _pm()
	assert_object(pm).is_not_null()
	if pm == null:
		return
	pm.idle_render_enabled = true
	pm.target_fps = 60
	pm.set_idle_render(true)

	# actividad reciente -> no idle
	pm.mark_activity()
	await get_tree().process_frame
	assert_bool(pm._is_idle).is_false()

	# forzar "hace mucho que no hay actividad"
	pm._last_activity_ms = Time.get_ticks_msec() - (pm.IDLE_DELAY_MS + 500)
	# dejar correr unos frames para que _process lo detecte
	for i in 5:
		await get_tree().process_frame
	assert_bool(pm._is_idle).is_true()
	assert_int(Engine.max_fps).is_equal(pm.IDLE_FPS)

	# actividad -> restaura al instante
	pm.mark_activity()
	assert_bool(pm._is_idle).is_false()
	assert_int(Engine.max_fps).is_equal(60)

func test_desactivable() -> void:
	var pm := _pm()
	if pm == null:
		return
	# estado limpio y determinista (el sistema idle corre durante toda la suite)
	pm.target_fps = 60
	pm.set_idle_render(false)
	pm._is_idle = false
	Engine.max_fps = 60
	pm._last_activity_ms = Time.get_ticks_msec() - 100000
	for i in 5:
		await get_tree().process_frame
	# desactivado: NO debe entrar en idle ni tocar el cap
	assert_bool(pm._is_idle).is_false()
	assert_int(Engine.max_fps).is_equal(60)
