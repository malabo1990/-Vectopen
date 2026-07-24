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
	var saved = ProjectSettings.get_setting(SETTINGS_KEY, "en")
	set_locale(saved)

func _load_translation_file() -> void:
	var base_path = TRANSLATIONS_PATH.get_basename()
	var loaded := 0
	for locale in available_locales:
		var path = base_path + "." + locale + ".translation"
		var translation = load(path) as Translation
		if translation:
			TranslationServer.add_translation(translation)
			loaded += 1
		else:
			push_warning('LanguageManager: No se pudo cargar traducción para "%s": %s' % [locale, path])
	if loaded == 0:
		push_warning("LanguageManager: No se cargó ninguna traducción")

func set_locale(locale: String) -> void:
	if not locale in available_locales:
		return
	current_locale = locale
	TranslationServer.set_locale(locale)
	ProjectSettings.set_setting(SETTINGS_KEY, locale)
	ProjectSettings.save()
	language_changed.emit(locale)
	if get_tree():
		get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)

func get_locale_name(locale: String) -> String:
	return available_locales.get(locale, locale)

func get_locale_list() -> Array:
	return available_locales.keys()
