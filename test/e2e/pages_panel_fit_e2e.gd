## E2E pestaña Páginas (Smart y Modern): la retícula y la página maestra NO se
## salen del panel (antes, con el panel bajo, «Usar maestra» y «Todas las
## páginas» quedaban por debajo, encima del pie «N capas»); con desplazamiento
## se llega a todo.
extends SceneTree

var K

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://pages_fit")
	for mode in ["smart", "modern"]:
		if not await K.boot(mode):
			quit(1)
			return
		await K.artboard(Vector2(800, 600), "Pág " + mode, Color.WHITE)
		var tab: Button = root.find_child("TabPaginas", true, false)
		if tab == null:
			for b in root.find_children("*", "Button", true, false):
				if (b as Button).text == "Páginas" and (b as Control).is_visible_in_tree():
					tab = b
		K.check("%s: pestaña Páginas" % mode, tab != null)
		if tab == null:
			continue
		tab.pressed.emit()
		await K.frames(8)
		var pp: Control = root.find_child("PaginasPanel", true, false)
		var sc: ScrollContainer = root.find_child("PageExtrasScroll", true, false)
		K.check("%s: retícula y maestra en una zona con desplazamiento" % mode, pp != null and sc != null and sc.is_visible_in_tree())
		if pp == null or sc == null:
			continue
		var pr := pp.get_global_rect()
		K.check("%s: la zona no se sale del panel" % mode, sc.get_global_rect().end.y <= pr.end.y + 1.0, "%s vs %s" % [sc.get_global_rect(), pr])
		for nm in ["IsMaster", "UseMaster", "MasterAllPages"]:
			var c: Control = sc.find_child(nm, true, false)
			sc.ensure_control_visible(c)
			await K.frames(3)
			var cr := c.get_global_rect()
			var vis := sc.get_global_rect()
			K.check("%s: «%s» accesible dentro del panel" % [mode, nm], vis.grow(1.0).encloses(cr), "%s en %s" % [cr, vis])
		await K.shot("paginas_" + mode)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
