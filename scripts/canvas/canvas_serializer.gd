# ==========================================
# RUTA: res://scripts/canvas/canvas_serializer.gd
# Serialización del CONTENIDO DIBUJADO del lienzo (la fuente de verdad son los
# nodos de escena, no el modelo de datos de ProjectManager — que las
# herramientas nunca poblaban, ver test SaveLoadRoundtrip).
#
# serialize_container(container) -> Dictionary   (artboards + figuras sueltas)
# rebuild_container(container, data)             (borra y reconstruye)
#
# Cubre: VectorCircle/Rectangle/Polygon/Path, Line2D (pincel), Polygon2D,
# los contenedores de texto (meta shape_type = text_title / text_paragraph),
# grupos anidados, imágenes (res:// o PNG embebido en base64), y el estado
# visual de CanvasItem: material/shader, clip_children (clipping/máscara),
# light_mask, modulate/self_modulate, z_index y metas de efectos CPU.
#
# No usa `class_name` a propósito: se referencia con preload() desde
# ProjectManager y los tests, para no depender del cache de clases global.
# ==========================================
extends RefCounted

const V := 2  # v2: + material/shader/clip/máscara/metas de efecto (lee v1)

# ─────────────────────────────── .vtc = contenedor plano direccionable (VTC2)
## Un ZIP resultó inservible a escala: ZIPReader.read_file(nombre) escanea el
## directorio central de forma lineal → releer N páginas al guardar es O(N²)
## (medido: 3,7 s con 1000 páginas) y no hay API para evitarlo.
##
## Formato VTC2:
##   "VTC2"                 4 bytes
##   uint32  manifest_len   (little-endian)
##   manifest_len bytes     manifest JSON (gzip) — cabeceras, SIN figuras
##   [región de datos]      chunks por artboard (cada uno JSON gzip), concatenados
##
## manifest.artboards[i] = {name, pos, size, off, len, rlen}
##   off  = offset del chunk DENTRO de la región de datos
##   len  = bytes comprimidos, rlen = bytes sin comprimir
## Leer una página = 1 seek + 1 get_buffer + 1 decompress → O(1).
## Guardar = copiar byte a byte (ya comprimidos) los chunks de páginas intactas.
const _MAGIC := "VTC2"
const _COMP := FileAccess.COMPRESSION_GZIP

## FileAccess de lectura cacheado por documento (evita reabrir el .vtc en cada
## despertar de página).
static var _rd_file: FileAccess = null
static var _rd_path: String = ""
static var _rd_data_start: int = 0

static func _reader_for(path: String) -> FileAccess:
	if _rd_file != null and _rd_file.is_open() and _rd_path == path:
		return _rd_file
	close_reader_cache()
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_buffer(4).get_string_from_ascii() != _MAGIC:
		f.close()
		return null
	_rd_data_start = 8 + f.get_32()   # magic(4) + len(4) + manifest
	_rd_file = f
	_rd_path = path
	return f

## Cierra el handle de lectura cacheado. Llamar al cambiar de documento
## (load/new/close) y ANTES de reescribir el .vtc (no truncar con un handle
## de lectura abierto en Windows).
static func close_reader_cache() -> void:
	if _rd_file != null and _rd_file.is_open():
		_rd_file.close()
	_rd_file = null
	_rd_path = ""
	_rd_data_start = 0

## Lee y descomprime el chunk de un artboard (dado su header del manifest). O(1).
static func read_vtc_chunk_raw(path: String, off: int, clen: int, rlen: int) -> PackedByteArray:
	var f := _reader_for(path)
	if f == null or clen <= 0:
		return PackedByteArray()
	f.seek(_rd_data_start + off)
	var comp := f.get_buffer(clen)
	if comp.size() != clen:
		return PackedByteArray()
	return comp if rlen <= 0 else comp.decompress(rlen, _COMP)

## Bytes COMPRIMIDOS crudos de un chunk (para copiarlo tal cual al guardar).
static func read_vtc_chunk_compressed(path: String, off: int, clen: int) -> PackedByteArray:
	var f := _reader_for(path)
	if f == null or clen <= 0:
		return PackedByteArray()
	f.seek(_rd_data_start + off)
	var comp := f.get_buffer(clen)
	return comp if comp.size() == clen else PackedByteArray()

