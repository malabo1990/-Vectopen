extends Node
## VectopenMCPServer — autoload.
##
## Servidor MCP (Model Context Protocol) EMBEBIDO en la app Vectopen en
## ejecución (distinto del plugin `addons/godot_mcp`, que conecta el EDITOR
## de Godot con un agente vía WebSocket saliente para tareas de desarrollo).
## Este servidor deja que un agente de IA controle/consulte el editor
## vectorial en vivo — seleccionar, crear/editar/borrar figuras, deshacer/
## rehacer, exportar — vía HTTP + JSON-RPC 2.0 (transporte "Streamable HTTP"
## de MCP, sin streaming SSE: cada POST recibe una única respuesta JSON).
##
## Solo escucha en 127.0.0.1 (nunca 0.0.0.0) y solo si el usuario lo activa
## explícitamente (Preferencias > Integraciones, persistido en
## user://vectopen_mcp.cfg). Deliberadamente NO expone ejecución/creación de
## scripts arbitrarios ni edición de otros proyectos — solo las operaciones
## estructuradas listadas en `_build_tools()`.
##
## ENDURECIMIENTO (localhost NO es lo mismo que "seguro"): cualquier pestaña
## de navegador abierta en la máquina puede intentar golpear un puerto local
## (CSRF/"DNS rebinding" contra servicios de loopback — el mismo problema que
## tuvieron Ollama y otras apps de IA locales). Por eso:
##  1. Token compartido obligatorio (Authorization: Bearer <token>), generado
##     al azar y guardado en user://vectopen_mcp.cfg; comparación en tiempo
##     constante. Se muestra en Preferencias para copiarlo al cliente MCP.
##  2. Se rechaza cualquier request con cabecera Origin (un cliente MCP nativo
##     no manda Origin; solo lo manda un navegador) — bloquea fetch() desde
##     una página web maliciosa.
##  3. Se valida Host contra 127.0.0.1:<puerto>/localhost:<puerto> — bloquea
##     DNS rebinding (dominio atacante que resuelve a 127.0.0.1).
##  4. Tope de conexiones concurrentes (429 si se excede) + timeout por
##     conexión ya existente — mitiga agotamiento de recursos.

const CONFIG_PATH := "user://vectopen_mcp.cfg"
const DEFAULT_PORT := 6520
const MAX_BODY_BYTES := 4 * 1024 * 1024
const CONN_TIMEOUT_MS := 15000
const MAX_CONNS := 16
const TOKEN_BYTES := 32
const PROTOCOL_VERSION := "2024-11-05"
const SERVER_NAME := "vectopen"
const SERVER_VERSION := "0.1.1"

class _Conn:
	var peer: StreamPeerTCP
	var raw: PackedByteArray = PackedByteArray()
	var headers_parsed: bool = false
	var header_text: String = ""
	var body_start: int = 0
	var content_length: int = 0
	var started_ms: int = 0
	var method: String = ""

var _server: TCPServer = null
var _port: int = DEFAULT_PORT
var _enabled: bool = false
var _token: String = ""
var _conns: Array[_Conn] = []
var _tools: Dictionary = {}

func _ready() -> void:
	_build_tools()
	_load_config()
	if _enabled:
		start_server(_port)

func _exit_tree() -> void:
	stop_server()

# ------------------------------------------------------------------ config
func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_enabled = bool(cfg.get_value("mcp", "enabled", false))
		_port = int(cfg.get_value("mcp", "port", DEFAULT_PORT))
		_token = String(cfg.get_value("mcp", "token", ""))
	else:
		_enabled = false
		_port = DEFAULT_PORT
	if _token.is_empty():
		_token = _generate_token()
		_save_config()

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # preserva otras secciones si existieran
	cfg.set_value("mcp", "enabled", _enabled)
	cfg.set_value("mcp", "port", _port)
	cfg.set_value("mcp", "token", _token)
	cfg.save(CONFIG_PATH)

func _generate_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(TOKEN_BYTES).hex_encode()

## Invalida el token actual (p.ej. si se sospecha que se filtró) — cualquier
## cliente MCP conectado deberá usar el nuevo token a partir de ahora.
func regenerate_token() -> String:
	_token = _generate_token()
	_save_config()
	return _token

