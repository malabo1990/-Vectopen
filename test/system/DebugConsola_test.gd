extends GdUnitTestSuite

## La consola de diagnóstico (autoload DebugConsola) debe: registrar cada
## anomalía UNA vez (dedupe), y solo disparar una condición cuando PERSISTE el
## umbral de barridos seguidos (nada de falsos positivos de un frame suelto).

func _consola() -> Node:
	# instancia aislada (no el autoload) para no ensuciar el estado global
	var c: Node = auto_free(load("res://script_gdscript/system/DebugConsola.gd").new())
	add_child(c)
	return c

func test_persistencia_solo_dispara_al_alcanzar_el_umbral() -> void:
	var c := _consola()
	# 2 barridos con la condición viva, umbral 3 → todavía NO hay anomalía
	c._persistencia("x", true, 3, "[DBG:TEST] x roto")
	c._persistencia("x", true, 3, "[DBG:TEST] x roto")
	assert_bool(c._anomalias.has("x")).is_false()
	# 3er barrido → se registra
	c._persistencia("x", true, 3, "[DBG:TEST] x roto")
	assert_bool(c._anomalias.has("x")).is_true()
	assert_int(c._anomalias["x"]["n"]).is_equal(1)


func test_condicion_intermitente_no_dispara() -> void:
	var c := _consola()
	c._persistencia("y", true, 3, "m")
	c._persistencia("y", false, 3, "m")   # se corta → contador a 0
	c._persistencia("y", true, 3, "m")
	c._persistencia("y", true, 3, "m")
	assert_bool(c._anomalias.has("y")).is_false()


func test_anomalia_se_agrupa_no_se_repite_infinito() -> void:
	var c := _consola()
	for i in 10:
		c._anom("z", "[DBG:TEST] z")
	# una sola entrada, con contador acumulado
	assert_int(c._anomalias.size()).is_equal(1)
	assert_int(c._anomalias["z"]["n"]).is_equal(10)


func test_evento_no_crashea_sin_mcpruntime() -> void:
	var c := _consola()
	c.evento("reparent", "A → B")   # no debe reventar aunque no haya MCPRuntime en el path
	assert_bool(true).is_true()