# ─────────────────────────────────────────────────────────── serializar
static func serialize_container(container: Node) -> Dictionary:
	var out := {"v": V, "artboards": [], "loose": []}
	if not is_instance_valid(container):
		return out
	for child in container.get_children():
		if child is ArtboardEditor:
			out["artboards"].append(_serialize_artboard(child))
		elif child is Node2D:
			var e := _serialize_element(child)
			if not e.is_empty():
				out["loose"].append(e)
	return out


static func _serialize_artboard(ab: ArtboardEditor) -> Dictionary:
	var elements: Array
	if ab.is_dormant:
		elements = ab.dormant_content()               # datos puros (dormido)
	elif ab.has_pending_wake():
		elements = serialize_elements(ab)              # instanciadas + en cola
		elements.append_array(ab.pending_wake_data())
	else:
		elements = serialize_elements(ab)
	return {
		"name": String(ab.name),
		"pos": [ab.position.x, ab.position.y],
		"size": [ab.artboard_size.x, ab.artboard_size.y],
		"elements": elements,
	}


## PÚBLICO: serializa todas las figuras dibujables hijas de `node` (ignora
## título/auxiliares). Usado por _serialize_artboard y por ArtboardEditor.sleep().
static func serialize_elements(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child.name == "ArtboardTitle" or child.name == "DisplayLabel" \
				or child.name == "TitleEdit" or child.name == "Contorno_Stroke":
			continue
		if child is Node2D:
			var e := _serialize_element(child)
			if not e.is_empty():
				out.append(e)
	return out


## PÚBLICO: instancia y añade a `parent` las figuras del array serializado.
static func instantiate_elements(parent: Node, elements: Array) -> void:
	for e_d in elements:
		var n := _element_from(e_d)
		if n:
			parent.add_child(n)
			_apply_transform(n, e_d)


static func _serialize_element(node: Node2D) -> Dictionary:
	var base := {
		"name": String(node.name),
		"pos": [node.position.x, node.position.y],
		"rot": node.rotation,
		"scale": [node.scale.x, node.scale.y],
		"visible": node.visible,
	}
	_add_visual_state(base, node)   # material/shader, clip, máscara, metas de efecto

	# Hijos ANIDADOS (Node2D). Cualquier figura/texto puede contener otras
	# figuras dentro (anidado profundo, o una máscara de recorte donde la
	# figura de arriba recorta al resto). Antes solo la rama "group" guardaba
	# hijos → el anidado se perdía al guardar/recargar.
	var _kids: Array = []
	for _ch in node.get_children():
		if _ch is Node2D:
			var _ce := _serialize_element(_ch)
			if not _ce.is_empty():
				_kids.append(_ce)
	if not _kids.is_empty():
		base["children"] = _kids

	# Texto (contenedor Node2D con meta)
	if node.has_meta("shape_type") and String(node.get_meta("shape_type")).begins_with("text_"):
		base["kind"] = "text"
		base["text_kind"] = String(node.get_meta("shape_type"))
		base["text"] = String(node.get_meta("text", ""))
		base["font_size"] = int(node.get_meta("font_size", 24))
		if node.has_meta("line_spacing"): base["line_spacing"] = int(node.get_meta("line_spacing"))
		if node.has_meta("letter_spacing"): base["letter_spacing"] = int(node.get_meta("letter_spacing"))
		if node.has_meta("font_family"): base["font_family"] = String(node.get_meta("font_family"))
		if node.has_meta("font_weight"): base["font_weight"] = int(node.get_meta("font_weight"))
		if node.has_meta("font_italic"): base["font_italic"] = bool(node.get_meta("font_italic"))
		if node.has_meta("text_color"): base["text_color"] = _col(node.get_meta("text_color"))
		if node.has_meta("text_outline_color"): base["text_outline_color"] = _col(node.get_meta("text_outline_color"))
		if node.has_meta("text_outline"): base["text_outline"] = int(node.get_meta("text_outline"))
		if node.has_meta("text_align"): base["text_align"] = String(node.get_meta("text_align"))
		if node.has_meta("width"): base["width"] = float(node.get_meta("width"))
		if node.has_meta("height"): base["height"] = float(node.get_meta("height"))
		return base

	if node is VectorCircle:
		base["kind"] = "circle"
		base["size"] = [node.size.x, node.size.y]
		_add_style(base, node)
		return base
	if node is VectorRectangle:
		base["kind"] = "rect"
		base["size"] = [node.size.x, node.size.y]
		base["corner"] = node.corner_radius
		var rr: Vector4 = node.get_corner_radii()
		if not (rr.x == rr.y and rr.y == rr.z and rr.z == rr.w):
			base["corners"] = [rr.x, rr.y, rr.z, rr.w]   # tl, tr, br, bl
		_add_style(base, node)
		return base
	if node is VectorPolygon:
		base["kind"] = "poly"
		base["verts"] = _pv2_to_arr(node.vertices)
		base["closed"] = node.closed
		_add_style(base, node)
		return base
	if node is Path2D and node.curve:
		base["kind"] = "path"
		var pts := PackedVector2Array()
		var ins := PackedVector2Array()
		var outs := PackedVector2Array()
		for i in node.curve.point_count:
			pts.append(node.curve.get_point_position(i))
			ins.append(node.curve.get_point_in(i))
			outs.append(node.curve.get_point_out(i))
		base["pts"] = _pv2_to_arr(pts)
		base["in"] = _pv2_to_arr(ins)
		base["out"] = _pv2_to_arr(outs)
		base["path_closed"] = bool(node.get_meta("is_closed", false))
		if "fill_color" in node:
			base["fill"] = _col(node.get("fill_color"))
		if "stroke_color" in node:
			base["stroke"] = _col(node.get("stroke_color"))
		if "stroke_width" in node:
			base["stroke_w"] = node.get("stroke_width")
		return base
	if node is Line2D:
		base["kind"] = "line"
		base["pts"] = _pv2_to_arr(node.points)
		base["width"] = node.width
		base["color"] = _col(node.default_color)
		if node.gradient is Gradient and node.gradient.get_point_count() >= 2:
			base["fill_grad"] = _grad_to_dict(node.gradient, 0, 0.0)
		return base
	if node is Polygon2D:
		base["kind"] = "polygon2d"
		base["verts"] = _pv2_to_arr(node.polygon)
		base["color"] = _col(node.color)
		return base
	if node is Sprite2D:
		base["kind"] = "image"
		base["centered"] = node.centered
		var tex: Texture2D = node.texture
		if tex and not tex.resource_path.is_empty() and tex.resource_path.begins_with("res://"):
			base["tex_path"] = tex.resource_path
		elif tex:
			var img := tex.get_image()
			if img:
				base["tex_png_b64"] = Marshalls.raw_to_base64(img.save_png_to_buffer())
		return base
	# GRUPO: cualquier Node2D con hijos Node2D que no sea un tipo conocido.
	if base.has("children"):
		base["kind"] = "group"
		return base
	return {}   # tipo no soportado todavía


static func _add_style(d: Dictionary, s: VectorShape) -> void:
	d["fill"] = _col(s.fill_color)
	d["stroke"] = _col(s.stroke_color)
	d["stroke_w"] = s.stroke_width
	if s.has_gradient_fill():
		d["fill_grad"] = _grad_to_dict(s.fill_gradient, int(s.fill_gradient_type), float(s.fill_gradient_angle))
	# Efectos (best-effort): array de Effect (Resource) o de dicts {type,params}.
	var fx := []
	for e in s.effects:
		if e is Object and "effect_type" in e:
			fx.append({"type": int(e.effect_type), "params": e.params if "params" in e else {},
				"enabled": e.enabled if "enabled" in e else true})
		elif e is Dictionary:
			fx.append(e)
	if not fx.is_empty():
		d["fx"] = fx


static func _grad_to_dict(g: Gradient, gtype: int, angle: float) -> Dictionary:
	var stops := []
	for i in g.get_point_count():
		stops.append([g.get_offset(i), _col(g.get_color(i))])
	return {"type": gtype, "angle": angle, "stops": stops}

static func _grad_from_dict(gd: Dictionary) -> Gradient:
	var g := Gradient.new()
	var stops: Array = gd.get("stops", [[0.0, [0, 0, 0, 1]], [1.0, [1, 1, 1, 1]]])
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return _to_col(s[1])))
	return g


