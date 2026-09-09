extends Control

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.85, 0.85, 0.88, 1.0)
	add_child(bg)

	var pickr = load("res://scenes/ui/pickr_color_tool.tscn").instantiate() as Control
	pickr.position = Vector2(100, 50)
	add_child(pickr)

	await get_tree().process_frame
	await get_tree().process_frame

	# Conmutar a modo triángulo (índice 1)
	if pickr.has_method("_on_mode_pressed"):
		pickr._on_mode_pressed(1)
	elif is_instance_valid(pickr.btn_mode_triangle):
		pickr.btn_mode_triangle.pressed.emit()

	for i in range(10):
		await get_tree().process_frame

	# Inspeccionar todos los nodos hijos y sus estilos
	_dump_nodes(pickr, 0)

	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	var path := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/inspect_triangle_mode.png"
	img.save_png(path)
	print("Captura guardada en: ", path)

	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)

func _dump_nodes(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var info := "%s- %s (%s)" % [indent, node.name, node.get_class()]
	if node is Control:
		info += " vis=%s rect=%s" % [node.visible, Rect2(node.position, node.size)]
		if node is Panel or node is PanelContainer:
			var sb = node.get_theme_stylebox("panel")
			if sb:
				info += " sb_class=%s" % sb.get_class()
				if sb is StyleBoxFlat:
					info += " bg_color=%s" % sb.bg_color
	print(info)
	for c in node.get_children():
		_dump_nodes(c, depth + 1)
