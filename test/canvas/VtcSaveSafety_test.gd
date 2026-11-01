extends GdUnitTestSuite

## SEGURIDAD AL GUARDAR el documento (.vtp / .vtc):
##  1. Guardar dos veces en el MISMO archivo con páginas aún sin cargar no
##     puede corromperlas (antes: tras el 1.er guardado sus posiciones en el
##     archivo quedaban viejas → la página salía vacía o se copiaban bytes
##     equivocados).
##  2. El guardado es atómico: se escribe un temporal y se reemplaza al final;
##     no queda el temporal y el archivo es válido.
##  3. Una página dañada no se abre vacía en silencio: se marca, se avisa, y al
##     guardar se conservan sus bytes originales (no se sobrescribe con nada).

const CANVAS := "res://scenes/canvas/canvas.tscn"
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

var _paths: Array[String] = []

func _scene() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	auto_free(s)
	return s

func _path(name: String) -> String:
	var p := "user://__vtc_safety_%s" % name
	_paths.append(p)
	return p

func after_test() -> void:
	CS.close_reader_cache()
	for p in _paths:
		for f in [p, p + ".tmp"]:
			var g := ProjectSettings.globalize_path(f)
			if FileAccess.file_exists(g):
				DirAccess.remove_absolute(g)
	_paths.clear()

## Libro de `pages` páginas × `per` círculos.
func _book(container: Node2D, pages: int, per: int) -> void:
	CS.rebuild_container(container, {"v": 1, "loose": [], "artboards": []})
	for p in pages:
		var ab := ArtboardEditor.new()
		ab.name = "Pag%d" % p
		ab.artboard_size = Vector2(400, 500)
		container.add_child(ab)
		ab.position = Vector2(p * 700, 0)
		for i in per:
			var c := VectorCircle.new()
			c.name = "P%d_C%d" % [p, i]
			c.size = Vector2(15, 15)
			ab.add_child(c)
			c.position = Vector2(20 + i * 3, 30)

func _counts_in_file(path: String) -> Array:
	var out := []
	var m := CS.read_vtc_manifest(path)
	for h in m.get("artboards", []):
		out.append(CS.read_vtc_chunk(path, h).size())
	return out

func _pages(container: Node2D) -> Array:
	var out := []
	for ch in container.get_children():
		if ch is ArtboardEditor:
			out.append(ch)
	return out


func test_guardar_dos_veces_en_el_mismo_archivo_no_corrompe_paginas_sin_cargar() -> void:
	var s := _scene()
	await get_tree().process_frame
	var container: Node2D = s.get_node("ArtboardsContainer")
	_book(container, 4, 20)
	await get_tree().process_frame
	var path := _path("same.vtc")
	assert_bool(CS.write_vtc(path, container)).is_true()

	# Abrir perezoso: solo la 1.ª página se carga.
	CS.rebuild_from_vtc(container, path)
	await get_tree().process_frame
	var pages := _pages(container)
	assert_bool(pages[2].is_dormant).is_true()
	assert_bool(pages[3].is_dormant).is_true()

	# Cambiar el TAMAÑO del bloque de la página 0 (las de detrás se desplazan).
	pages[0].wake(true)
	for i in 30:
		var c := VectorCircle.new()
		c.size = Vector2(9, 9)
		pages[0].add_child(c)
	# Guardar DOS veces en el mismo archivo sin despertar las páginas 1-3.
	assert_bool(CS.write_vtc(path, container)).is_true()
	assert_bool(CS.write_vtc(path, container)).is_true()
	assert_array(_counts_in_file(path)).is_equal([50, 20, 20, 20])

	# Y al despertarlas ahora, tienen su contenido.
	for i in [1, 2, 3]:
		pages[i].wake(true)
		var n := 0
		for ch in pages[i].get_children():
			if ch is VectorCircle:
				n += 1
		assert_int(n).override_failure_message("página %d vacía tras guardar" % i).is_equal(20)


