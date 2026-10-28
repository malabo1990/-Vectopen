# =============================================================================
# VECTOPEN — MINIATURAS DE CAPAS (vista previa como Affinity / Photoshop)
# RUTA: res://script_gdscript/ui/panels/layer_thumbs.gd
#
# Cada capa (también las de dentro de grupos) se reconstruye con el
# serializador del proyecto —igual que Artboard.render_to_image— y se pinta
# en UNA imagen-cuadrícula junto con hasta CELLS_PER_PASS capas más: un solo
# render para muchas miniaturas (con el león, 521 capas en ~9 pasadas).
# Caché por capa; `invalidate(n)` la vuelve a pedir cuando cambia.
# =============================================================================
extends Node

signal thumb_ready(node: Node, tex: Texture2D)

const COLS := 10
const CELLS_PER_PASS := 80
const PAD := 3.0
## Se pinta a SS× el tamaño final y se reduce con buen filtro (y MSAA): sin
## esto los contornos finos salían punteados al encoger.
const SS := 2

var cell := 40              # px de cada miniatura (se cambia con set_size)
var _cache: Dictionary = {} # node -> Texture2D
var _queue: Array = []
var _busy := false
var _Ser = null

func _ready() -> void:
	_Ser = load("res://scripts/canvas/canvas_serializer.gd")

func set_size(px: int) -> void:
	if px != cell:
		cell = px
		_cache.clear()

func clear() -> void:
	_cache.clear()
	_queue.clear()

func get_cached(n: Node) -> Texture2D:
	return _cache.get(n)

func request(n: Node) -> void:
	if not is_instance_valid(n) or _cache.has(n) or n in _queue:
		return
	_queue.append(n)
	if not _busy:
		_run.call_deferred()

func invalidate(n: Node) -> void:
	_cache.erase(n)
	request(n)

func _run() -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		_queue.clear()
		return
	_busy = true
	while not _queue.is_empty():
		var batch: Array = []
		while not _queue.is_empty() and batch.size() < CELLS_PER_PASS:
			var n = _queue.pop_front()
			if is_instance_valid(n) and n.is_inside_tree():
				batch.append(n)
		if not batch.is_empty():
			await _render_batch(batch)
	_busy = false

func _render_batch(batch: Array) -> void:
	var rows := int(ceil(float(batch.size()) / COLS))
	var big := cell * SS
	var vp := SubViewport.new()
	vp.size = Vector2i(COLS * big, rows * big)
	vp.transparent_bg = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := Node2D.new()
	vp.add_child(root)
	for i in batch.size():
		var n: Node2D = batch[i]
		var e: Dictionary = _Ser._serialize_element(n)
		if e.is_empty():
			continue
		var holder := Node2D.new()
		root.add_child(holder)
		_Ser.instantiate_elements(holder, [e])
		var b := _local_bounds(n)
		var pad := PAD * SS
		var inner := float(big) - pad * 2.0
		var k := inner / maxf(maxf(b.size.x, b.size.y), 0.001)
		var origin := Vector2((i % COLS) * big, (i / COLS) * big)
		holder.scale = Vector2(k, k)
		holder.position = origin + Vector2(pad, pad) + (Vector2(inner, inner) - b.size * k) / 2.0 - b.position * k
	add_child(vp)
	for f in 3:   # texto nativo y efectos necesitan un fotograma más
		await get_tree().process_frame
		if not is_inside_tree():
			vp.queue_free()
			return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	for i in batch.size():
		var n = batch[i]
		if not is_instance_valid(n):
			continue
		var cut := img.get_region(Rect2i((i % COLS) * big, (i / COLS) * big, big, big))
		cut.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		var tex := ImageTexture.create_from_image(_on_card(cut))
		_cache[n] = tex
		thumb_ready.emit(n, tex)

## Fondo de cuadros de transparencia con borde (como Affinity / Photoshop):
## se distingue del panel en tema claro y oscuro, y una figura blanca o
## negra se ve igual.
func _on_card(cut: Image) -> Image:
	var card := Image.create(cut.get_width(), cut.get_height(), false, Image.FORMAT_RGBA8)
	var w := card.get_width()
	var h := card.get_height()
	var sq := maxi(3, w / 8)
	for y in h:
		for x in w:
			var odd := ((x / sq) + (y / sq)) % 2 == 1
			card.set_pixel(x, y, Color(0.84, 0.84, 0.86) if odd else Color(0.98, 0.98, 0.99))
	var edge := Color(0.45, 0.45, 0.5)
	for x in w:
		card.set_pixel(x, 0, edge)
		card.set_pixel(x, h - 1, edge)
	for y in h:
		card.set_pixel(0, y, edge)
		card.set_pixel(w - 1, y, edge)
	card.blend_rect(cut, Rect2i(Vector2i.ZERO, cut.get_size()), Vector2i.ZERO)
	return card

## Caja de `n` (y de sus hijos) en el espacio de su PADRE: es el espacio en el
## que queda la copia serializada dentro del contenedor.
func _local_bounds(n: Node2D) -> Rect2:
	var parent := n.get_parent() as Node2D
	var acc := [false, Rect2()]
	_accum(n, parent, acc)
	if not acc[0]:
		return Rect2(n.position - Vector2(50, 50), Vector2(100, 100))
	var r: Rect2 = acc[1]
	return r.grow(maxf(r.size.x, r.size.y) * 0.02)

func _accum(n: Node, parent: Node2D, acc: Array) -> void:
	if not (n is Node2D):
		return
	var pts := PackedVector2Array()
	if n.has_method("get_evaluated_geometry"):
		for ring in n.get_evaluated_geometry():
			pts.append_array(ring)
	elif n is Line2D:
		pts = (n as Line2D).points
	elif n is Sprite2D and (n as Sprite2D).texture:
		var rr := (n as Sprite2D).get_rect()
		pts = PackedVector2Array([rr.position, rr.end, Vector2(rr.position.x, rr.end.y), Vector2(rr.end.x, rr.position.y)])
	elif n.has_meta("shape_type") and String(n.get_meta("shape_type")).begins_with("text"):
		# Tamaño REAL del texto pintado (la caja guardada suele ser mucho
		# más ancha que las letras y la miniatura salía casi vacía).
		var sz := Vector2(float(n.get_meta("width", 200.0)), float(n.get_meta("height", 40.0)))
		for cn in ["VectorRichText", "DisplayLabel"]:
			var c := n.get_node_or_null(cn) as Control
			if c and c.has_method("get_minimum_size") and c.get_minimum_size().x > 1.0:
				sz = c.get_minimum_size()
				break
		pts = PackedVector2Array([Vector2.ZERO, sz])
	for p in pts:
		var g: Vector2 = (n as Node2D).to_global(p)
		var lp: Vector2 = parent.to_local(g) if parent else g
		if not acc[0]:
			acc[1] = Rect2(lp, Vector2.ZERO)
			acc[0] = true
		else:
			acc[1] = (acc[1] as Rect2).expand(lp)
	for c in n.get_children():
		_accum(c, parent, acc)
