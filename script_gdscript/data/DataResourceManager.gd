extends Node

const EXTENSION: String = ".vectres"

# ── Save / Load using native ResourceSaver/ResourceLoader ──

func save_project(project: VectopenProject, path: String) -> int:
	if not path.ends_with(EXTENSION):
		path += EXTENSION
	return ResourceSaver.save(project, path, ResourceSaver.FLAG_COMPRESS)

func load_project(path: String) -> VectopenProject:
	if not ResourceLoader.exists(path):
		return null
	var res = ResourceLoader.load(path)
	if res is VectopenProject:
		return res
	return null

func artboard_to_resource(ab_data) -> VectopenArtboard:
	var r = VectopenArtboard.new()
	r.id = ab_data.id
	r.artboard_name = ab_data.name
	r.position = ab_data.position
	r.size = ab_data.size
	r.bg_color = ab_data.bg_color
	return r

func layer_to_resource(layer_data) -> VectopenLayer:
	var r = VectopenLayer.new()
	r.id = layer_data.id
	r.layer_name = layer_data.name
	r.artboard_id = layer_data.artboard_id
	r.is_visible = layer_data.is_visible
	r.is_locked = layer_data.is_locked
	r.opacity = layer_data.opacity
	r.blend_mode = layer_data.blend_mode
	for s in layer_data.shapes:
		var sr = shape_to_resource(s)
		r.shapes.append(sr)
		r.shape_ids.append(s.id)
	return r

func shape_to_resource(shape_data) -> VectopenShape:
	var r = VectopenShape.new()
	r.id = shape_data.id
	r.shape_type = shape_data.type
	r.shape_name = shape_data.name
	r.position = shape_data.position
	r.rotation = shape_data.rotation
	r.scale = shape_data.scale
	r.stroke_color = shape_data.stroke_color
	r.stroke_width = shape_data.stroke_width
	r.fill_color = shape_data.fill_color
	r.is_filled = shape_data.is_filled
	r.size = shape_data.size
	r.text_content = shape_data.text_content
	if shape_data.points is PackedVector2Array:
		r.points = shape_data.points
	elif shape_data.points is Array:
		r.points = PackedVector2Array(shape_data.points)
	return r

func convert_project_to_resource() -> VectopenProject:
	var repo = DataRepository
	if not repo or not repo.project:
		return null
	var p = repo.project
	var r = VectopenProject.new()
	r.project_name = p.name
	r.file_path = p.file_path
	r.created_at = p.created_at
	for ab_id in p.artboards:
		var ab = artboard_to_resource(p.artboards[ab_id])
		r.add_artboard(ab)
	for layer_id in p.layers:
		var layer = layer_to_resource(p.layers[layer_id])
		r.add_layer(layer)
	return r

func convert_resource_to_project(r: VectopenProject):
	var repo = DataRepository
	if not repo:
		return
	var p = repo.project
	if not p:
		return
	p.name = r.project_name
	p.file_path = r.file_path
	p.created_at = r.created_at
	p.artboards.clear()
	p.layers.clear()
	for ab_id in r.list_artboard_ids():
		var ab = r.get_artboard(ab_id)
		p.artboards[ab_id] = _resource_to_artboard_data(ab)
	for layer_id in r.list_layer_ids():
		var layer = r.get_layer(layer_id)
		p.layers[layer_id] = _resource_to_layer_data(layer)

func _resource_to_artboard_data(r: VectopenArtboard):
	var d = DataRepository.ArtboardData.new()
	d.id = r.id
	d.name = r.artboard_name
	d.position = r.position
	d.size = r.size
	d.bg_color = r.bg_color
	return d

func _resource_to_layer_data(r: VectopenLayer):
	var d = DataRepository.LayerData.new()
	d.id = r.id
	d.name = r.layer_name
	d.artboard_id = r.artboard_id
	d.is_visible = r.is_visible
	d.is_locked = r.is_locked
	d.opacity = r.opacity
	d.blend_mode = r.blend_mode
	for s in r.shapes:
		var sd = _resource_to_shape_data(s)
		d.shapes.append(sd)
		d.shape_ids.append(s.id)
	return d

func _resource_to_shape_data(r: VectopenShape):
	var d = DataRepository.ShapeData.new()
	d.id = r.id
	d.type = r.shape_type
	d.name = r.shape_name
	d.position = r.position
	d.rotation = r.rotation
	d.scale = r.scale
	d.stroke_color = r.stroke_color
	d.stroke_width = r.stroke_width
	d.fill_color = r.fill_color
	d.is_filled = r.is_filled
	d.size = r.size
	d.text_content = r.text_content
	d.points = r.points
	return d