func get_token() -> String:
	return _token

## Llamado por la UI de Preferencias (checkbox "Servidor MCP").
func set_enabled(v: bool) -> void:
	if v == _enabled and (not v or (is_instance_valid(_server) and _server.is_listening())):
		return
	_enabled = v
	_save_config()
	if _enabled:
		start_server(_port)
	else:
		stop_server()

func is_enabled() -> bool:
	return _enabled

func is_listening() -> bool:
	return is_instance_valid(_server) and _server.is_listening()

func get_port() -> int:
	return _port

func set_port(p: int) -> void:
	_port = clampi(p, 1024, 65535)
	_save_config()
	if _enabled:
		stop_server()
		start_server(_port)

# ------------------------------------------------------------------ server lifecycle
func start_server(port: int = _port) -> bool:
	stop_server()
	_server = TCPServer.new()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_warning("VectopenMCPServer: no se pudo escuchar en 127.0.0.1:%d (%s)" % [port, error_string(err)])
		_server = null
		return false
	_port = port
	print("VectopenMCPServer: escuchando en http://127.0.0.1:%d/mcp" % _port)
	return true

func stop_server() -> void:
	for c in _conns:
		if is_instance_valid(c.peer):
			c.peer.disconnect_from_host()
	_conns.clear()
	if is_instance_valid(_server):
		_server.stop()
	_server = null

func _process(_delta: float) -> void:
	if not is_instance_valid(_server) or not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if not peer:
			continue
		if _conns.size() >= MAX_CONNS:
			_write_response(peer, 429, {"error": "too many connections"})
			continue
		var c := _Conn.new()
		c.peer = peer
		c.started_ms = Time.get_ticks_msec()
		_conns.append(c)
	var i := _conns.size() - 1
	while i >= 0:
		_poll_connection(_conns[i])
		i -= 1

func _drop_connection(c: _Conn) -> void:
	if is_instance_valid(c.peer):
		c.peer.disconnect_from_host()
	_conns.erase(c)

func _poll_connection(c: _Conn) -> void:
	var peer: StreamPeerTCP = c.peer
	peer.poll()
	var status := peer.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		_drop_connection(c)
		return
	var avail := peer.get_available_bytes()
	if avail > 0:
		var chunk: Array = peer.get_data(avail)
		if int(chunk[0]) == OK:
			c.raw.append_array(chunk[1])
			if c.raw.size() > MAX_BODY_BYTES:
				_write_response(peer, 413, {"error": "payload too large"})
				_conns.erase(c)
				return
	if not c.headers_parsed:
		var text: String = c.raw.get_string_from_utf8()
		var idx: int = text.find("\r\n\r\n")
		if idx != -1:
			c.header_text = text.substr(0, idx)
			c.headers_parsed = true
			c.body_start = c.header_text.to_utf8_buffer().size() + 4
			c.content_length = _parse_content_length(c.header_text)
			c.method = c.header_text.split(" ")[0] if c.header_text.length() > 0 else ""
	if c.headers_parsed and c.raw.size() >= c.body_start + c.content_length:
		_conns.erase(c)
		_handle_request(c)
		return
	if Time.get_ticks_msec() - c.started_ms > CONN_TIMEOUT_MS:
		_drop_connection(c)

func _parse_content_length(header_text: String) -> int:
	var v := _get_header(header_text, "content-length")
	return int(v) if not v.is_empty() else 0

func _get_header(header_text: String, header_name: String) -> String:
	var prefix := header_name.to_lower() + ":"
	for line in header_text.split("\r\n"):
		if line.to_lower().begins_with(prefix):
			return line.substr(line.find(":") + 1).strip_edges()
	return ""

## Comparación en tiempo constante (evita side-channel por tiempo de respuesta
## al adivinar el token byte a byte).
func _tokens_match(a: String, b: String) -> bool:
	var ab := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	var diff := ab.size() ^ bb.size()
	var n := maxi(ab.size(), bb.size())
	for i in n:
		var x := ab[i] if i < ab.size() else 0
		var y := bb[i] if i < bb.size() else 0
		diff |= x ^ y
	return diff == 0