func test_guardado_atomico_no_deja_temporal() -> void:
	var s := _scene()
	await get_tree().process_frame
	var container: Node2D = s.get_node("ArtboardsContainer")
	_book(container, 2, 5)
	var path := _path("atomic.vtc")
	assert_bool(CS.write_vtc(path, container)).is_true()
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()
	assert_array(_counts_in_file(path)).is_equal([5, 5])


func test_pagina_danada_se_marca_y_no_se_pierde_al_guardar() -> void:
	var s := _scene()
	await get_tree().process_frame
	var container: Node2D = s.get_node("ArtboardsContainer")
	_book(container, 3, 10)
	var path := _path("damaged.vtc")
	assert_bool(CS.write_vtc(path, container)).is_true()

	# Estropear el bloque comprimido de la página 1 dentro del archivo.
	var m := CS.read_vtc_manifest(path)
	var h1: Dictionary = m["artboards"][1]
	var bytes := FileAccess.get_file_as_bytes(path)
	var data_start := 8 + _manifest_len(bytes)
	var at := data_start + int(h1["off"]) + int(h1["len"]) / 2
	for k in 16:
		bytes[at + k] = (bytes[at + k] + 77) % 256
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	CS.close_reader_cache()
	var damaged_chunk := bytes.slice(data_start + int(h1["off"]), data_start + int(h1["off"]) + int(h1["len"]))

	var notices := []
	var on_notice := func(level: String, msg: String) -> void: notices.append([level, msg])
	GlobalEvents.user_notice.connect(on_notice)
	CS.rebuild_from_vtc(container, path)
	var pages := _pages(container)
	pages[1].wake(true)
	await get_tree().process_frame
	GlobalEvents.user_notice.disconnect(on_notice)

	assert_bool(pages[1].is_damaged()).is_true()
	assert_int(notices.size()).is_greater(0)
	assert_str(String(notices[0][0])).is_equal("error")

	# Guardar en otro archivo: la página dañada conserva SUS bytes (no vacía).
	var out := _path("damaged_out.vtc")
	assert_bool(CS.write_vtc(out, container)).is_true()
	var m2 := CS.read_vtc_manifest(out)
	var h1b: Dictionary = m2["artboards"][1]
	var raw := CS.read_vtc_chunk_compressed(out, int(h1b["off"]), int(h1b["len"]))
	assert_bool(raw == damaged_chunk).override_failure_message("la página dañada se sobrescribió").is_true()
	# Las otras dos siguen intactas.
	assert_int(CS.read_vtc_chunk(out, m2["artboards"][0]).size()).is_equal(10)
	assert_int(CS.read_vtc_chunk(out, m2["artboards"][2]).size()).is_equal(10)


func _manifest_len(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(4)


func test_formato_vtp_y_los_vtc_antiguos_se_siguen_abriendo() -> void:
	var s := _scene()
	await get_tree().process_frame
	var container: Node2D = s.get_node("ArtboardsContainer")
	_book(container, 2, 7)
	await get_tree().process_frame
	# Un .vtc antiguo (mismo contenedor) se abre.
	var old := _path("legacy.vtc")
	assert_bool(CS.write_vtc(old, container)).is_true()
	assert_bool(DataRepository.load_project(old)).is_true()
	# Guardar ese documento pide «legacy.vtc» → se escribe «legacy.vtp» y el
	# original se conserva.
	var saved := DataRepository.save_project(old)
	_paths.append(saved)
	assert_str(saved).ends_with(".vtp")
	assert_bool(FileAccess.file_exists(saved)).is_true()
	assert_bool(FileAccess.file_exists(old)).is_true()
	assert_array(_counts_in_file(saved)).is_equal([7, 7])
	# Sin extensión → .vtp
	var plain := DataRepository.save_project(_path("sin_ext"))
	_paths.append(plain)
	assert_str(plain).ends_with(".vtp")
