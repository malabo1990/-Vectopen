# Escribe user://godot_notices.txt con la licencia de Godot y la de cada
# componente de terceros que incluye el motor (para THIRD_PARTY_NOTICES).
#   flatpak run --command=godot org.godotengine.Godot --path . --headless -s res://tools/gen_godot_notices.gd
extends SceneTree

func _init() -> void:
	var o := PackedStringArray()
	var v := Engine.get_version_info()
	o.append("Godot Engine %s — https://godotengine.org" % v.string)
	o.append("")
	o.append(Engine.get_license_text())
	o.append("")
	o.append("Godot Engine includes the following third-party components:")
	o.append("")
	for comp in Engine.get_copyright_info():
		o.append("- %s" % comp.name)
		for part in comp.parts:
			o.append("    Copyright: %s" % "; ".join(PackedStringArray(part.copyright)))
			o.append("    License: %s" % part.license)
	o.append("")
	var lic := Engine.get_license_info()
	var names := lic.keys()
	names.sort()
	for n in names:
		o.append("------------------------------------------------------------------")
		o.append("License: %s" % n)
		o.append("")
		o.append(String(lic[n]))
		o.append("")
	var f := FileAccess.open("user://godot_notices.txt", FileAccess.WRITE)
	f.store_string("\n".join(o))
	f.close()
	print("NOTICES ", o.size(), " lines")
	quit(0)