## Rechaza: (1) cualquier request con cabecera Origin (un cliente MCP nativo
## no la manda; solo un navegador) — corta fetch() desde una página web; (2)
## Host que no sea 127.0.0.1/localhost:<puerto> — corta DNS rebinding; (3)
## falta o mismatch del Bearer token. Devuelve "" si pasa, o un motivo si no.
func _reject_reason(c: _Conn) -> String:
	if not _get_header(c.header_text, "origin").is_empty():
		return "origin not allowed"
	var host := _get_header(c.header_text, "host")
	var expected := ["127.0.0.1:%d" % _port, "localhost:%d" % _port]
	if not (host in expected):
		return "unexpected host"
	var auth := _get_header(c.header_text, "authorization")
	if not _tokens_match(auth, "Bearer " + _token):
		return "unauthorized"
	return ""

## Coroutine: puede usar `await` (p.ej. export_artboard) sin bloquear el resto
## del servidor — Godot la ejecuta como corrutina en segundo plano.
func _handle_request(c: _Conn) -> void:
	var peer: StreamPeerTCP = c.peer
	var reason := _reject_reason(c)
	if not reason.is_empty():
		var status := 401 if reason == "unauthorized" else 403
		_write_response(peer, status, {"error": reason})
		return
	if c.method != "POST":
		_write_response(peer, 200, {"ok": true, "server": SERVER_NAME, "version": SERVER_VERSION})
		return
	var body: String = c.raw.slice(c.body_start, c.body_start + c.content_length).get_string_from_utf8()
	var parsed = JSON.parse_string(body)
	if not (parsed is Dictionary):
		_write_jsonrpc(peer, null, null, {"code": -32700, "message": "Parse error"})
		return
	var msg: Dictionary = parsed
	var id = msg.get("id", null)
	var method: String = String(msg.get("method", ""))
	var params: Dictionary = msg.get("params", {}) if msg.get("params", {}) is Dictionary else {}
	var is_notification := not msg.has("id")

	var result = await _dispatch(method, params)
	if is_notification:
		_write_response(peer, 202, null)
		return
	if result is Dictionary and result.has("_jsonrpc_error"):
		_write_jsonrpc(peer, id, null, result["_jsonrpc_error"])
	else:
		_write_jsonrpc(peer, id, result, null)

func _write_jsonrpc(peer: StreamPeerTCP, id, result, error: Variant) -> void:
	var payload := {"jsonrpc": "2.0"}
	if id != null:
		payload["id"] = id
	if error != null:
		payload["error"] = error
	else:
		payload["result"] = result
	_write_response(peer, 200, payload)

func _write_response(peer: StreamPeerTCP, status: int, payload) -> void:
	if not is_instance_valid(peer):
		return
	var status_text: String = {200: "OK", 202: "Accepted", 401: "Unauthorized", 403: "Forbidden", 413: "Payload Too Large", 429: "Too Many Requests", 500: "Internal Server Error"}.get(status, "OK")
	var body_bytes := PackedByteArray()
	if payload != null:
		body_bytes = JSON.stringify(payload).to_utf8_buffer()
	var header := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, status_text, body_bytes.size()]
	peer.put_data(header.to_utf8_buffer())
	if body_bytes.size() > 0:
		peer.put_data(body_bytes)
	peer.disconnect_from_host()

# ------------------------------------------------------------------ MCP protocol
func _dispatch(method: String, params: Dictionary):
	match method:
		"initialize":
			return {
				"protocolVersion": PROTOCOL_VERSION,
				"capabilities": {"tools": {}},
				"serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
			}
		"notifications/initialized", "ping":
			return {}
		"tools/list":
			var out := []
			for tool_name in _tools:
				var t: Dictionary = _tools[tool_name]
				out.append({"name": tool_name, "description": t.description, "inputSchema": t.input_schema})
			return {"tools": out}
		"tools/call":
			return await _call_tool(params)
		_:
			return {"_jsonrpc_error": {"code": -32601, "message": "Method not found: %s" % method}}