# ─────────────────────────────────────────── .vtc = contenedor plano (VTC2)
## Escribe un .vtc: cabecera + manifest (gzip) + un chunk (JSON gzip) por
## artboard, concatenados. Al abrir solo se lee el manifest; cada página se
## trae con un seek directo. Guardar copia byte a byte los chunks (ya
## comprimidos) de las páginas que nunca se tocaron → O(páginas cambiadas).
static func write_vtc(path: String, container: Node, header_extra: Dictionary = {}) -> bool:
	if not is_instance_valid(container):
		return false
	# PASO 1: reunir los bytes COMPRIMIDOS de cada chunk (todavía sin tocar el
	# archivo destino, por si guardamos sobre el mismo path).
	var arts: Array = []          # {name,pos,size} por artboard
	var comp_chunks: Array = []   # PackedByteArray comprimido, en orden
	var raw_lens: Array = []      # tamaño sin comprimir de cada chunk
	var loose: Array = []
	for child in container.get_children():
		if child is ArtboardEditor:
			var pair := _artboard_chunk_compressed(child)   # [comp_bytes, raw_len]
			arts.append({
				"name": String(child.name),
				"pos": [child.position.x, child.position.y],
				"size": [child.artboard_size.x, child.artboard_size.y],
			})
			comp_chunks.append(pair[0])
			raw_lens.append(pair[1])
		elif child is Node2D:
			var e := _serialize_element(child)
			if not e.is_empty():
				loose.append(e)
	close_reader_cache()   # soltar el handle de lectura antes de truncar

	# Manifest con los offsets ya calculados (dentro de la región de datos).
	var manifest := header_extra.duplicate(true)
	manifest["v"] = V
	manifest["loose"] = loose
	var headers: Array = []
	var off := 0
	for i in arts.size():
		var h: Dictionary = arts[i]
		h["off"] = off
		h["len"] = comp_chunks[i].size()
		h["rlen"] = raw_lens[i]
		headers.append(h)
		off += comp_chunks[i].size()
	manifest["artboards"] = headers

	var mbytes := JSON.stringify(manifest).to_utf8_buffer().compress(_COMP)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(_MAGIC.to_ascii_buffer())
	f.store_32(mbytes.size())
	f.store_buffer(mbytes)
	for c in comp_chunks:
		f.store_buffer(c)
	f.close()
	return true


