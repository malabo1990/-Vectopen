extends GdUnitTestSuite

## Test suite para VectopenMCPServer (Servidor MCP Embebido en Vectopen).
## Valida el protocolo MCP (JSON-RPC 2.0), autenticación Bearer, rechazo anti-CSRF,
## registro de herramientas y manipulación de propiedades mediante InspectorCore.

const CANVAS := "res://scenes/canvas/canvas.tscn"

func _server() -> Node:
	var s: Node = auto_free(load("res://script_gdscript/system/VectopenMCPServer.gd").new())
	add_child(s)
	return s

func test_inicializacion_y_registro_de_herramientas() -> void:
	var s := _server()
	assert_bool(s._tools.has("get_project_info")).is_true()
	assert_bool(s._tools.has("get_properties")).is_true()
	assert_bool(s._tools.has("set_property")).is_true()
	assert_bool(s._tools.has("create_shape")).is_true()
	assert_bool(s._tools.has("undo")).is_true()
	assert_bool(s._tools.has("redo")).is_true()

func test_mcp_initialize() -> void:
	var s := _server()
	var res = await s._dispatch("initialize", {})
	assert_that(res).is_not_null()
	assert_str(res["protocolVersion"]).is_equal("2024-11-05")
	assert_str(res["serverInfo"]["name"]).is_equal("vectopen")

func test_mcp_tools_list() -> void:
	var s := _server()
	var res = await s._dispatch("tools/list", {})
	assert_that(res).is_not_null()
	assert_bool(res.has("tools")).is_true()
	assert_int((res["tools"] as Array).size()).is_greater_equal(10)

func test_seguridad_tokens_match() -> void:
	var s := _server()
	var token: String = s.get_token()
	assert_str(token).is_not_empty()
	assert_bool(s._tokens_match("Bearer " + token, "Bearer " + token)).is_true()
	assert_bool(s._tokens_match("Bearer fake_token", "Bearer " + token)).is_false()

func test_seguridad_rechazo_con_origin_anti_csrf() -> void:
	var s := _server()
	var conn = load("res://script_gdscript/system/VectopenMCPServer.gd")._Conn.new()
	conn.header_text = "POST / HTTP/1.1\r\nOrigin: http://malicious-site.com\r\nHost: 127.0.0.1:%d\r\n\r\n" % s.get_port()
	assert_str(s._reject_reason(conn)).is_equal("origin not allowed")

func test_seguridad_rechazo_host_invalido_anti_dns_rebinding() -> void:
	var s := _server()
	var conn = load("res://script_gdscript/system/VectopenMCPServer.gd")._Conn.new()
	conn.header_text = "POST / HTTP/1.1\r\nHost: evil.com\r\n\r\n"
	assert_str(s._reject_reason(conn)).is_equal("unexpected host")

func test_seguridad_rechazo_token_invalido() -> void:
	var s := _server()
	var conn = load("res://script_gdscript/system/VectopenMCPServer.gd")._Conn.new()
	conn.header_text = "POST / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer wrong\r\n\r\n" % s.get_port()
	assert_str(s._reject_reason(conn)).is_equal("unauthorized")

func test_mcp_set_property_y_undo_redo() -> void:
	var scn: Node2D = load(CANVAS).instantiate()
	add_child(scn)
	get_tree().current_scene = scn
	auto_free(scn)
	await get_tree().process_frame

	var s := _server()
	var r := VectorRectangle.new()
	r.size = Vector2(100, 80)
	var ab = (scn.get_node("manager_script") as ArtboardManager).get_active_artboard()
	ab.add_child(r)
	r.set_doc_position(DVec2.new(50, 50))
	r.set_doc_extent(DVec2.from_v2(r.size))
	await get_tree().process_frame

	var sm = get_node_or_null("/root/SelectionManager")
	if sm:
		sm.set_selection([r])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	# Llamar a tools/call set_property con rotation = 45
	var call_res = await s._dispatch("tools/call", {
		"name": "set_property",
		"arguments": {"prop": "rotation", "value": 45.0}
	})
	assert_bool(call_res.get("isError", true)).is_false()
	assert_float(rad_to_deg(r.get_doc_rotation())).is_equal_approx(45.0, 0.5)

	# Deshacer mediante MCP undo
	var undo_res = await s._dispatch("tools/call", {"name": "undo", "arguments": {}})
	assert_bool(undo_res.get("isError", true)).is_false()
	await get_tree().process_frame
	assert_float(rad_to_deg(r.get_doc_rotation())).is_equal_approx(0.0, 0.5)

	# Rehacer mediante MCP redo
	var redo_res = await s._dispatch("tools/call", {"name": "redo", "arguments": {}})
	assert_bool(redo_res.get("isError", true)).is_false()
	await get_tree().process_frame
	assert_float(rad_to_deg(r.get_doc_rotation())).is_equal_approx(45.0, 0.5)
	HistoryManager.clear()