func _call_tool(params: Dictionary):
	var tool_name: String = String(params.get("name", ""))
	var args: Dictionary = params.get("arguments", {}) if params.get("arguments", {}) is Dictionary else {}
	if not _tools.has(tool_name):
		return {"_jsonrpc_error": {"code": -32602, "message": "Unknown tool: %s" % tool_name}}
	var handler: Callable = _tools[tool_name].handler
	var result = await handler.call(args)
	if result is Dictionary and result.has("_tool_error"):
		return {"content": [{"type": "text", "text": String(result["_tool_error"])}], "isError": true}
	return {"content": [{"type": "text", "text": JSON.stringify(result)}], "isError": false}

func _err(msg: String) -> Dictionary:
	return {"_tool_error": msg}

# ------------------------------------------------------------------ scene helpers
func _canvas() -> Node:
	var st := get_tree()
	return st.get_first_node_in_group("_vectopen_canvas") if st else null

func _artboard_manager() -> ArtboardManager:
	return ArtboardManager.find(get_tree()) if get_tree() else null

func _active_artboard(artboard_index: int = -1) -> Node2D:
	var mgr := _artboard_manager()
	if not mgr:
		return null
	if artboard_index >= 0:
		var all := mgr.all_artboards()
		if artboard_index < all.size():
			return all[artboard_index]
		return null
	return mgr.get_active_artboard()

func _selection_manager() -> Node:
	return get_node_or_null("/root/SelectionManager")

func _resolve_nodes(paths: Array) -> Array:
	var out: Array = []
	var root := get_tree().root if get_tree() else null
	for p in paths:
		var n := root.get_node_or_null(String(p)) if root else null
		if n:
			out.append(n)
	return out

# ------------------------------------------------------------------ tool registry
func _build_tools() -> void:
	_tools = {
		"get_project_info": {
			"description": "Devuelve info del proyecto actual: artboards, deshacer/rehacer disponibles, modificado.",
			"input_schema": {"type": "object", "properties": {}},
			"handler": Callable(self, "_tool_get_project_info"),
		},
		"list_artboards": {
			"description": "Lista los artboards del lienzo activo con su índice, nombre y si está activo.",
			"input_schema": {"type": "object", "properties": {}},
			"handler": Callable(self, "_tool_list_artboards"),
		},
		"get_canvas_tree": {
			"description": "Árbol de nodos (figuras) de un artboard: nombre, tipo, posición, path para usar en otras tools.",
			"input_schema": {"type": "object", "properties": {"artboard_index": {"type": "integer", "description": "Índice de artboard (por defecto: el activo)"}}},
			"handler": Callable(self, "_tool_get_canvas_tree"),
		},
		"get_selection": {
			"description": "Devuelve las figuras actualmente seleccionadas en el lienzo.",
			"input_schema": {"type": "object", "properties": {}},
			"handler": Callable(self, "_tool_get_selection"),
		},
		"set_selection": {
			"description": "Selecciona figuras por su node path (obtenido de get_canvas_tree/get_selection).",
			"input_schema": {"type": "object", "properties": {"paths": {"type": "array", "items": {"type": "string"}}}, "required": ["paths"]},
			"handler": Callable(self, "_tool_set_selection"),
		},
		"clear_selection": {
			"description": "Vacía la selección actual.",
			"input_schema": {"type": "object", "properties": {}},
			"handler": Callable(self, "_tool_clear_selection"),
		},
		"get_properties": {
			"description": "Propiedades tipo-Inspector (posición, tamaño, color, etc.) de la selección actual (o de `paths` si se indica).",
			"input_schema": {"type": "object", "properties": {"paths": {"type": "array", "items": {"type": "string"}}}},
			"handler": Callable(self, "_tool_get_properties"),
		},
		"set_property": {
			"description": "Aplica una propiedad (mismo motor que el panel Inspector, con deshacer) a la selección actual o a `paths`. Propiedades: name,pos_x,pos_y,width,height,rotation,fill_color,stroke_color,stroke_width,opacity,corner_radius,visible,text,font_size,...",
			"input_schema": {
				"type": "object",
				"properties": {
					"prop": {"type": "string"},
					"value": {},
					"paths": {"type": "array", "items": {"type": "string"}},
				},
				"required": ["prop", "value"],
			},
			"handler": Callable(self, "_tool_set_property"),
		},
		"create_shape": {
			"description": "Crea un rectángulo o elipse en un artboard. x,y = esquina superior-izquierda en coordenadas LOCALES del artboard.",
			"input_schema": {
				"type": "object",
				"properties": {
					"type": {"type": "string", "enum": ["rectangle", "ellipse"]},
					"x": {"type": "number"}, "y": {"type": "number"},
					"width": {"type": "number"}, "height": {"type": "number"},
					"fill_color": {"type": "string", "description": "hex, p.ej. #e0e0e0"},
					"stroke_color": {"type": "string"},
					"stroke_width": {"type": "number"},
					"artboard_index": {"type": "integer"},
				},
				"required": ["type", "x", "y", "width", "height"],
			},
			"handler": Callable(self, "_tool_create_shape"),
		},
		"delete_selected": {
			"description": "Borra (con deshacer) la selección actual, o las figuras en `paths` si se indica.",
			"input_schema": {"type": "object", "properties": {"paths": {"type": "array", "items": {"type": "string"}}}},
			"handler": Callable(self, "_tool_delete_selected"),
		},
		"undo": {
			"description": "Deshace la última acción.",
			"input_schema": {"type": "object", "properties": {}},
			"handler": Callable(self, "_tool_undo"),
		},
		"redo": {
			"description": "Rehace la última acción deshecha.",
			"input_schema": {"type": "object", "properties": {}},
			"handler": Callable(self, "_tool_redo"),
		},
		"export_artboard": {
			"description": "Exporta un artboard a PNG o SVG en disco (espera a que termine).",
			"input_schema": {
				"type": "object",
				"properties": {
					"format": {"type": "string", "enum": ["png", "svg"]},
					"path": {"type": "string", "description": "Ruta absoluta o user://... de destino"},
					"artboard_index": {"type": "integer"},
					"scale": {"type": "number"},
				},
				"required": ["format", "path"],
			},
			"handler": Callable(self, "_tool_export_artboard"),
		},
	}