## [bytes comprimidos, tamaño sin comprimir] del chunk de un artboard.
## Página intacta y perezosa → se copia el chunk comprimido tal cual (O(1)).
static func _artboard_chunk_compressed(ab: ArtboardEditor) -> Array:
	if ab.is_dormant and ab.has_method("get_lazy_source"):
		var src: Dictionary = ab.get_lazy_source()
		if not src.is_empty() and src.get("len", 0) > 0:
			var comp := read_vtc_chunk_compressed(src.get("vtc", ""), src.get("off", 0), src.get("len", 0))
			if comp.size() == int(src.get("len", 0)):
				return [comp, int(src.get("rlen", 0))]   # copia cruda
	var elements: Array
	if ab.is_dormant:
		elements = ab.dormant_content()
	elif ab.has_pending_wake():
		elements = serialize_elements(ab)
		elements.append_array(ab.pending_wake_data())
	else:
		elements = serialize_elements(ab)
	var raw := JSON.stringify(elements).to_utf8_buffer()
	return [raw.compress(_COMP), raw.size()]


## Lee SOLO el manifest de un .vtc. {} si no es un VTC2 válido.
static func read_vtc_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_buffer(4).get_string_from_ascii() != _MAGIC:
		f.close()
		return {}
	var mlen := f.get_32()
	var mbytes := f.get_buffer(mlen)
	f.close()
	var json := mbytes.decompress_dynamic(-1, _COMP).get_string_from_utf8()
	var m = JSON.parse_string(json)
	return m if m is Dictionary else {}


## Contenido (Array de figuras) del chunk de un artboard, dado su header del
## manifest. Para tests / herramientas.
static func read_vtc_chunk(path: String, header: Dictionary) -> Array:
	var raw := read_vtc_chunk_raw(path, header.get("off", 0), header.get("len", 0), header.get("rlen", 0))
	if raw.is_empty():
		return []
	var arr = JSON.parse_string(raw.get_string_from_utf8())
	return arr if arr is Array else []


## Reconstruye el contenedor desde un .vtc: artboards DORMIDOS con fuente
## perezosa (su chunk no se lee hasta despertar). Devuelve el manifest.
static func rebuild_from_vtc(container: Node, path: String) -> Dictionary:
	var manifest := read_vtc_manifest(path)
	if manifest.is_empty():
		return {}
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	for ab_h in manifest.get("artboards", []):
		var ab := ArtboardEditor.new()
		ab.name = ab_h.get("name", "Artboard")
		ab.artboard_size = _arr_to_v2(ab_h.get("size", [794, 1123]))
		container.add_child(ab)
		ab.position = _arr_to_v2(ab_h.get("pos", [0, 0]))
		ab.set_lazy_source(path, {
			"off": int(ab_h.get("off", 0)),
			"len": int(ab_h.get("len", 0)),
			"rlen": int(ab_h.get("rlen", 0)),
		})
	# materializa el primero (a la vista)
	for ch in container.get_children():
		if ch is ArtboardEditor and ch.is_dormant:
			ch.wake()
			break
	for e_d in manifest.get("loose", []):
		var n := _element_from(e_d)
		if n:
			container.add_child(n)
			_apply_transform(n, e_d)
	return manifest


