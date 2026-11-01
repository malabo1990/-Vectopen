extends GdUnitTestSuite

## Comprobaciones previas de importar/exportar: archivos que no son lo que
## dicen, vacíos, destinos sin permiso, imágenes demasiado grandes, y la copia
## de seguridad antes de operar con cambios sin guardar.

const IoGuard = preload("res://script_gdscript/system/io_guard.gd")
const PsImport = preload("res://script_gdscript/system/ps_import.gd")
const FIX := "res://test/fixtures/import/"

var _dir := ""

func before_test() -> void:
	_dir = ProjectSettings.globalize_path("user://ioguard_test")
	DirAccess.make_dir_recursive_absolute(_dir)

func after_test() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))

func _write(name: String, bytes: PackedByteArray) -> String:
	var p := _dir.path_join(name)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return p

func test_reconoce_el_tipo_real() -> void:
	for pair in [["sample.svg", "svg"], ["sample.pdf", "pdf"], ["sample.ai", "pdf"],
			["sample.eps", "ps"], ["illustrator_old.eps", "ps"]]:
		var head := FileAccess.get_file_as_bytes(FIX + pair[0]).slice(0, 4096)
		assert_str(IoGuard.sniff(head)).override_failure_message(pair[0]).is_equal(pair[1])
	assert_str(IoGuard.sniff(PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]))).is_equal("png")
	assert_str(IoGuard.sniff(PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0]))).is_equal("jpg")
	assert_str(IoGuard.sniff("{\"format\":\"vop\"}".to_utf8_buffer())).is_equal("json")

func test_importar_archivos_validos_pasan() -> void:
	for f in ["sample.svg", "sample.pdf", "sample.ai", "sample.eps", "illustrator_old.eps"]:
		var r := IoGuard.check_import(FIX + f)
		assert_bool(r["ok"]).override_failure_message("%s: %s" % [f, r["error"]]).is_true()

func test_importar_rechaza_falsos_vacios_y_ausentes() -> void:
	assert_bool(IoGuard.check_import(_dir.path_join("no_existe.svg"))["ok"]).is_false()
	var empty := _write("vacio.svg", PackedByteArray())
	assert_str(IoGuard.check_import(empty)["error"]).contains("vacío")
	# un PNG renombrado a .pdf no debe llegar al lector de PDF
	var fake := _write("falso.pdf", PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]))
	var r := IoGuard.check_import(fake)
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).contains("no es un archivo .pdf válido")
	assert_str(r["error"]).contains("PNG")
	var junk := _write("basura.eps", "hola, esto no es PostScript".to_utf8_buffer())
	assert_bool(IoGuard.check_import(junk)["ok"]).is_false()

func test_exportar_destino_valido_y_reemplazo() -> void:
	var p := _dir.path_join("dibujo.svg")
	var r := IoGuard.check_export(p, "SVG")
	assert_bool(r["ok"]).is_true()
	assert_array(r["warnings"]).is_empty()
	_write("dibujo.svg", "x".to_utf8_buffer())
	r = IoGuard.check_export(p, "SVG")
	assert_bool(r["ok"]).is_true()
	assert_str(String(r["warnings"][0])).contains("reemplazado")
	assert_bool(FileAccess.file_exists(_dir.path_join(".vectopen_write_test"))).is_false()

func test_exportar_rechaza_nombre_documento_y_tamano() -> void:
	assert_bool(IoGuard.check_export(_dir.path_join("a:b?.svg"), "SVG")["ok"]).is_false()
	assert_bool(IoGuard.check_export(_dir.path_join(".svg"), "SVG")["ok"]).is_false()
	var doc := _dir.path_join("mi_doc.vtp")
	var r := IoGuard.check_export(doc, "VOP", Vector2.ZERO, doc)
	assert_str(r["error"]).contains("documento abierto")
	r = IoGuard.check_export(_dir.path_join("enorme.png"), "PNG", Vector2(20000, 500))
	assert_str(r["error"]).contains("máximo")
	assert_bool(IoGuard.check_export(_dir.path_join("ok.webp"), "WEBP", Vector2(16383, 100))["ok"]).is_true()
	assert_bool(IoGuard.check_export(_dir.path_join("no.webp"), "WEBP", Vector2(16384, 100))["ok"]).is_false()

func test_exportar_rechaza_carpeta_sin_permiso() -> void:
	if OS.get_name() == "Windows":
		return
	var r := IoGuard.check_export("/proc/vectopen_no/x.svg", "SVG")
	assert_bool(r["ok"]).is_false()

## El texto del PDF tiene que tener 1 carácter por byte (los offsets se usan
## en los bytes) y convertirse rápido aunque el archivo sea grande.
func test_texto_de_pdf_un_caracter_por_byte_y_rapido() -> void:
	var b := PackedByteArray([37, 80, 0, 200, 65, 0, 255, 10])
	var t: String = PsImport._Pdf.PsImport_bytes_to_text(b)
	assert_int(t.length()).is_equal(b.size())
	assert_str(t.substr(0, 2)).is_equal("%P")
	assert_str(t[4]).is_equal("A")
	var big := PackedByteArray()
	big.resize(16 * 1024 * 1024)
	for i in range(0, big.size(), 997):
		big[i] = 65
	var t0 := Time.get_ticks_msec()
	var s: String = PsImport._Pdf.PsImport_bytes_to_text(big)
	var ms := Time.get_ticks_msec() - t0
	assert_int(s.length()).is_equal(big.size())
	assert_int(ms).override_failure_message("16 MB en %d ms" % ms).is_less(1500)
