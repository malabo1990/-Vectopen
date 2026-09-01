extends Node

## ImportExportManager
## Handles export and import of artboards to various formats
## 
## Features:
## - Export caching system to optimize repeated exports
## - Error handling for unsupported formats
## - Progress notifications via GlobalEvents
## 
## Supported Export Formats:
## - SVG: Vector graphics export (optimized with estándar math calculations)
## - PDF: Portable Document Format (basic vector support)
## - PNG: Raster image export
## - JPEG: Raster image export
## - JPEG XL: Next-gen raster format
## - WEBP: Modern raster format with transparency
## - EPS: Encapsulated PostScript (import only)
## - TSCN: Godot 4 scene format
## - SCN: Godot 3 scene format
## - VOP: Vectopen proprietary format
## - JSON: Project data export
## 
## Unsupported Export Formats (will emit export_error):
## - AI: formato vectorial (.ai) format
## - DXF: AutoCAD Drawing Exchange Format
## 
## Supported Import Formats:
## - SVG: Vector graphics import (strong math calculations, estándar)
## - PNG, JPEG: Raster image import (converted to Sprite2D, not vectorized)
## - EPS: Encapsulated PostScript (import only)
## - TSCN, SCN: Godot scene formats
## - VOP: Vectopen proprietary format
## 
## Unsupported Import Formats (will emit import_error):
## - AI: formato vectorial (.ai) format
## - PDF: Portable Document Format
## - DXF: AutoCAD Drawing Exchange Format
## - JPEG XL, WEBP: Import not yet implemented


enum ExportFormat {
	SVG,
	PDF,
	PNG,
	JPEG,
	JPEG_XL,
	WEBP,
	EPS,
	TSCN,
	SCN,
	VOP,
	JSON
}

enum ImportFormat {
	SVG,
	EPS,
	TSCN,
	SCN,
	VOP,
	PNG,
	JPEG
}

# Configuración de exportación
var cache_enabled: bool = true
var default_pdf_page_size: Vector2 = Vector2(612, 792)
var default_png_scale: float = 2.0

# Formato y configuración seleccionados en el panel (FormatConfigPanel)
var current_format: String = "SVG"
var current_export_config: Dictionary = {}

func _ready() -> void:
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnArchivos", _on_btn_archivos_pressed)
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnRecuperar", _on_btn_recuperar_pressed)
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnNuevo", _on_btn_nuevo_pressed)
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnReciente", _on_btn_reciente_pressed)
	var format_config := get_node_or_null("HBoxContainer/FileFlowLayout/ExportPanel")
	if format_config and format_config.has_signal("format_selected"):
		format_config.format_selected.connect(_on_format_selected_changed)
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/SaveHBox/BtnSave", _on_btn_save_pressed)
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/SaveHBox/BtnSaveAs", _on_btn_save_as_pressed)

func _get_and_connect_button(path: String, callback: Callable) -> void:
	var btn: Button = get_node_or_null(path)
	if btn:
		btn.pressed.connect(callback)

func _on_btn_archivos_pressed() -> void:
	_set_file_view("files")

func _on_btn_recuperar_pressed() -> void:
	_set_file_view("recover")

func _on_btn_reciente_pressed() -> void:
	_set_file_view("recent")

func _set_file_view(mode: String) -> void:
	var ffl := get_node_or_null("HBoxContainer/FileFlowLayout")
	if ffl and ffl.has_method("set_view"):
		ffl.set_view(mode)

func _on_open_file_selected(path: String) -> void:
	if SaveManager:
		SaveManager.open(path)
	RecentFilesManager.add_file(path)

func _on_btn_nuevo_pressed() -> void:
	if SaveManager:
		SaveManager.new_project()

func _on_btn_save_pressed() -> void:
	if SaveManager:
		SaveManager.save()

func _on_btn_save_as_pressed() -> void:
	if SaveManager:
		SaveManager.save_as()

func _on_format_selected_changed(format: String, config: Dictionary) -> void:
	current_format = format
	current_export_config = config

