extends OptionButton

func _ready() -> void:
	var lm := get_node_or_null("/root/LanguageManager")
	if not lm:
		return
	for locale in lm.get_locale_list():
		add_item(lm.get_locale_name(locale))
		if locale == lm.current_locale:
			select(item_count - 1)
	item_selected.connect(_on_selected.bind(lm))
	if lm.has_signal("language_changed"):
		lm.language_changed.connect(_on_changed)

func _on_selected(index: int, lm: Node) -> void:
	var locales = lm.get_locale_list()
	if index >= 0 and index < locales.size():
		lm.set_locale(locales[index])

func _on_changed(_locale: String) -> void:
	var lm := get_node_or_null("/root/LanguageManager")
	if not lm:
		return
	for i in range(item_count):
		if get_item_text(i) == lm.get_locale_name(lm.current_locale):
			select(i)
			return