# ─────────────────────────────────────────────────────────── reconstruir
## `materialize_all = false` → los artboards se crean DORMIDOS (sus figuras
## quedan como datos, sin instanciar). El ArtboardStreamer despierta luego los
## visibles. Carga O(páginas) en vez de O(figuras).
static func rebuild_container(container: Node, data: Dictionary, materialize_all: bool = true) -> void:
	if not is_instance_valid(container) or data.is_empty():
		return
	# Detach inmediato (no solo queue_free) para que no choquen los nombres.
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

	for ab_d in data.get("artboards", []):
		var ab := ArtboardEditor.new()
		ab.name = ab_d.get("name", "Artboard")
		ab.artboard_size = _arr_to_v2(ab_d.get("size", [794, 1123]))
		container.add_child(ab)
		ab.position = _arr_to_v2(ab_d.get("pos", [0, 0]))
		var elements: Array = ab_d.get("elements", [])
		if materialize_all:
			instantiate_elements(ab, elements)
		else:
			ab.set_dormant_content(elements)   # dormido

	# En carga diferida, materializa YA el primer artboard (que suele estar a la
	# vista) para que no aparezca vacío mientras el streamer arranca.
	if not materialize_all:
		for ch in container.get_children():
			if ch is ArtboardEditor and ch.is_dormant:
				ch.wake()
				break

	for e_d in data.get("loose", []):
		var n := _element_from(e_d)
		if n:
			container.add_child(n)
			_apply_transform(n, e_d)


static func _apply_transform(n: Node2D, d: Dictionary) -> void:
	n.position = _arr_to_v2(d.get("pos", [0, 0]))
	n.rotation = d.get("rot", 0.0)
	n.scale = _arr_to_v2(d.get("scale", [1, 1]))
	n.visible = d.get("visible", true)
	_read_visual_state(n, d)
	# Hijos ANIDADOS (figura dentro de figura / texto, máscara de recorte).
	# Los añade DESPUÉS de crear el nodo, recursivamente.
	for cd in d.get("children", []):
		var cn := _element_from(cd)
		if cn:
			n.add_child(cn)
			_apply_transform(cn, cd)
	# Máscara stencil de grupo/texto: el contenido ya se reconstruyó anidado bajo
	# el nodo-máscara (rama "children" recursiva). Aquí solo restauramos las
	# metas para que el panel de capas sepa que la máscara está activa.
	if d.get("clip_mask", false):
		n.set_meta("clip_mask", true)
		n.set_meta("clip_mask_target", String(d.get("clip_mask_target", "")))


