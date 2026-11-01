# Demo para la web: un logo pequeño (96 px) → Mejorar ×4 (IA) → Vectorizar en
# blanco y negro, con el mismo motor que el panel Vectorizar.
#   flatpak run --command=godot org.godotengine.Godot --path . --headless -s res://tools/web_vectorize_demo.gd
extends SceneTree

func _g(p: String) -> String:
	return ProjectSettings.globalize_path("user://" + p)

func _init() -> void:
	if not ClassDB.class_exists("ImageVectorizer") or not ClassDB.class_exists("ImageUpscaler"):
		print("NO_EXT"); quit(1); return
	var up = ClassDB.instantiate("ImageUpscaler")
	var t := Time.get_ticks_msec()
	var e1: String = up.upscale_to_file(_g("vec_logo_in.png"), _g("vec_logo_x4.png"))
	print("RESULT upscale [", e1, "] ", Time.get_ticks_msec() - t, " ms")
	var v = ClassDB.instantiate("ImageVectorizer")
	var bw := {"color_mode": "binary", "filter_speckle": 4, "corner_threshold": 60, "mode": "spline"}
	print("RESULT bw_direct [", v.vectorize_ex(_g("vec_logo_in.png"), _g("vec_logo_bw.svg"), bw), "]")
	print("RESULT bw_x4 [", v.vectorize_ex(_g("vec_logo_x4.png"), _g("vec_logo_bw_x4.svg"), bw), "]")
	quit(0)
