# =============================================================================
# RUTA: res://script_gdscript/shapes/ClipboardImageService.gd
#
# Puente entre el GDExtension nativo (ClipboardImage / arboard, ver
# rust/vectopen_vectorizer) y el canvas: si el portapapeles del sistema
# tiene una imagen (copiada de un navegador, un visor/editor de imágenes,
# una captura de pantalla, etc.), la importa como Sprite2D en el artboard
# activo — mismo camino que ya usa ImportExportManager al importar PNG/JPEG
# (Artboard.vectorize_image, pese al nombre no vectoriza de verdad).
#
# NO cubre "copiar un archivo" en el explorador de Windows (formato CF_HDROP,
# distinto del bitmap que sí lee arboard) — para eso está el diálogo normal
# de Importar.
# =============================================================================
class_name ClipboardImageService
extends RefCounted

## Si el portapapeles del sistema tiene una imagen, la importa en el
## artboard activo de `canvas` y devuelve true. Si el portapapeles no tiene
## imagen (vacío, texto, o el portapapeles interno de formas de Vectopen)
## devuelve false SIN hacer push_error — es el caso normal en el que el
## llamador debe caer al Ctrl+V interno de formas.
static func try_paste_into(canvas: Node) -> bool:
	if not ClassDB.class_exists("ClipboardImage"):
		return false
	if not is_instance_valid(canvas):
		return false

	var target_artboard: Node = _resolve_active_artboard(canvas)
	if not is_instance_valid(target_artboard):
		return false

	var tmp_path := ProjectSettings.globalize_path("user://_clipboard_paste_%d.png" % Time.get_ticks_usec())
	var has_native_clip := ClassDB.class_exists("ClipboardImage")
	var result := "EMPTY"

	if has_native_clip:
		var clip = ClassDB.instantiate("ClipboardImage")
		result = clip.paste_image_to_file(tmp_path)

	if result != "EMPTY" and result != "":
		push_error("ClipboardImageService: fallo al leer el portapapeles: %s" % result)
		return false

	if result == "":
		target_artboard.vectorize_image(tmp_path)
		DirAccess.remove_absolute(tmp_path)
		return true

	# Fallback a texto del portapapeles si no hubo bitmap nativo (data URI o URL de imagen)
	var clip_text := DisplayServer.clipboard_get().strip_edges()
	if clip_text.begins_with("data:image/") and ";base64," in clip_text:
		var parts := clip_text.split(";base64,")
		if parts.size() >= 2:
			var buf := Marshalls.base64_to_raw(parts[1])
			if not buf.is_empty() and target_artboard.has_method("import_image_from_buffer"):
				target_artboard.import_image_from_buffer(buf, "Captura_Base64")
				return true

	if (clip_text.begins_with("http://") or clip_text.begins_with("https://")) and _is_image_url(clip_text):
		_fetch_and_import_url(clip_text, target_artboard, canvas)
		return true

	return false

static func _is_image_url(url: String) -> bool:
	var u := url.to_lower()
	for ext in [".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".gif"]:
		if u.contains(ext):
			return true
	return false

static func _fetch_and_import_url(url: String, target_artboard: Node, canvas: Node) -> void:
	if not is_instance_valid(canvas):
		return
	var http := HTTPRequest.new()
	canvas.add_child(http)
	http.request_completed.connect(func(res: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		if is_instance_valid(http):
			http.queue_free()
		if res == HTTPRequest.RESULT_SUCCESS and code == 200 and not body.is_empty():
			if is_instance_valid(target_artboard) and target_artboard.has_method("import_image_from_buffer"):
				var raw_name: String = url.get_file().get_basename()
				var name_hint := "Foto_" + (raw_name if not raw_name.is_empty() else "Web")
				target_artboard.import_image_from_buffer(body, name_hint)
	)
	http.request(url)

static func _resolve_active_artboard(canvas: Node) -> Node:
	if canvas.is_inside_tree():
		var mgr = ArtboardManager.find(canvas.get_tree())
		if mgr:
			var active = mgr.get_active_artboard()
			if is_instance_valid(active):
				return active
	var container := canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		return container.get_child(0)
	return null
