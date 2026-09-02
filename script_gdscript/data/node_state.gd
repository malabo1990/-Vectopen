class_name NodeState
extends RefCounted

## Contrato ÚNICO para capturar y restaurar el estado NO-geométrico de un nodo
## del documento: visibilidad, bloqueo, recorte / máscara de recorte y z-order.
##
## Objetivo: que CUALQUIER operación de undo pueda guardar y restaurar este
## estado de forma uniforme, en vez de que cada sitio (panel de capas,
## herramienta, inspector…) reinvente su propio "antes / después".
##
## NO cubre transform ni geometría (posición, rotación, tamaño, puntos de path…).
## De eso se ocupa `MoveTool._snapshot` / `_restore_transform`, que trabajan en
## doble precisión. `capture()` / `restore()` de aquí son ADITIVOS: se llaman
## JUNTO a esos, no en su lugar.

const _CLAVES := ["visible", "z_index", "locked", "clip_children", "clip_mask", "clip_mask_target"]

## Estado no-geométrico de `n`. Una clave está presente solo si el nodo la
## soporta (p. ej. `clip_children` solo en `CanvasItem`).
static func capture(n: Node) -> Dictionary:
	var s: Dictionary = {}
	if not is_instance_valid(n):
		return s
	if "visible" in n:
		s["visible"] = bool(n.visible)
	if "z_index" in n:
		s["z_index"] = int(n.z_index)
	s["locked"] = bool(n.get_meta("locked", false))
	if "clip_children" in n:
		s["clip_children"] = int(n.clip_children)
	if n.has_meta("clip_mask"):
		s["clip_mask"] = bool(n.get_meta("clip_mask"))
		s["clip_mask_target"] = String(n.get_meta("clip_mask_target", ""))
	return s

## Reaplica sobre `n` lo que capturó `capture()`. Cada clave se restaura solo si
## está presente en `s` y el nodo la soporta → seguro con capturas parciales o
## de versiones antiguas.
static func restore(n: Node, s: Dictionary) -> void:
	if not is_instance_valid(n) or s.is_empty():
		return
	if s.has("visible") and "visible" in n:
		n.visible = bool(s["visible"])
	if s.has("z_index") and "z_index" in n:
		n.z_index = int(s["z_index"])
	if s.has("locked"):
		if bool(s["locked"]):
			n.set_meta("locked", true)
		elif n.has_meta("locked"):
			n.remove_meta("locked")
	if s.has("clip_children") and "clip_children" in n:
		n.clip_children = int(s["clip_children"])
	if s.has("clip_mask"):
		if bool(s["clip_mask"]):
			n.set_meta("clip_mask", true)
			n.set_meta("clip_mask_target", String(s.get("clip_mask_target", "")))
		else:
			if n.has_meta("clip_mask"):
				n.remove_meta("clip_mask")
			if n.has_meta("clip_mask_target"):
				n.remove_meta("clip_mask_target")

## ¿Dos capturas representan el MISMO estado no-geométrico?
static func equal(a: Dictionary, b: Dictionary) -> bool:
	for k in _CLAVES:
		if a.get(k) != b.get(k):
			return false
	return true
