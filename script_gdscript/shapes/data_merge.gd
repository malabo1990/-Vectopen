# =============================================================================
# RUTA: res://script_gdscript/shapes/data_merge.gd
# COMBINACIÓN DE DATOS (catálogos, informe §5, como el «Data Merge» de
# InDesign): una PLANTILLA (grupo o texto) con marcadores {campo} y una tabla
# CSV → una ficha por fila. Aquí: leer el CSV y sustituir los marcadores. La
# colocación (rejilla en páginas nuevas, un paso de deshacer) la hace la API
# (`data_merge`). Los {pág} / {total} de los números de página no se tocan.
# =============================================================================
extends RefCounted

## CSV → filas como diccionarios (primera fila = nombres de campo). Separador
## automático (coma, punto y coma o tabulador); comillas "…" con "" dentro.
static func parse_csv(text: String) -> Array:
	var lines := text.replace("\r\n", "\n").replace("\r", "\n")
	var first := lines.get_slice("\n", 0)
	var sep := ","
	if first.count(";") > first.count(","):
		sep = ";"
	if first.count("\t") > maxi(first.count(","), first.count(";")):
		sep = "\t"
	var rows: Array = []
	var row: Array = []
	var cell := ""
	var quoted := false
	var i := 0
	while i < lines.length():
		var ch := lines[i]
		if quoted:
			if ch == "\"":
				if i + 1 < lines.length() and lines[i + 1] == "\"":
					cell += "\""
					i += 1
				else:
					quoted = false
			else:
				cell += ch
		elif ch == "\"":
			quoted = true
		elif ch == sep:
			row.append(cell)
			cell = ""
		elif ch == "\n":
			row.append(cell)
			cell = ""
			if not (row.size() == 1 and String(row[0]).strip_edges() == ""):
				rows.append(row)
			row = []
		else:
			cell += ch
		i += 1
	if cell != "" or not row.is_empty():
		row.append(cell)
		rows.append(row)
	if rows.is_empty():
		return []
	var head: Array = rows[0].map(func(h) -> String: return String(h).strip_edges())
	var out: Array = []
	for r in rows.slice(1):
		var d := {}
		for c in head.size():
			d[head[c]] = String(r[c]).strip_edges() if c < r.size() else ""
		out.append(d)
	return out

## Sustituye {campo} por su valor (sin tocar {pág}, {total} ni campos que no
## existan en la fila).
static func fill(t: String, row: Dictionary) -> String:
	if not t.contains("{"):
		return t
	var out := t
	for k in row:
		out = out.replace("{%s}" % k, String(row[k]))
	return out

## Campos que usa la plantilla (para avisar de los que faltan en el CSV).
static func fields_in(t: String) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.new()
	re.compile("\\{([^{}]+)\\}")
	for m in re.search_all(t):
		var f := m.get_string(1)
		if not (f in ["pág", "pag", "#", "total"]) and not out.has(f):
			out.append(f)
	return out