# ------------------------------------------------------------------ tool handlers
func _tool_get_project_info(_args: Dictionary) -> Dictionary:
	var mgr := _artboard_manager()
	var hm := get_node_or_null("/root/HistoryManager")
	return {
		"artboard_count": mgr.all_artboards().size() if mgr else 0,
		"can_undo": hm.can_undo() if hm else false,
		"can_redo": hm.can_redo() if hm else false,
		"modified": bool(DataRepository.is_project_modified) if "is_project_modified" in DataRepository else false,
	}

func _tool_list_artboards(_args: Dictionary) -> Dictionary:
	var mgr := _artboard_manager()
	if not mgr:
		return _err("No hay ArtboardManager en la escena (¿está el lienzo abierto?).")
	var active := mgr.get_active_artboard()
	var out := []
	var all := mgr.all_artboards()
	for i in all.size():
		var ab := all[i]
		out.append({
			"index": i, "name": String(ab.name), "active": ab == active,
			"position": {"x": ab.position.x, "y": ab.position.y},
		})
	return {"artboards": out}

func _tool_get_canvas_tree(args: Dictionary) -> Dictionary:
	var idx := int(args.get("artboard_index", -1))
	var ab := _active_artboard(idx)
	if not ab:
		return _err("Artboard no encontrado.")
	var root := get_tree().root
	var out := []
	for child in ab.get_children():
		out.append(_node_summary(child, root))
	return {"artboard": String(ab.name), "children": out}

func _node_summary(n: Node, root: Node) -> Dictionary:
	var d := {"name": String(n.name), "type": n.get_class(), "path": String(root.get_path_to(n))}
	if n is Node2D:
		d["position"] = {"x": n.position.x, "y": n.position.y}
		d["rotation"] = n.rotation
	if "size" in n:
		d["size"] = {"w": n.size.x, "h": n.size.y}
	if "visible" in n:
		d["visible"] = n.visible
	if n.has_meta("shape_type"):
		d["shape_type"] = n.get_meta("shape_type")
	return d

