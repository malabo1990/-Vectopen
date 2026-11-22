# =============================================================================
# RUTA: res://script_gdscript/shapes/table_props.gd
# TABLAS v2 (VAL-56): opciones de la tabla como propiedades del inspector
# (InspectorCore «table_*»): cabecera, cebreado, tamaño de letra, alto de
# fila, borde, alineación de las columnas y sus colores. Así salen en Modern
# y Pro con su deshacer, sin un panel aparte que pueda divergir.
# Solo existen (read ≠ null) cuando el objeto es una tabla.
# =============================================================================
extends RefCounted

const Table = preload("res://script_gdscript/shapes/table.gd")

const PROPS := ["table_header", "table_zebra", "table_font_size", "table_row_h", "table_border",
	"table_align", "table_header_bg", "table_header_fg", "table_cell_bg", "table_zebra_bg",
	"table_text_color", "table_border_color"]
const COLOR_KEYS := {"table_header_bg": "header_bg", "table_header_fg": "header_fg",
	"table_cell_bg": "cell_bg", "table_zebra_bg": "zebra_bg", "table_text_color": "text",
	"table_border_color": "border"}

static func handles(prop: String) -> bool:
	return prop.begins_with("table_") and PROPS.has(prop)

static func read(n: Node, prop: String) -> Variant:
	if not Table.is_table(n):
		return null
	var s: Dictionary = n.get_meta(Table.META)
	match prop:
		"table_header": return bool(s.get("header", true))
		"table_zebra": return bool(s.get("zebra", true))
		"table_font_size": return float(s.get("font_size", 16))
		"table_row_h": return float(s.get("row_h", 44.0))
		"table_border": return float(s.get("border", 1.0))
		"table_align":
			var al: Array = s.get("align", [])
			if al.is_empty():
				return "left"
			var first := String(al[0])
			for a in al:
				if String(a) != first:
					return "mixed"
			return first
	if COLOR_KEYS.has(prop):
		return Table._col(s, COLOR_KEYS[prop])
	return null

static func write(n: Node, prop: String, value: Variant) -> void:
	if not Table.is_table(n):
		return
	Table.sync_from_children(n)   # no perder lo escrito en las celdas
	var s: Dictionary = (n.get_meta(Table.META) as Dictionary).duplicate(true)
	match prop:
		"table_header": s["header"] = bool(value)
		"table_zebra": s["zebra"] = bool(value)
		"table_font_size": s["font_size"] = clampi(int(round(float(value))), 4, 400)
		"table_row_h": s["row_h"] = maxf(8.0, float(value))
		"table_border": s["border"] = maxf(0.0, float(value))
		"table_align":
			var v := String(value)
			if v in ["left", "center", "right"]:
				var al: Array = []
				for c in int(s["cols"]):
					al.append(v)
				s["align"] = al
	if COLOR_KEYS.has(prop) and value is Color:
		var cols: Dictionary = (s.get("colors", {}) as Dictionary).duplicate()
		cols[COLOR_KEYS[prop]] = "#" + (value as Color).to_html(true)
		s["colors"] = cols
	n.set_meta(Table.META, s)
	Table.rebuild(n)
