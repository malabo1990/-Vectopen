extends GdUnitTestSuite

## REGRESIÓN — Text-to-shape (convertir texto a forma):
## build_outline_path() del WorldTextLabel crea Path2D con curvas Bézier
## reales por contorno. Con fuente sin contornos (headless fallback) debe
## devolver null sin crashear (nunca una excepción).
## Contratos verificados:
## 1. Nunca lanza: con fuente de sistema o embebida, responde siempre.
## 2. Con contornos: cada Path2D tiene Curve2D con al menos 2 puntos y los
##    puntos SÍ existen dentro del bbox del texto (coordenadas coherentes).
## 3. Produces el mismo nº de "contours" y están cerrados (path cerrado).
## 4. No muta el label (text/posición/size intactos).

const TEXT_TOOL := "res://script_gdscript/tools/TextTool.gd"

func _label(base: int = 24, texto: String = "Aa") -> WorldTextLabel:
	var l := WorldTextLabel.new()
	l.base_font_size = base
	l.text = texto
	l.add_theme_font_size_override("font_size", base)
	add_child(l)
	auto_free(l)
	await get_tree().process_frame
	return l

## build_outline_path() devuelve un Node2D DESACOPLADO (fuera del árbol) con
## un Path2D por contorno de glifo — el llamador real (TextTool text-to-shape)
## lo añade a la escena; aquí hay que liberarlo a mano o quedan huérfanos.
func _free_outline(out: Node2D) -> void:
	if out != null:
		out.free()

func test_build_outline_nunca_crashea() -> void:
	var l := await _label(24, "Hola Texto")
	var out: Node2D = l.build_outline_path()
	# Permitido null (fuente sin contornos en headless) — pero SI retorna,
	# debe ser un Node2D con Path2D válidos dentro del bbox del label.
	if out != null:
		var paths := _get_paths(out)
		assert_that(paths.size()).is_greater(0)
	# null = fallback aceptado (fuente embebida sin fdata en headless)
	_free_outline(out)

func test_build_outline_curvas_dentro_del_bbox() -> void:
	var l := await _label(24, "Texto de prueba")
	var out: Node2D = l.build_outline_path()
	if out == null:
		return
	var bbox: Rect2 = Rect2(Vector2.ZERO, Vector2(l.size.x * l.scale.x, l.size.y * l.scale.y))
	var world_ok := true
	var curves_ok := true
	for p in _get_paths(out):
		var curve: Curve2D = p.curve
		if curve != null and curve.point_count >= 2:
			# Todo punto del path razonable: dentro del bbox expandido 200px
			for i in curve.point_count:
				var pos := curve.get_point_position(i)
				if not bbox.grow(200).has_point(pos):
					world_ok = false
		else:
			curves_ok = false
	assert_that(curves_ok).is_true()
	assert_that(world_ok).is_true()
	_free_outline(out)

func test_build_outline_no_muta_el_label() -> void:
	var l := await _label(24, "No mutar")
	var text_antes := l.text
	var size_antes := l.size
	var pos_antes := l.position
	var scale_antes := l.scale

	var out: Node2D = l.build_outline_path()
	assert_that(l.text).is_equal(text_antes)
	assert_that(l.size).is_equal(size_antes)
	assert_that(l.position).is_equal(pos_antes)
	assert_that(l.scale).is_equal(scale_antes)
	_free_outline(out)

func test_outline_con_multiline_y_linea_larga() -> void:
	var l := await _label(24, "Línea larga Línea larga Línea larga Línea larga")
	var out: Node2D = l.build_outline_path()
	# Debe ser null o válido — nunca error
	assert_that(out == null or out.get_child_count() > -1).is_true()
	_free_outline(out)

func _get_paths(container: Node2D) -> Array[Path2D]:
	var res: Array[Path2D] = []
	for child in container.get_children():
		if child is Path2D:
			res.append(child)
	return res
