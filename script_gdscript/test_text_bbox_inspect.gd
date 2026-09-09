extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_text_bbox_test.png"

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.94, 0.95, 0.97, 1.0)
	add_child(bg)

	var s: Node2D = load("res://scenes/canvas/canvas.tscn").instantiate()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	var artboard: Node2D = s.get_node_or_null("ArtboardsContainer/Artboard")
	if not artboard:
		print("ERROR: No artboard found!")
		get_tree().quit(1)
		return

	# Configurar MoveTool
	var move_tool_script = load("res://script_gdscript/tools/MoveTool.gd")
	var move_tool = s._new_tool(move_tool_script)
	move_tool.target_artboard = artboard
	move_tool.canvas = s
	s.change_tool(move_tool)

	# 1. Crear Texto 1 (Left / Top) con tamaño 360x70
	var txt1 := _create_text_node(artboard, "1. Izquierda / Arriba (Left-Top)", Vector2(100, 100), Vector2(360, 70), "left", "top")

	# 2. Crear Texto 2 (Center / Middle) con tamaño 360x70
	var txt2 := _create_text_node(artboard, "2. Centrado / Medio (Center-Middle)", Vector2(100, 220), Vector2(360, 70), "center", "middle")

	# 3. Crear Texto 3 (Right / Bottom) con tamaño 360x70
	var txt3 := _create_text_node(artboard, "3. Derecha / Abajo (Right-Bottom)", Vector2(100, 340), Vector2(360, 70), "right", "bottom")

	# 4. Crear Texto 4 (Título Corporativo con Center / Middle)
	var txt4 := _create_text_node(artboard, "Título Corporativo", Vector2(100, 460), Vector2(320, 60), "center", "middle")

	# 5. Crear Texto 5 (Vector Mode / Letter Proportions con Center / Middle)
	var txt5 := _create_text_node(artboard, "5. Proporción Vector (Center-Middle)", Vector2(100, 560), Vector2(380, 70), "center", "middle")
	var dl5: WorldTextLabel = txt5.get_node_or_null("DisplayLabel")
	if dl5:
		dl5.set_letter_proportions({"mode": "Aaa", "start": 1.3, "mid": 1.0, "end": 0.8})

	await get_tree().process_frame
	await get_tree().process_frame

	# Seleccionar txt4 con SelectionManager y MoveTool para que el BoundingBox interactivo se muestre alrededor de él
	var sm = get_node_or_null("/root/SelectionManager")
	if sm:
		sm.set_selection([txt4])
	if move_tool:
		move_tool.selected_shapes.assign([txt4])
		move_tool._update_bounding_box()

	await get_tree().process_frame
	await get_tree().process_frame

	var dl4: Control = txt4.get_node_or_null("DisplayLabel")
	print("txt4 pos = ", txt4.position, " width = ", txt4.get_meta("width"), " height = ", txt4.get_meta("height"))
	print("dl4 pos = ", dl4.position, " size = ", dl4.size, " h_align = ", dl4.horizontal_alignment, " v_align = ", dl4.vertical_alignment)
	if dl4 is WorldTextLabel:
		print("dl4 world_size = ", dl4._world_size, " scale = ", dl4.scale)

	for i in range(25):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(SCREENSHOT_PATH)
		print("Captura guardada en: ", SCREENSHOT_PATH)
	else:
		print("ERROR: Viewport texture image was null")
	get_tree().quit(0)

func _create_text_node(artboard: Node2D, text_content: String, pos: Vector2, box_size: Vector2, h_align: String, v_align: String) -> Node2D:
	var node := Node2D.new()
	node.name = NameUtils.unique_child_name(artboard, "Texto")
	node.position = pos
	node.set_meta("shape_type", "text_title")
	node.set_meta("text", text_content)
	node.set_meta("font_size", 20)
	node.set_meta("width", box_size.x)
	node.set_meta("height", box_size.y)
	node.set_meta("text_align", h_align)
	node.set_meta("text_valign", v_align)

	# Borde visible de referencia para depuración visual (rectángulo gris claro detrás)
	var ref_box := Line2D.new()
	ref_box.name = "DebugBox"
	ref_box.width = 1.0
	ref_box.default_color = Color(0.7, 0.7, 0.8, 0.8)
	ref_box.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(box_size.x, 0),
		Vector2(box_size.x, box_size.y),
		Vector2(0, box_size.y),
		Vector2.ZERO
	])
	node.add_child(ref_box)

	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = 20
	label.text = text_content
	label.add_theme_color_override("font_color", Color(0.12, 0.14, 0.18, 1.0))
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = {
		"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER,
		"right": HORIZONTAL_ALIGNMENT_RIGHT, "fill": HORIZONTAL_ALIGNMENT_FILL
	}.get(h_align, HORIZONTAL_ALIGNMENT_LEFT)
	label.vertical_alignment = {
		"top": VERTICAL_ALIGNMENT_TOP, "middle": VERTICAL_ALIGNMENT_CENTER,
		"bottom": VERTICAL_ALIGNMENT_BOTTOM
	}.get(v_align, VERTICAL_ALIGNMENT_TOP)
	label.set_world_size(box_size)

	var edit := TextEdit.new()
	edit.name = "TitleEdit"
	edit.visible = false

	node.add_child(label)
	node.add_child(edit)
	artboard.add_child(node)
	return node