# ─────────────────────────────────── estado visual (shaders / clipping / máscaras)
## Serializa lo que NO es geometría ni estilo de relleno: material/shader,
## clip_children (clipping y máscara de recorte), light_mask, modulate y las
## metas que el sistema de efectos CPU (Effect.gd) escribe sobre el nodo.
static func _add_visual_state(d: Dictionary, node: CanvasItem) -> void:
	if node.modulate != Color.WHITE:
		d["modulate"] = _col(node.modulate)
	if node.self_modulate != Color.WHITE:
		d["self_modulate"] = _col(node.self_modulate)
	if node.z_index != 0:
		d["z"] = node.z_index
	if not node.z_as_relative:
		d["z_abs"] = true
	# CLIPPING / MÁSCARA de recorte (un grupo con clip_children recorta a sus hijos)
	if "clip_children" in node and int(node.clip_children) != 0:
		d["clip"] = int(node.clip_children)
	# MÁSCARA STENCIL de grupo/texto: el contenido se movió bajo un nodo-máscara.
	if node.has_meta("clip_mask") and bool(node.get_meta("clip_mask")):
		d["clip_mask"] = true
		d["clip_mask_target"] = String(node.get_meta("clip_mask_target", ""))
	# MÁSCARAS de luz / capa de visibilidad
	if node.light_mask != 1:
		d["light_mask"] = node.light_mask
	if "visibility_layer" in node and node.visibility_layer != 1:
		d["vis_layer"] = node.visibility_layer
	# SHADER / material
	var mat := node.material
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var md := {"mat": "shader", "params": {}}
		if sm.shader:
			var sp := sm.shader.resource_path
			if not sp.is_empty() and sp.begins_with("res://"):
				md["shader_path"] = sp
			else:
				md["shader_code"] = sm.shader.code
			for u in sm.shader.get_shader_uniform_list():
				var enc = _enc_param(sm.get_shader_parameter(u["name"]))
				if enc != null:
					md["params"][u["name"]] = enc
		d["material"] = md
	elif mat is CanvasItemMaterial:
		var cm := mat as CanvasItemMaterial
		d["material"] = {"mat": "canvas", "blend": int(cm.blend_mode), "light": int(cm.light_mode)}
	# METAS de efectos CPU (Effect.gd las escribe al aplicar sombra / glow)
	var fx_meta := {}
	for mk in ["shadow_enabled", "shadow_color", "shadow_offset", "glow_enabled", "glow_color"]:
		if node.has_meta(mk):
			var enc = _enc_param(node.get_meta(mk))
			if enc != null:
				fx_meta[mk] = enc
	if not fx_meta.is_empty():
		d["fx_meta"] = fx_meta


static func _read_visual_state(node: CanvasItem, d: Dictionary) -> void:
	if d.has("modulate"):
		node.modulate = _to_col(d["modulate"])
	if d.has("self_modulate"):
		node.self_modulate = _to_col(d["self_modulate"])
	if d.has("z"):
		node.z_index = int(d["z"])
	if d.get("z_abs", false):
		node.z_as_relative = false
	if d.has("clip") and "clip_children" in node:
		node.clip_children = int(d["clip"]) as CanvasItem.ClipChildrenMode
	if d.has("light_mask"):
		node.light_mask = int(d["light_mask"])
	if d.has("vis_layer") and "visibility_layer" in node:
		node.visibility_layer = int(d["vis_layer"])
	if d.has("material") and d["material"] is Dictionary:
		_apply_material(node, d["material"])
	if d.has("fx_meta") and d["fx_meta"] is Dictionary:
		for mk in d["fx_meta"]:
			node.set_meta(mk, _dec_param(d["fx_meta"][mk]))


static func _apply_material(node: CanvasItem, md: Dictionary) -> void:
	match String(md.get("mat", "")):
		"shader":
			var sm := ShaderMaterial.new()
			var sh: Shader = null
			if md.has("shader_path"):
				var r = load(md["shader_path"])
				if r is Shader:
					sh = r
			if sh == null and md.has("shader_code"):
				sh = Shader.new()
				sh.code = String(md["shader_code"])
			if sh:
				sm.shader = sh
				for pn in md.get("params", {}):
					sm.set_shader_parameter(pn, _dec_param(md["params"][pn]))
				node.material = sm
		"canvas":
			var cm := CanvasItemMaterial.new()
			cm.blend_mode = int(md.get("blend", 0)) as CanvasItemMaterial.BlendMode
			cm.light_mode = int(md.get("light", 0)) as CanvasItemMaterial.LightMode
			node.material = cm


## Codifica un Variant a algo JSON-seguro y etiquetado por tipo (o null si el
## tipo no se puede serializar: Texture2D, RID, etc. → se omite).
static func _enc_param(v):
	if v is Color:
		return {"__t": "col", "v": [v.r, v.g, v.b, v.a]}
	if v is Vector2:
		return {"__t": "v2", "v": [v.x, v.y]}
	if v is Vector3:
		return {"__t": "v3", "v": [v.x, v.y, v.z]}
	if v is bool or v is int or v is float or v is String or v is StringName:
		return v
	if v is Array:
		var o := []
		for e in v:
			o.append(_enc_param(e))
		return o
	return null


static func _dec_param(v):
	if v is Dictionary and v.has("__t"):
		var a = v.get("v", [])
		match String(v["__t"]):
			"col":
				return Color(a[0], a[1], a[2], a[3]) if a.size() >= 4 else Color.WHITE
			"v2":
				return Vector2(a[0], a[1]) if a.size() >= 2 else Vector2.ZERO
			"v3":
				return Vector3(a[0], a[1], a[2]) if a.size() >= 3 else Vector3.ZERO
	if v is Array:
		var o := []
		for e in v:
			o.append(_dec_param(e))
		return o
	return v


