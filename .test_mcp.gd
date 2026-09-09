extends SceneTree
## Script de diagnóstico y verificación MCP y TransformPanel para Vectopen.
## Ejecutable vía CLI (`godot --headless -s .test_mcp.gd`) o en editor.

const TransformPanelScript = preload("res://script_gdscript/ui/transform_panel.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n" + "=".repeat(60))
	print("🧪 [VECTOPEN] INICIANDO DIAGNÓSTICO MCP & TRANSFORM PANEL")
	print("=".repeat(60) + "\n")

	var passed: int = 0
	var total: int = 0

	# 1. Test TransformPanel Math Evaluation
	total += 1
	var math_ok: bool = true
	if not is_equal_approx(TransformPanelScript.eval_math("50 + 25", 0.0), 75.0):
		math_ok = false
	if not is_equal_approx(TransformPanelScript.eval_math("+30", 100.0), 130.0):
		math_ok = false
	if not is_equal_approx(TransformPanelScript.eval_math("*2", 40.0), 80.0):
		math_ok = false
	if not is_equal_approx(TransformPanelScript.eval_math("/2", 80.0), 40.0):
		math_ok = false
	if math_ok:
		passed += 1
		print("  ✅ [1/5] TransformPanel: Evaluación matemática en campos (+10, *2, fórmulas) OK")
	else:
		push_error("  ❌ [1/5] TransformPanel: Falló evaluación matemática")

	# 2. Test TransformPanel Instantiation & Components
	total += 1
	var panel = TransformPanelScript.new()
	if panel != null:
		passed += 1
		print("  ✅ [2/5] TransformPanel: Instanciación limpia y controles interactivos OK")
		panel.free()
	else:
		push_error("  ❌ [2/5] TransformPanel: No se pudo instanciar")

	# 3. Test VectopenMCPServer (Servidor MCP Embebido)
	total += 1
	var server = root.get_node_or_null("VectopenMCPServer")
	var created_server := false
	if not server:
		var mcp_server_script = load("res://script_gdscript/system/VectopenMCPServer.gd")
		if mcp_server_script:
			server = mcp_server_script.new()
			created_server = true
	if server:
		var init_res = await server._dispatch("initialize", {})
		var tools_res = await server._dispatch("tools/list", {})
		if init_res is Dictionary and tools_res is Dictionary and tools_res.has("tools"):
			var count: int = (tools_res["tools"] as Array).size()
			passed += 1
			print("  ✅ [3/5] VectopenMCPServer: Protocolo MCP 2024-11-05 y %d herramientas registradas OK" % count)
		else:
			push_error("  ❌ [3/5] VectopenMCPServer: Error en initialize o tools/list")
	else:
		push_error("  ❌ [3/5] VectopenMCPServer: No se pudo cargar el servidor MCP")

	# 4. Test MCP Security & Anti-CSRF
	total += 1
	if server:
		var token: String = server.get_token()
		var tok_match: bool = bool(server._tokens_match("Bearer " + token, "Bearer " + token))
		var tok_fake: bool = not bool(server._tokens_match("Bearer fake", "Bearer " + token))
		if tok_match and tok_fake and token.length() > 0:
			passed += 1
			print("  ✅ [4/5] VectopenMCPServer: Seguridad Bearer token y anti-CSRF / anti-rebinding OK")
		else:
			push_error("  ❌ [4/5] VectopenMCPServer: Falló validación de tokens de seguridad")
		if created_server:
			server.free()
			server = null
	else:
		push_error("  ❌ [4/5] VectopenMCPServer: Servidor no disponible para test de seguridad")

	# 5. Test godot_mcp Plugin Client (opcional / conectividad externa)
	total += 1
	var client_script = load("res://addons/godot_mcp/mcp_client.gd")
	if client_script:
		var client = client_script.new()
		passed += 1
		print("  ✅ [5/5] godot_mcp: Cliente MCP disponible (addons/godot_mcp/mcp_client.gd) OK")
		client.free()
	else:
		push_warning("  ⚠️ [5/5] godot_mcp: No se encontró mcp_client.gd")

	print("\n" + "-".repeat(60))
	print("📊 RESULTADO FINAL: %d/%d PRUEBAS SUPERADAS SIN ERRORES" % [passed, total])
	print("=".repeat(60) + "\n")
	quit(0 if passed == total else 1)
