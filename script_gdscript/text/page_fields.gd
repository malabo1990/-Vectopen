# =============================================================================
# VECTOPEN — CAMPOS DE PÁGINA EN TEXTOS (VAL-01, Fase B · libro)
# RUTA: res://script_gdscript/text/page_fields.gd
#
# Como el «número de página actual» de InDesign / Affinity: en cualquier texto
#   {pág} · {pag} · {#}   → número de la página (artboard) que lo contiene
#   {total}               → número de páginas del documento
# El texto GUARDADO conserva el marcador (meta «text»); lo que se ve (la
# etiqueta) y lo que se exporta lleva el número. Al añadir, borrar o
# reordenar páginas, o al abrir un documento, los números se recalculan solos.
# =============================================================================
extends RefCounted

const TOKENS_PAGE := ["{pág}", "{pag}", "{#}"]
const TOKEN_TOTAL := "{total}"

static func has_fields(t: String) -> bool:
	if not t.contains("{"):
		return false
	for k in TOKENS_PAGE + [TOKEN_TOTAL]:
		if t.contains(k):
			return true
	return false

## Páginas del documento en su orden.
static func pages(tree: SceneTree) -> Array:
	if tree == null:
		return []
	var cv = tree.get_first_node_in_group("_vectopen_canvas")
	var cont = cv.get("artboards_container") if cv else null
	var out: Array = []
	if cont is Node:
		for c in (cont as Node).get_children():
			if c.is_in_group("artboards"):
				out.append(c)
	if out.is_empty():
		out = tree.get_nodes_in_group("artboards")
	return out

## Página (artboard) que contiene a `n`.
static func page_of(n: Node) -> Node:
	var p: Node = n
	while p:
		if p.is_in_group("artboards"):
			return p
		p = p.get_parent()
	return null

## Texto con los marcadores sustituidos para el nodo `n`.
static func resolve(t: String, n: Node) -> String:
	if not has_fields(t) or n == null or not n.is_inside_tree():
		return t
	var list := pages(n.get_tree())
	var ab := page_of(n)
	var idx := list.find(ab) + 1 if ab else 0
	var out := t
	for k in TOKENS_PAGE:
		out = out.replace(k, str(idx) if idx > 0 else "#")
	return out.replace(TOKEN_TOTAL, str(list.size()))

## Vuelve a resolver todos los textos con campos (tras cambiar las páginas).
static func refresh_all(tree: SceneTree) -> int:
	var n_done := 0
	for ab in pages(tree):
		for t in (ab as Node).find_children("*", "Node2D", true, false):
			if not t.has_meta("text"):
				continue
			var raw := String(t.get_meta("text", ""))
			if not has_fields(raw):
				continue
			var shown := resolve(raw, t)
			for nm in ["DisplayLabel", "Label"]:
				var dl = t.get_node_or_null(nm)
				if dl and "text" in dl and dl.text != shown:
					dl.text = shown
					n_done += 1
			var vrt = t.get_node_or_null("VectorRichText")
			if vrt and vrt.has_method("set_text"):
				vrt.set_text(shown)
	return n_done

## Firma del orden de páginas (para saber cuándo recalcular).
static func signature(tree: SceneTree) -> String:
	var ids: Array = []
	for p in pages(tree):
		ids.append(str((p as Object).get_instance_id()))
	return ",".join(ids)