func _tool_get_selection(_args: Dictionary) -> Dictionary:
	var sm := _selection_manager()
	var sel: Array = sm.get_selected() if sm else []
	var root := get_tree().root
	var out := []
	for n in sel:
		out.append(_node_summary(n, root))
	return {"selection": out}

func _tool_set_selection(args: Dictionary) -> Dictionary:
	var sm := _selection_manager()
	if not sm:
		return _err("SelectionManager no disponible.")
	var nodes := _resolve_nodes(args.get("paths", []))
	if nodes.is_empty():
		return _err("Ningún path de `paths` resolvió a un nodo válido.")
	sm.set_selection(nodes)
	return {"selected": nodes.size()}

func _tool_clear_selection(_args: Dictionary) -> Dictionary:
	var sm := _selection_manager()
	if sm:
		sm.clear()
	return {"ok": true}

func _select_if_paths(args: Dictionary) -> void:
	if args.has("paths"):
		var sm := _selection_manager()
		var nodes := _resolve_nodes(args.get("paths", []))
		if sm and not nodes.is_empty():
			sm.set_selection(nodes)

func _tool_get_properties(args: Dictionary) -> Dictionary:
	_select_if_paths(args)
	return InspectorCore.current_props()

func _tool_set_property(args: Dictionary) -> Dictionary:
	_select_if_paths(args)
	if InspectorCore.selection().is_empty():
		return _err("No hay selección: pasa `paths` o llama a set_selection primero.")
	var prop: String = String(args.get("prop", ""))
	if not (prop in InspectorCore.PROPS):
		return _err("Propiedad desconocida: %s. Válidas: %s" % [prop, ", ".join(InspectorCore.PROPS)])
	var value = _coerce_value(prop, args.get("value"))
	InspectorCore.apply(prop, value)
	return {"applied": prop}

func _coerce_value(prop: String, value):
	if prop in ["fill_color", "stroke_color"] and value is String:
		return Color(value)
	if prop in ["pos_x", "pos_y", "width", "height", "rotation", "stroke_width", "opacity",
			"corner_radius", "font_size", "line_spacing", "letter_spacing",
			"corner_tl", "corner_tr", "corner_br", "corner_bl"]:
		return float(value)
	if prop == "visible" or prop == "font_italic":
		return bool(value)
	return value

func _tool_create_shape(args: Dictionary) -> Dictionary:
	var shape_type: String = String(args.get("type", ""))
	if not (shape_type in ["rectangle", "ellipse"]):
		return _err("type debe ser 'rectangle' o 'ellipse'.")
	var idx := int(args.get("artboard_index", -1))
	var ab := _active_artboard(idx)
	if not ab:
		return _err("No hay artboard activo donde crear la figura.")
	var top_left := Vector2(float(args.get("x", 0.0)), float(args.get("y", 0.0)))
	var size := Vector2(float(args.get("width", 100.0)), float(args.get("height", 100.0)))
	if size.x <= 0.0 or size.y <= 0.0:
		return _err("width/height deben ser > 0.")
	var fill: Color = Color(String(args["fill_color"])) if args.has("fill_color") else Color(0.88, 0.88, 0.88, 1.0)
	var stroke: Color = Color(String(args["stroke_color"])) if args.has("stroke_color") else Color(0, 0, 0, 1)
	var stroke_w: float = float(args.get("stroke_width", 1.0))

	var new_shape
	var base_name: String
	if shape_type == "rectangle":
		new_shape = VectorRectangle.new()
		base_name = "Rectángulo"
	else:
		new_shape = VectorCircle.new()
		base_name = "Elipse"
	new_shape.name = NameUtils.unique_child_name(ab, base_name)
	new_shape.set_doc_position(DVec2.from_v2(top_left + size / 2.0))
	new_shape.set_doc_extent(DVec2.from_v2(size))
	new_shape.fill_color = fill
	new_shape.stroke_color = stroke
	new_shape.stroke_width = stroke_w

	var parent := ab
	var do_fn := func() -> void:
		if not new_shape.is_inside_tree():
			parent.add_child(new_shape)
			new_shape.owner = parent
	var undo_fn := func() -> void:
		if is_instance_valid(new_shape) and new_shape.is_inside_tree():
			new_shape.get_parent().remove_child(new_shape)
	var hm := get_node_or_null("/root/HistoryManager")
	if hm:
		hm.register_action("MCP · Crear %s" % base_name)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

	var sm := _selection_manager()
	if sm:
		sm.select(new_shape)
	return {"name": String(new_shape.name), "path": String(get_tree().root.get_path_to(new_shape))}