static func _element_from(d: Dictionary) -> Node2D:
	var kind := String(d.get("kind", ""))
	match kind:
		"circle":
			var c := VectorCircle.new()
			c.size = _arr_to_v2(d.get("size", [40, 40]))
			_read_style(c, d)
			c.name = d.get("name", "Circulo")
			return c
		"rect":
			var r := VectorRectangle.new()
			r.size = _arr_to_v2(d.get("size", [40, 40]))
			r.corner_radius = d.get("corner", 0.0)
			if d.has("corners") and d["corners"] is Array and d["corners"].size() == 4:
				var cc: Array = d["corners"]
				r.set_corner_radii(Vector4(cc[0], cc[1], cc[2], cc[3]))
			_read_style(r, d)
			r.name = d.get("name", "Rectangulo")
			return r
		"poly":
			var p := VectorPolygon.new()
			p.vertices = _arr_to_pv2(d.get("verts", []))
			p.closed = d.get("closed", true)
			_read_style(p, d)
			p.name = d.get("name", "Poligono")
			return p
		"path":
			var vp := Path2D.new()
			vp.set_script(load("res://script_gdscript/shapes/VectorPath.gd"))
			var curve := Curve2D.new()
			var pts := _arr_to_pv2(d.get("pts", []))
			var ins := _arr_to_pv2(d.get("in", []))
			var outs := _arr_to_pv2(d.get("out", []))
			for i in pts.size():
				curve.add_point(pts[i],
					ins[i] if i < ins.size() else Vector2.ZERO,
					outs[i] if i < outs.size() else Vector2.ZERO)
			vp.curve = curve
			vp.set_meta("is_closed", d.get("path_closed", false))
			if d.has("fill"): vp.set("fill_color", _to_col(d["fill"]))
			if d.has("stroke"): vp.set("stroke_color", _to_col(d["stroke"]))
			if d.has("stroke_w"): vp.set("stroke_width", float(d["stroke_w"]))
			vp.set("closed", bool(d.get("path_closed", false)))
			vp.name = d.get("name", "Trazo")
			return vp
		"line":
			var l := Line2D.new()
			l.points = _arr_to_pv2(d.get("pts", []))
			l.width = d.get("width", 3.0)
			l.default_color = _to_col(d.get("color", [0, 0, 0, 1]))
			l.joint_mode = Line2D.LINE_JOINT_ROUND
			l.begin_cap_mode = Line2D.LINE_CAP_ROUND
			l.end_cap_mode = Line2D.LINE_CAP_ROUND
			l.antialiased = false
			if d.has("fill_grad") and d["fill_grad"] is Dictionary:
				l.gradient = _grad_from_dict(d["fill_grad"])
			l.name = d.get("name", "Trazo")
			return l
		"polygon2d":
			var pg := Polygon2D.new()
			pg.polygon = _arr_to_pv2(d.get("verts", []))
			pg.color = _to_col(d.get("color", [1, 1, 1, 1]))
			pg.name = d.get("name", "Poligono")
			return pg
		"text":
			return _text_from(d)
		"image":
			return _image_from(d)
		"group":
			var g := Node2D.new()
			g.name = d.get("name", "Grupo")
			g.set_meta("shape_type", "group")   # se re-detecta como grupo aunque quede sin hijos-capa
			# los hijos los añade _apply_transform (rama "children")
			return g
	return null


static func _image_from(d: Dictionary) -> Node2D:
	var sp := Sprite2D.new()
	sp.name = d.get("name", "Imagen")
	sp.centered = d.get("centered", true)
	if d.has("tex_path"):
		var t = load(d["tex_path"])
		if t is Texture2D:
			sp.texture = t
	elif d.has("tex_png_b64"):
		var img := Image.new()
		if img.load_png_from_buffer(Marshalls.base64_to_raw(d["tex_png_b64"])) == OK:
			sp.texture = ImageTexture.create_from_image(img)
	return sp