func export_artboard(artboard: Node, format: ExportFormat, path: String, settings: Dictionary = {}) -> void:
	var format_name = ExportFormat.keys()[format]
	GlobalEvents.export_started.emit(format_name, path)
	
	# Verificar si el formato es soportado
	var unsupported_formats = ["AI", "DXF"]
	if format_name in unsupported_formats:
		var error_msg = "Export format '%s' is not yet supported. Currently supported: SVG, PDF, PNG, JPEG, JPEG XL, WEBP, EPS, TSCN, SCN, VOP, JSON." % format_name
		push_error(error_msg)
		GlobalEvents.emit_safe("export_error", format_name, error_msg)
		return
	
	# Preparar datos para la caché
	var export_data = {
		"artboard_id": artboard.get_instance_id(),
		"artboard_state": _get_artboard_state(artboard),
		"format": format_name,
		"settings": settings.duplicate(true),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Intentar recuperar de la caché si está habilitada
	var cached_result = null
	if cache_enabled and ExportCache:
		cached_result = ExportCache.retrieve(format_name, export_data)
		if cached_result:
			# Guardar el resultado cacheado
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file:
				if cached_result is PackedByteArray:
					file.store_buffer(cached_result)
				else:
					file.store_string(cached_result)
				file.close()
				GlobalEvents.export_finished.emit(format_name, path)
				return
	
	# Si no está en caché, procesar la exportación
	match format:
		ExportFormat.SVG:
			_export_svg(artboard, path, settings)
		ExportFormat.PDF:
			_export_pdf(artboard, path, settings)
		ExportFormat.PNG:
			await _export_png(artboard, path, settings)
		ExportFormat.JPEG:
			_export_jpeg(artboard, path, settings)
		ExportFormat.JPEG_XL:
			_export_jpegxl(artboard, path, settings)
		ExportFormat.WEBP:
			_export_webp(artboard, path, settings)
		ExportFormat.EPS:
			_export_eps(artboard, path, settings)
		ExportFormat.TSCN:
			_export_tscn(artboard, path, settings)
		ExportFormat.SCN:
			_export_scn(artboard, path, settings)
		ExportFormat.VOP:
			_export_vop(artboard, path, settings)
		ExportFormat.JSON:
			_export_json(artboard, path, settings)
		_:
			var error_msg = "Export format '%s' is not yet supported." % format_name
			push_error(error_msg)
			GlobalEvents.emit_safe("export_error", format_name, error_msg)

func import_file(file_path: String, format: ImportFormat, target_artboard: Node) -> void:
	GlobalEvents.import_started.emit(file_path)

	match format:
		ImportFormat.SVG:
			_import_svg(file_path, target_artboard)
		ImportFormat.EPS:
			_import_eps(file_path, target_artboard)
		ImportFormat.TSCN, ImportFormat.SCN:
			_import_godot_scene(file_path, target_artboard)
		ImportFormat.VOP:
			_import_vop(file_path, target_artboard)
		ImportFormat.PNG, ImportFormat.JPEG:
			_vectorize_image(file_path, target_artboard)
		_:
			var fmt_name = ImportFormat.keys()[format]
			var error_msg = "Import format '%s' is not yet supported. Currently supported: SVG, EPS, TSCN, SCN, VOP, PNG, JPEG." % fmt_name
			push_error(error_msg)
			GlobalEvents.emit_safe("import_error", fmt_name, error_msg)

func _export_svg(artboard: Node, path: String, _settings: Dictionary):
	# Prefixing settings with _ to ignore unused warning
	var _svg_content = artboard.export_to_svg(path)
	GlobalEvents.export_finished.emit("svg", path)

func _export_pdf(artboard: Node, path: String, _settings: Dictionary) -> void:
	var shapes = _collect_shapes(artboard)
	var content = _render_pdf_content(shapes, artboard)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Cannot open %s for PDF export" % path)
		GlobalEvents.emit_safe("export_error", "PDF", "Cannot open file for writing")
		return
	file.store_buffer(content)
	file.close()
	GlobalEvents.export_finished.emit("pdf", path)

func _collect_shapes(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		var c = child as Node
		if c and c.has_method("get_bounds"):
			out.append(c)
		out.append_array(_collect_shapes(c))
	return out

func _render_pdf_content(shapes: Array[Node], artboard: Node) -> PackedByteArray:
	var text := "%PDF-1.4\n"
	var objects: Array[String] = []
	var content_body := ""
	
	# Get artboard size for MediaBox
	var artboard_size = Vector2(612, 792)  # Default A4 in points (72 dpi)
	if artboard.has("artboard_size"):
		# Convert pixels to points (assuming 96 dpi for artboard, PDF uses 72 dpi)
		var pixel_size = artboard.get("artboard_size")
		artboard_size = Vector2(pixel_size.x * 72.0 / 96.0, pixel_size.y * 72.0 / 96.0)
	
	# Collect all unique colors and fonts
	var colors_used: Dictionary = {}
	var fonts_used: Dictionary = {"Helvetica": true}
	
	for shape in shapes:
		content_body += _shape_to_pdf(shape, colors_used, fonts_used)

	if content_body.is_empty():
		content_body = "BT /F1 12 Tf (Empty Artboard) Tj ET\n"

	# Build PDF objects
	objects.append("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
	objects.append("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
	
	# Build resources dictionary
	var resources := "<< /Font"
	var font_index = 1
	for font_name in fonts_used:
		resources += " /F%d /%s" % [font_index, font_name]
		font_index += 1
	resources += " >>"
	
	# Add color space if we have colors
	if colors_used.size() > 0:
		resources = resources.replace(">>", " /ColorSpace << /Cs1 /DeviceRGB >> >>")
	
	# Page object with proper MediaBox
	objects.append("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R /Resources %s >>\nendobj\n" % [artboard_size.x, artboard_size.y, resources])
	
	# Content stream
	var stream_data := "q\n" + content_body + "Q\n"
	var encoded = stream_data.to_utf8_buffer()
	
	objects.append("4 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n" % [encoded.size(), stream_data])
	
	# Font objects
	font_index = 1
	for font_name in fonts_used:
		objects.append("5 %d 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /%s >>\nendobj\n" % [font_index - 1, font_name])
		font_index += 1

	# Build cross-reference table
	var offsets: Array[int] = []
	for obj in objects:
		offsets.append(text.length())
		text += obj

	var xref_offset = text.length()
	text += "xref\n0 %d\n0000000000 65535 f \n" % (objects.size() + 1)
	for off in offsets:
		text += "%010d 00000 n \n" % off
	text += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [objects.size() + 1, xref_offset]

	return text.to_utf8_buffer()


func _shape_to_pdf(shape: Node, colors_used: Dictionary, _fonts_used: Dictionary) -> String:
	var content := ""
	var cls = shape.get_class()
	
	# Get position, scale, rotation
	var position = shape.position if shape.has("position") else Vector2.ZERO
	var _scale = shape.scale if shape.has("scale") else Vector2.ONE
	var _rotation = shape.rotation if shape.has("rotation") else 0.0
	
	# Get color and style properties
	var stroke_color = Color.BLACK
	var fill_color = Color.TRANSPARENT
	var stroke_width = 1.0
	var is_filled = false
	
	if shape.has("stroke_color"):
		stroke_color = shape.get("stroke_color")
	if shape.has("fill_color"):
		fill_color = shape.get("fill_color")
	if shape.has("stroke_width"):
		stroke_width = shape.get("stroke_width")
	if shape.has("is_filled"):
		is_filled = shape.get("is_filled")
	
	# Add colors to used colors
	if not colors_used.has(stroke_color.to_html()):
		colors_used[stroke_color.to_html()] = true
	if not colors_used.has(fill_color.to_html()):
		colors_used[fill_color.to_html()] = true
	
	# Set PDF color
	var pdf_stroke_color = _color_to_pdf(stroke_color)
	var pdf_fill_color = _color_to_pdf(fill_color)
	
	# Handle different shape types
	if cls == "Path2D":
		var curve = shape.get(&"curve") as Curve2D if shape.get(&"curve") else null
		if curve and curve.point_count >= 2:
			var pts = curve.get_baked_points()
			if pts.size() >= 2:
				content += "%s %s %s rg\n" % [pdf_fill_color.r, pdf_fill_color.g, pdf_fill_color.b]
				content += "%s %s %s RG\n" % [pdf_stroke_color.r, pdf_stroke_color.g, pdf_stroke_color.b]
				content += "%f w\n" % stroke_width
				content += "%f %f m\n" % [pts[0].x, pts[0].y]
				for i in range(1, pts.size()):
					content += "%f %f l\n" % [pts[i].x, pts[i].y]
				if is_filled:
					content += "b\n"  # Fill and stroke
				else:
					content += "S\n"  # Stroke only
			
	elif cls == "Polygon2D":
		var pts = shape.get("polygon") if shape.has("polygon") else []
		if pts.size() >= 3:
			content += "%s %s %s rg\n" % [pdf_fill_color.r, pdf_fill_color.g, pdf_fill_color.b]
			content += "%s %s %s RG\n" % [pdf_stroke_color.r, pdf_stroke_color.g, pdf_stroke_color.b]
			content += "%f w\n" % stroke_width
			content += "%f %f m\n" % [position.x + pts[0].x, position.y + pts[0].y]
			for i in range(1, pts.size()):
				content += "%f %f l\n" % [position.x + pts[i].x, position.y + pts[i].y]
			content += "h\n"  # Close path
			if is_filled:
				content += "b\n"
			else:
				content += "S\n"
		
	elif cls == "Line2D":
		var pts = shape.get("points") if shape.has("points") else []
		if pts.size() >= 2:
			content += "%s %s %s RG\n" % [pdf_stroke_color.r, pdf_stroke_color.g, pdf_stroke_color.b]
			content += "%f w\n" % (shape.get("width") if shape.has("width") else stroke_width)
			content += "%f %f m\n" % [position.x + pts[0].x, position.y + pts[0].y]
			for i in range(1, pts.size()):
				content += "%f %f l\n" % [position.x + pts[i].x, position.y + pts[i].y]
			content += "S\n"
		
	elif cls == "ColorRect" or cls.find("Rect") >= 0:
		var rect = shape.get("rect") if shape.has("rect") else Rect2(Vector2.ZERO, shape.get("size") if shape.has("size") else Vector2(100, 100))
		if rect.size.x > 0 and rect.size.y > 0:
			content += "%s %s %s rg\n" % [pdf_fill_color.r, pdf_fill_color.g, pdf_fill_color.b]
			content += "%f %f %f %f re\n" % [position.x + rect.position.x, position.y + rect.position.y, rect.size.x, rect.size.y]
			content += "f\n"
		
	elif cls == "Sprite2D":
		# For imported raster images (not vector, but we include them)
		var texture = shape.get("texture")
		if texture:
			# This is a simplified approach - real PDF image embedding would need more work
			content += "% BT /F1 12 Tf (Raster Image: %s) Tj ET\n" % [shape.name]
		
	elif shape.has_method("to_svg"):
		# Try to parse SVG output and convert to PDF
		var svg = shape.to_svg()
		content += _svg_path_to_pdf(svg)
	
	return content


func _color_to_pdf(color: Color) -> Color:
	# Convert Godot Color (0-1 range) to PDF color (0-1 range)
	# PDF uses RGB, same as Godot
	return Color(color.r, color.g, color.b)


func _svg_path_to_pdf(svg: String) -> String:
	# Simple conversion from SVG path to PDF path
	# This is a basic implementation - would need more work for full SVG support
	var pdf_content := ""
	
	# Look for path data in SVG
	var path_match = svg.find("d=\"")
	if path_match >= 0:
		var start = svg.find("d=\"") + 3
		var end = svg.find("\"", start)
		if end > start:
			var path_data = svg.substr(start, end - start)
			# Basic conversion - would need proper parsing for full support
			pdf_content += "q\n"
			pdf_content += "0 0 0 RG\n"  # Black stroke
			pdf_content += "1 w\n"  # Stroke width
			pdf_content += path_data.replace("M", "m").replace("L", "l").replace("Z", "h") + " S\n"
			pdf_content += "Q\n"
	
	return pdf_content

func _export_png(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	await artboard.export_to_png(path, scale)
	GlobalEvents.export_finished.emit("png", path)

func _export_jpeg(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	var quality = settings.get("quality", 90)
	await artboard.export_to_jpeg(path, scale, quality)
	GlobalEvents.export_finished.emit("jpeg", path)

func _export_jpegxl(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	var quality = settings.get("quality", 90)
	await artboard.export_to_jpegxl(path, scale, quality)
	GlobalEvents.export_finished.emit("jpeg_xl", path)

func _export_webp(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	var quality = settings.get("quality", 90)
	await artboard.export_to_webp(path, scale, quality)
	GlobalEvents.export_finished.emit("webp", path)

func _export_eps(artboard: Node, path: String, _settings: Dictionary) -> void:
	# EPS export - wrapper around SVG with EPS header
	var svg_content = artboard.export_to_svg_string()
	var eps_content = _svg_to_eps(svg_content)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(eps_content)
		file.close()
		GlobalEvents.export_finished.emit("eps", path)

func _svg_to_eps(svg: String) -> String:
	# Convert SVG to EPS format
	return "%%EPSF-3.0\n" + svg + "\n%%EOF\n"

func _export_tscn(artboard: Node, path: String, _settings: Dictionary) -> void:
	# Export as Godot 4 scene
	var scene_data = {
		"resource_path": path,
		"format_version": 3,
		"root_node": artboard.get_class(),
		"node_data": _get_node_data(artboard),
		"metadata": {
			"exported_at": Time.get_unix_time_from_system(),
			"vectopen_version": "1.0"
		}
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(scene_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("tscn", path)

func _export_scn(artboard: Node, path: String, _settings: Dictionary) -> void:
	# Export as Godot 3 scene (legacy format)
	var scene_data = {
		"resource_path": path,
		"format_version": 2,
		"root_node": artboard.get_class(),
		"node_data": _get_node_data(artboard),
		"metadata": {
			"exported_at": Time.get_unix_time_from_system(),
			"vectopen_version": "1.0"
		}
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(scene_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("scn", path)

func _export_vop(artboard: Node, path: String, _settings: Dictionary) -> void:
	# Export as Vectopen proprietary format
	var vop_data = {
		"version": "1.0",
		"artboard": {
			"name": artboard.name,
			"size": artboard.get("artboard_size") if artboard.has("artboard_size") else Vector2(800, 600),
			"layers": _get_layer_data(artboard),
			"metadata": {
				"created_at": Time.get_unix_time_from_system(),
				"modified_at": Time.get_unix_time_from_system()
			}
		}
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(vop_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("vop", path)

func _export_json(artboard: Node, path: String, _settings: Dictionary) -> void:
	var shapes = _collect_shapes(artboard)
	var json_data = {
		"version": "1.0",
		"artboard_name": artboard.name,
		"shapes": shapes
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(json_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("json", path)


func _get_node_data(node: Node) -> Dictionary:
	var data = {
		"name": node.name,
		"type": node.get_class(),
		"position": node.position if node.has("position") else Vector2.ZERO,
		"scale": node.scale if node.has("scale") else Vector2.ONE,
		"rotation": node.rotation if node.has("rotation") else 0.0,
		"children": []
	}
	
	for child in node.get_children():
		if child is Node:
			data["children"].append(_get_node_data(child))
	
	return data

func _get_layer_data(artboard: Node) -> Array:
	var layers = []
	for child in artboard.get_children():
		if child is Node2D:
			layers.append({
				"name": child.name,
				"type": child.get_class(),
				"visible": child.visible if child.has("visible") else true,
				"locked": child.locked if child.has("locked") else false
			})
	return layers

# ==========================================
# MÉTODOS DE CACHÉ Y ESTADO
# ==========================================

func _get_artboard_state(artboard: Node) -> Dictionary:
	"""
	Obtiene el estado del artboard para la caché de exportación.
	"""
	var state = {
		"id": artboard.get_instance_id(),
		"name": artboard.name,
		"size": artboard.get("artboard_size") if artboard.has("artboard_size") else Vector2.ZERO,
		"shapes": [],
		"modified_at": Time.get_unix_time_from_system()
	}
	
	# Recoger información de las shapes
	for child in artboard.get_children():
		if child is Node2D and child.name != "ArtboardTitle":
			var shape_state = {
				"type": child.get_class(),
				"id": child.get_instance_id(),
				"position": child.position,
				"scale": child.scale,
				"rotation": child.rotation,
				"properties": {}
			}
			
			# Propiedades específicas de cada tipo
			if child.has("stroke_color"):
				shape_state["properties"]["stroke_color"] = child.get("stroke_color").to_html()
			if child.has("fill_color"):
				shape_state["properties"]["fill_color"] = child.get("fill_color").to_html()
			if child.has("stroke_width"):
				shape_state["properties"]["stroke_width"] = child.get("stroke_width")
			if child.has("points") and child.get("points") is PackedVector2Array:
				shape_state["properties"]["points"] = child.get("points").duplicate()
			if child.has("polygon") and child.get("polygon") is PackedVector2Array:
				shape_state["properties"]["polygon"] = child.get("polygon").duplicate()
			if child.has("width"):
				shape_state["properties"]["width"] = child.get("width")
			if child.has("height"):
				shape_state["properties"]["height"] = child.get("height")
			
			state["shapes"].append(shape_state)
	
	return state


# ==========================================
# MÉTODOS DE EXPORTACIÓN
# ==========================================


func _import_svg(file_path: String, target_artboard: Node):
	target_artboard.import_svg(file_path)

func _vectorize_image(file_path: String, target_artboard: Node):
	target_artboard.vectorize_image(file_path)

func _import_eps(file_path: String, target_artboard: Node):
	# Import EPS as SVG first, then process
	var svg_path = file_path.get_base_dir() + "/" + file_path.get_file().get_basename() + ".svg"
	# EPS to SVG conversion would be done here
	_import_svg(svg_path, target_artboard)

func _import_godot_scene(file_path: String, target_artboard: Node):
	# Import Godot scene file
	var scene = load(file_path)
	if scene:
		var instance = scene.instantiate()
		target_artboard.add_child(instance)
		GlobalEvents.import_finished.emit(file_path)

func _import_vop(file_path: String, target_artboard: Node):
	# Import Vectopen proprietary format
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Cannot open VOP file: %s" % file_path)
		return
	
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	json.parse(content)
	var vop_data = json.data
	
	if not vop_data:
		push_error("Invalid VOP file: %s" % file_path)
		return
	
	# Process VOP data
	if vop_data.has("artboard"):
		target_artboard.name = vop_data["artboard"].get("name", "Imported Artboard")
		# Load layers from VOP data
		_load_vop_layers(target_artboard, vop_data["artboard"].get("layers", []))
		GlobalEvents.import_finished.emit(file_path)

func _load_vop_layers(artboard: Node, layers: Array) -> void:
	# Process VOP layers and recreate them in the artboard
	for layer_data in layers:
		# Create nodes based on layer type
		var layer_type = layer_data.get("type", "Node2D")
		var layer_node = create_node_by_type(layer_type)
		if layer_node:
			layer_node.name = layer_data.get("name", "Layer")
			layer_node.position = layer_data.get("position", Vector2.ZERO)
			layer_node.scale = layer_data.get("scale", Vector2.ONE)
			layer_node.rotation = layer_data.get("rotation", 0.0)
			artboard.add_child(layer_node)

func create_node_by_type(type_name: String) -> Node:
	# Factory method to create nodes by type name
	match type_name:
		"Path2D", "Bezier2D":
			return Path2D.new()
		"Polygon2D":
			return Polygon2D.new()
		"Line2D":
			return Line2D.new()
		"ColorRect", "Rect2D":
			return ColorRect.new()
		"Sprite2D":
			return Sprite2D.new()
		"Node2D":
			return Node2D.new()
		_:
			return Node2D.new()

func export_to_svg_string(artboard: Node) -> String:
	# Export artboard to SVG string (helper method)
	var svg_content = '<?xml version="1.0" encoding="UTF-8"?>\n'
	svg_content += '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s">\n' % [
		artboard.get("artboard_size").x if artboard.has("artboard_size") else 800,
		artboard.get("artboard_size").y if artboard.has("artboard_size") else 600
	]
	
	# Add shapes
	for child in artboard.get_children():
		if child is Node2D and child.name != "ArtboardTitle":
			svg_content += _node_to_svg(child)
	
	svg_content += '</svg>'
	return svg_content

func _node_to_svg(node: Node) -> String:
	# Convert a node to SVG element string
	var svg_element = ""
	
	if node is Path2D:
		svg_element = '<path d="M 0 0" stroke="black" fill="none"/>'
	elif node is Polygon2D:
		svg_element = '<polygon points="0,0 100,0 100,100 0,100" fill="none" stroke="black"/>'
	elif node is ColorRect:
		svg_element = '<rect x="0" y="0" width="100" height="100" fill="black"/>'
	elif node is Sprite2D:
		svg_element = '<image href="" x="0" y="0" width="100" height="100"/>'
	else:
		svg_element = '<!-- Unknown shape type: %s -->' % node.get_class()
	
	return svg_element
