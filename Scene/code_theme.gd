# Editor code Vectopen
extends CodeEdit

func _ready() -> void:
	# 1. Configuración de Estilo y Comportamiento General
	setup_editor_settings()
	
	# 2. Configuración del Tema Visual (Calcado de tu captura de pantalla)
	setup_godot_theme_colors()
	
	# 3. Configuración del Resaltador de Sintaxis y Auto-completado de GDScript
	setup_gdscript_highlighter_and_autocomplete()


func setup_editor_settings() -> void:
	# Comportamiento y visualización idéntica al editor de la foto
	draw_tabs = true
	draw_spaces = false
	line_folding = true
	minimap_draw = true
	highlight_current_line = true
	highlight_all_occurrences = true
	
	# Estilo de líneas, sangrado y cierre automático de símbolos
	indent_size = 4
	indent_automatic = true
	auto_brace_completion_enabled = true
	
	# Mostrar números de línea y área de plegado (gutters)
	gutters_draw_line_numbers = true
	gutters_draw_fold_gutter = true
	
	# --- SISTEMA DE AUTO-COMPLETADO ---
	code_completion_enabled = true
	code_completion_prefixes = [" ", ".", "(", "[", ","]


func setup_godot_theme_colors() -> void:
	# Paleta exacta de tu captura (Estilo Gris Carbón / Charcoal de Godot)
	var charcoal_bg = Color("#1e1e1e")         # Fondo gris oscuro/negro de tu editor
	var charcoal_font = Color("#e0e0e0")       # Texto plano y nombres de funciones definidas
	var charcoal_selection = Color("#363636")  # Color de selección sutil
	var charcoal_current_line = Color("#2a2a2a")# Resaltado de la línea actual
	var charcoal_numbers_bg = Color("#1a1a1a")  # Fondo del gutter de números (¡Ya se usa abajo!)
	
	# Aplicar colores de fondo y texto al nodo
	add_theme_color_override("background_color", charcoal_bg)
	add_theme_color_override("font_color", charcoal_font)
	add_theme_color_override("font_selected_color", Color("#ffffff"))
	add_theme_color_override("selection_color", charcoal_selection)
	
	# Personalizar guías de línea, números laterales y fondo del gutter
	add_theme_color_override("current_line_color", charcoal_current_line)
	add_theme_color_override("line_number_color", Color("#606060"))
	add_theme_color_override("line_number_background_color", charcoal_numbers_bg)
	add_theme_color_override("word_highlighted_color", Color("#2d2d2d"))
	
	# Minimapa perfectamente integrado
	add_theme_color_override("minimap_background_color", charcoal_bg)


func setup_gdscript_highlighter_and_autocomplete() -> void:
	var highlighter = CodeHighlighter.new()
	
	# Colores extraídos directamente de la sintaxis de tu foto
	var color_keyword = Color("#ff5f70")    # Rojo/Rosa de 'func', 'extends', 'true', 'false'
	var color_functions = Color("#57b3ff")  # Azul brillante de las funciones llamadas
	var color_comment = Color("#666666")    # Gris oscuro para los comentarios
	var color_type = Color("#42b883")       # Verde esmeralda para tipos de nodos y void
	
	# Mapeo seguro con nombres únicos para solucionar el Shadowed Variable Error
	var COMPLETION_KEYWORD = 4
	var COMPLETION_FUNCTION = 3
	var COMPLETION_MEMBER = 1
	
	# 1. Palabras clave (Keywords de tu foto)
	var keywords = [
		"extends", "class_name", "const", "var", "onready", "func",
		"if", "elif", "else", "for", "while", "match", "switch",
		"break", "continue", "pass", "return", "signal", "enum",
		"export", "static", "as", "is", "in", "and", "or", "not",
		"true", "false"
	]
	for keyword in keywords:
		highlighter.add_keyword_color(keyword, color_keyword)
		add_code_completion_option(COMPLETION_KEYWORD, keyword, keyword)
		
	# 2. Funciones llamadas (Azules en tu foto)
	var builtins = [
		"setup_editor_settings", "setup_godot_theme_colors", "setup_gdscript_highlighter_and_autocomplete",
		"print", "print_rich", "get_node", "connect", "emit_signal"
	]
	for builtin in builtins:
		highlighter.add_keyword_color(builtin, color_functions)
		add_code_completion_option(COMPLETION_FUNCTION, builtin, builtin)
	
	# 3. Tipos y Clases (Verdes en tu foto)
	var types = [
		"CodeEdit", "void", "int", "float", "String", "bool", "Array", "Dictionary",
		"Vector2", "Vector3", "Color", "Rect2", "Node", "Object"
	]
	for type_item in types:
		highlighter.add_keyword_color(type_item, color_type)
		add_code_completion_option(COMPLETION_MEMBER, type_item, type_item)
	
	# 4. Reglas de aislamiento para Comentarios (Gris en tu foto)
	highlighter.add_color_region("#", "", color_comment, true)
	
	# Cadenas de texto comunes (Naranja suave)
	highlighter.add_color_region('"', '"', Color("#ffb357"), false)
	highlighter.add_color_region("'", "'", Color("#ffb357"), false)
	
	# Aplicar el sistema de resaltado personalizado al CodeEdit
	self.set_syntax_highlighter(highlighter)


# Conector para actualizar las sugerencias del menú flotante al escribir
func _on_text_changed() -> void:
	request_code_completion()