func _tool_delete_selected(args: Dictionary) -> Dictionary:
	_select_if_paths(args)
	var sm := _selection_manager()
	var sel: Array = sm.get_selected() if sm else []
	if sel.is_empty():
		return _err("No hay selección para borrar.")
	var nodes: Array = sel.duplicate()
	var parents: Array = []
	var indices: Array = []
	for n in nodes:
		parents.append(n.get_parent())
		indices.append(n.get_index())
	var do_fn := func() -> void:
		for n in nodes:
			if is_instance_valid(n) and is_instance_valid(n.get_parent()):
				n.get_parent().remove_child(n)
		sm.clear()
	var undo_fn := func() -> void:
		for i in range(nodes.size()):
			var n = nodes[i]
			var p = parents[i]
			if is_instance_valid(n) and is_instance_valid(p) and not n.is_inside_tree():
				p.add_child(n)
				p.move_child(n, mini(indices[i], p.get_child_count() - 1))
	var hm := get_node_or_null("/root/HistoryManager")
	if hm:
		hm.register_action("MCP · Borrar selección")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
	return {"deleted": nodes.size()}

func _tool_undo(_args: Dictionary) -> Dictionary:
	var hm := get_node_or_null("/root/HistoryManager")
	if hm:
		hm.undo()
		return {"can_undo": hm.can_undo(), "can_redo": hm.can_redo()}
	return _err("HistoryManager no disponible.")

func _tool_redo(_args: Dictionary) -> Dictionary:
	var hm := get_node_or_null("/root/HistoryManager")
	if hm:
		hm.redo()
		return {"can_undo": hm.can_undo(), "can_redo": hm.can_redo()}
	return _err("HistoryManager no disponible.")

func _tool_export_artboard(args: Dictionary):
	var fmt_name: String = String(args.get("format", "")).to_lower()
	if not (fmt_name in ["png", "svg"]):
		return _err("format debe ser 'png' o 'svg'.")
	var path: String = String(args.get("path", ""))
	if path.is_empty():
		return _err("path es obligatorio.")
	var idx := int(args.get("artboard_index", -1))
	var ab := _active_artboard(idx)
	if not ab:
		return _err("No hay artboard activo para exportar.")
	var fmt = ImportExportManager.ExportFormat.PNG if fmt_name == "png" else ImportExportManager.ExportFormat.SVG
	var settings := {}
	if args.has("scale"):
		settings["scale"] = float(args["scale"])

	# Un Dictionary se captura POR REFERENCIA en el lambda (a diferencia de
	# bool/String, que se copian) — es la única forma de que estos callbacks
	# le lleguen de vuelta al bucle de espera de abajo.
	var state := {"done": false, "ok": false, "err_msg": ""}
	var on_ok := func(_f, _p): state.done = true; state.ok = true
	var on_err := func(_f, m): state.done = true; state.err_msg = String(m)
	GlobalEvents.export_finished.connect(on_ok, CONNECT_ONE_SHOT)
	GlobalEvents.export_error.connect(on_err, CONNECT_ONE_SHOT)
	ImportExportManager.export_artboard(ab, fmt, path, settings)
	var tries := 0
	while not state.done and tries < 300:
		await get_tree().process_frame
		tries += 1
	if GlobalEvents.export_finished.is_connected(on_ok):
		GlobalEvents.export_finished.disconnect(on_ok)
	if GlobalEvents.export_error.is_connected(on_err):
		GlobalEvents.export_error.disconnect(on_err)
	if not state.done:
		return _err("Timeout esperando a que terminara la exportación.")
	if not state.ok:
		return _err("Error al exportar: %s" % state.err_msg)
	return {"path": path, "format": fmt_name}
