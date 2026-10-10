# =============================================================================
# RUTA: res://script_gdscript/shapes/SvgImportService.gd
#
# Puente entre el GDExtension nativo (ImageVectorizer / vtracer, ver
# rust/vectopen_vectorizer) y el modelo de datos del editor: crea nodos
# Path2D con VectorPath.gd — el MISMO tipo que producen PenTool/BezierTool —
# para que Inspector, panel de trazos y serializador los traten igual que
# cualquier otro trazo, sin ramas especiales.
#
# LIMITACIÓN CONOCIDA: vtracer puede emitir varios subtrazados dentro de un
# mismo <path> para representar agujeros (vía fill-rule). VectorPath no
# soporta agujeros (un único Curve2D por nodo), así que cada subtrazado se
# crea como su propio VectorPath relleno — un agujero real se ve como una
# forma superpuesta en vez de un hueco recortado. Aceptable para el caso de
# uso principal (logos/ilustración simple); si aparecen fotos con agujeros
# grandes habría que resolverlo con Geometry2D.clip_polygons o extendiendo
# VectorPath para admitir sub-paths con fill-rule.
# =============================================================================
class_name SvgImportService
extends RefCounted

const VectorPathScript := preload("res://script_gdscript/shapes/VectorPath.gd")

## Vectoriza `image_path` (res:// o ruta absoluta de sistema) con el
## GDExtension nativo y crea un VectorPath hijo de `parent` por cada
## subtrazado cerrado. Devuelve los nodos creados (ya añadidos a `parent`).
## Devuelve un array vacío y hace push_error si el GDExtension no cargó o
## vtracer falla.
static func vectorize_into(
	image_path: String,
	parent: Node,
	filter_speckle: int = 4,
	corner_threshold: int = 60,
	color_mode_binary: bool = false
) -> Array[Path2D]:
	var created: Array[Path2D] = []
	if not ClassDB.class_exists("ImageVectorizer"):
		push_error("SvgImportService: ImageVectorizer no está disponible (GDExtension no cargado; revisa vectopen_vectorizer.gdextension)")
		return created

	var abs_input := image_path
	if image_path.begins_with("res://") or image_path.begins_with("user://"):
		abs_input = ProjectSettings.globalize_path(image_path)

	var tmp_svg := ProjectSettings.globalize_path("user://_vectorize_tmp_%d.svg" % Time.get_ticks_usec())

	var vectorizer = ClassDB.instantiate("ImageVectorizer")
	var err: String = vectorizer.vectorize_to_file(abs_input, tmp_svg, filter_speckle, corner_threshold, color_mode_binary)
	if err != "":
		push_error("SvgImportService: vtracer falló al vectorizar '%s': %s" % [image_path, err])
		return created

	var svg_text := FileAccess.get_file_as_string(tmp_svg)
	DirAccess.remove_absolute(tmp_svg)

	return build_from_svg(svg_text, parent)

## Igual que vectorize_into, pero a partir de un texto SVG ya generado —
## no depende del GDExtension ni de disco, útil para tests y para importar
## SVGs externos que ya vengan en el subconjunto de comandos soportado por
## SvgPathParser.
static func build_from_svg(svg_text: String, parent: Node) -> Array[Path2D]:
	var created: Array[Path2D] = []
	for path_data in SvgPathParser.parse_document(svg_text):
		var fill: Color = path_data.fill
		var translate: Vector2 = path_data.translate
		# UN VectorPath por <path>: el primer subtrazado es la curva y el resto
		# van a `subpaths` (par-impar), así los agujeros quedan huecos.
		var vp: Path2D = null
		var extra: Array[Curve2D] = []
		for sub in path_data.subpaths:
			if vp == null:
				vp = _build_vector_path(sub, fill, translate, parent)
			elif (sub.anchors as PackedVector2Array).size() >= 2:
				extra.append(_curve_of(sub))
		if vp:
			if not extra.is_empty():
				vp.set("subpaths", extra)
			created.append(vp)
	return created

static func _curve_of(sub: Dictionary) -> Curve2D:
	var c := Curve2D.new()
	var anchors: PackedVector2Array = sub.anchors
	var ins: PackedVector2Array = sub.ins
	var outs: PackedVector2Array = sub.outs
	for i in anchors.size():
		c.add_point(anchors[i], ins[i], outs[i])
	return c

static func _build_vector_path(sub: Dictionary, fill: Color, translate: Vector2, parent: Node) -> Path2D:
	var anchors: PackedVector2Array = sub.anchors
	if anchors.size() < 2:
		return null

	var path := Path2D.new()
	path.set_script(VectorPathScript)
	path.name = NameUtils.unique_child_name(parent, "Vectorizado")
	path.position = translate

	var curve := Curve2D.new()
	var ins: PackedVector2Array = sub.ins
	var outs: PackedVector2Array = sub.outs
	for i in range(anchors.size()):
		curve.add_point(anchors[i], ins[i], outs[i])

	path.curve = curve
	path.closed = bool(sub.closed)
	path.fill_color = fill
	path.stroke_width = 0.0

	parent.add_child(path)
	return path
