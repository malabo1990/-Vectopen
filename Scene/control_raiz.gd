extends PanelContainer

# --- Variables Exportadas para asignar en el Inspector ---
@export_category("Conexiones de Nodos")
@export var search_bar: LineEdit
@export var file_tree: Tree
@export var btn_details: Button
@export var btn_icons: Button

func _ready() -> void:
	# Verificación de seguridad inicial
	if not search_bar or not file_tree or not btn_details or not btn_icons:
		print("⚠️ Error: Por favor, asigna todos los nodos en el Inspector del PanelContainer.")
		return
		
	# Conectar las señales de la barra de búsqueda y botones
	search_bar.text_changed.connect(_on_search_bar_text_changed)
	
	btn_details.pressed.connect(func(): file_tree.cambiar_modo_vista(file_tree.ModoVista.DETALLES))
	btn_icons.pressed.connect(func(): file_tree.cambiar_modo_vista(file_tree.ModoVista.ICONOS))
	
	# Forzar la primera carga de datos en el árbol
	file_tree.actualizar_explorador()

func _on_search_bar_text_changed(nuevo_texto: String) -> void:
	# Pasar el filtro al árbol de archivos y refrescar la vista al escribir
	file_tree.filtro_busqueda = nuevo_texto
	file_tree.actualizar_explorador()