static func _text_from(d: Dictionary) -> Node2D:
	var cont := Node2D.new()
	cont.name = d.get("name", "Texto")
	cont.set_meta("shape_type", d.get("text_kind", "text_title"))
	cont.set_meta("text", d.get("text", ""))
	cont.set_meta("font_size", int(d.get("font_size", 24)))
	if d.has("line_spacing"): cont.set_meta("line_spacing", int(d["line_spacing"]))
	if d.has("letter_spacing"): cont.set_meta("letter_spacing", int(d["letter_spacing"]))
	if d.has("font_family"): cont.set_meta("font_family", String(d["font_family"]))
	if d.has("font_weight"): cont.set_meta("font_weight", int(d["font_weight"]))
	if d.has("font_italic"): cont.set_meta("font_italic", bool(d["font_italic"]))
	if d.has("text_color"): cont.set_meta("text_color", _to_col(d["text_color"]))
	if d.has("text_outline_color"): cont.set_meta("text_outline_color", _to_col(d["text_outline_color"]))
	if d.has("text_outline"): cont.set_meta("text_outline", int(d["text_outline"]))
	if d.has("text_align"): cont.set_meta("text_align", String(d["text_align"]))
	if d.has("width"): cont.set_meta("width", d["width"])
	if d.has("height"): cont.set_meta("height", d["height"])
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = int(d.get("font_size", 24))
	label.text = d.get("text", "")
	label.add_theme_color_override("font_color", _to_col(d.get("text_color", [0, 0, 0, 1])))
	label.add_theme_font_size_override("font_size", int(d.get("font_size", 24)))
	if d.has("line_spacing"):
		label.add_theme_constant_override("line_spacing", int(d["line_spacing"]))
	if d.has("text_outline_color"):
		label.add_theme_color_override("font_outline_color", _to_col(d["text_outline_color"]))
	if d.has("text_outline"):
		label.add_theme_constant_override("outline_size", int(d["text_outline"]))
	if d.has("text_align") and "horizontal_alignment" in label:
		label.horizontal_alignment = {
			"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER,
			"right": HORIZONTAL_ALIGNMENT_RIGHT, "fill": HORIZONTAL_ALIGNMENT_FILL,
		}.get(String(d["text_align"]), HORIZONTAL_ALIGNMENT_LEFT)
	cont.add_child(label)
	# Resuelve la familia guardada (SO o bundled) + tracking vía FontCore.
	if (d.has("font_family") or d.has("font_weight") or d.has("font_italic") or d.has("letter_spacing")) \
			and label.has_method("apply_font_from_meta"):
		label.apply_font_from_meta()
	return cont


static func _read_style(s: VectorShape, d: Dictionary) -> void:
	s.fill_color = _to_col(d.get("fill", [1, 1, 1, 1]))
	s.stroke_color = _to_col(d.get("stroke", [0, 0, 0, 1]))
	s.stroke_width = d.get("stroke_w", 2.0)
	if d.has("fill_grad") and d["fill_grad"] is Dictionary:
		s.fill_gradient_type = int(d["fill_grad"].get("type", 0))
		s.fill_gradient_angle = float(d["fill_grad"].get("angle", 0.0))
		s.fill_gradient = _grad_from_dict(d["fill_grad"])
	# Efectos (best-effort): reconstruye recursos Effect desde los datos.
	if d.has("fx") and ClassDB.class_exists("Resource"):
		s.effects = []
		var EffectClass = load("res://script_gdscript/system/Effect.gd")
		for fd in d["fx"]:
			if EffectClass and fd is Dictionary:
				var e = EffectClass.new()
				if "effect_type" in e: e.effect_type = int(fd.get("type", 0))
				if "params" in e: e.params = fd.get("params", {})
				if "enabled" in e: e.enabled = fd.get("enabled", true)
				s.effects.append(e)


# ─────────────────────────────────────────────────────────── helpers
static func _col(c: Color) -> Array: return [c.r, c.g, c.b, c.a]
static func _to_col(a) -> Color:
	if a is Color: return a
	if a is Array and a.size() >= 4: return Color(a[0], a[1], a[2], a[3])
	return Color.WHITE
static func _arr_to_v2(a) -> Vector2:
	if a is Vector2: return a
	if a is Array and a.size() >= 2: return Vector2(a[0], a[1])
	return Vector2.ZERO
static func _pv2_to_arr(pv: PackedVector2Array) -> Array:
	var out := []
	for p in pv: out.append([p.x, p.y])
	return out
static func _arr_to_pv2(a) -> PackedVector2Array:
	var out := PackedVector2Array()
	if a is PackedVector2Array: return a
	if a is Array:
		for p in a:
			if p is Array and p.size() >= 2:
				out.append(Vector2(p[0], p[1]))
			elif p is Vector2:
				out.append(p)
	return out
