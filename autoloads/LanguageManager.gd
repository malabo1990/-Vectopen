extends Node

signal language_changed(locale: String)

const CONFIG_PATH := "user://vectopen_language.cfg"
const SETTINGS_KEY := "application/vectopen/locale"
const TRANSLATIONS_PATH := "res://translations/vectopen.csv"

var current_locale: String = "en"
var available_locales: Dictionary = {
	"en": "English",
	"es": "Español",
	"fr": "Français",
	"de": "Deutsch",
	"pt": "Português",
	"ru": "Русский",
	"zh": "中文",
	"ja": "日本語",
	"ar": "العربية",
	"hi": "हिन्दी",
}

func _ready() -> void:
	_load_translation_file()
	set_locale(_initial_locale(), false)

## Idioma al arrancar: el que eligió el usuario (user://) → el idioma del
## sistema si Vectopen lo tiene → inglés.
func _initial_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		var saved := String(cfg.get_value("ui", "locale", ""))
		if saved in available_locales:
			return saved
	var sys := OS.get_locale_language()
	if sys in available_locales:
		return sys
	return "en"

func _load_translation_file() -> void:
	# Bug real encontrado en vivo ("Copyiar" al pasar de es→en en el menú
	# contextual, test_modern_context_menu_reacts_to_language_change): esto
	# registraba en TranslationServer TANTO los .translation precompilados
	# (importados automáticamente por Godot desde vectopen.csv — build
	# artifact, con textos viejos como "Copiar (Ctrl+C)" horneados de una
	# versión anterior de los menús, donde el atajo vivía DENTRO del string
	# traducido) COMO una segunda tabla fresca parseada a mano del mismo CSV
	# (_load_csv_translations, más abajo) — dos Translation por locale con
	# claves/valores desalineados entre sí, y el orden de qué versión "gana"
	# en TranslationServer.translate() no es determinista. El CSV vía
	# _load_csv_translations ya es la única fuente que se edita a mano; los
	# .translation precompilados quedan sin usar aquí.
	_load_csv_translations()

func _load_csv_translations() -> void:
	if not FileAccess.file_exists(TRANSLATIONS_PATH):
		# VAL-02: en la app EXPORTADA el CSV no va en el paquete (Godot solo
		# empaqueta las .translation compiladas a partir de él al exportar).
		# Sin esto la app instalada salía sin traducir (inglés y español
		# mezclados).
		_load_compiled_translations()
		return
	var file := FileAccess.open(TRANSLATIONS_PATH, FileAccess.READ)
	if not file:
		return
	var header := file.get_csv_line()
	if header.size() < 2:
		return
	var translations_by_col: Dictionary = {}
	for col in range(1, header.size()):
		var loc: String = header[col].strip_edges()
		if available_locales.has(loc):
			var tr_obj := Translation.new()
			tr_obj.locale = loc
			translations_by_col[col] = tr_obj
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 2:
			continue
		var key := row[0].strip_edges()
		if key.is_empty():
			continue
		for col in translations_by_col:
			if col < row.size():
				var text := row[col].strip_edges()
				if not text.is_empty():
					translations_by_col[col].add_message(key, text)
	for col in translations_by_col:
		TranslationServer.add_translation(translations_by_col[col])

func _load_compiled_translations() -> void:
	for loc in available_locales:
		var path := TRANSLATIONS_PATH.get_basename() + ".%s.translation" % loc
		if ResourceLoader.exists(path):
			var t = load(path)
			if t is Translation:
				TranslationServer.add_translation(t)

func set_locale(locale: String, remember: bool = true) -> void:
	if not locale in available_locales:
		return
	current_locale = locale
	TranslationServer.set_locale(locale)
	# Se recuerda en la carpeta del usuario. Antes se guardaba en project.godot:
	# en la app instalada no se puede escribir («Couldn't save project.godot»)
	# y el idioma elegido se perdía al reiniciar.
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(CONFIG_PATH)
		cfg.set_value("ui", "locale", locale)
		cfg.save(CONFIG_PATH)
	language_changed.emit(locale)
	if get_tree():
		get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)

func get_locale_name(locale: String) -> String:
	return available_locales.get(locale, locale)

func get_locale_list() -> Array:
	return available_locales.keys()
