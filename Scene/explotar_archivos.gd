extends Tree

# --- Variables Exportadas para Personalización Visual ---
@export_category("Estética de Interfaz")
@export var color_carpeta: Color = Color("e0a96d")
@export var color_archivo: Color = Color("ffffff")
@export var color_texto_detalles: Color = Color("8e8e93")

enum ModoVista { DETALLES, ICONOS }
var modo_actual: ModoVista = ModoVista.DETALLES
var filtro_busqueda: String = ""

func _ready() -> void:
	self.item_collapsed.connect(_on_item_collapsed)
	cambiar_modo_vista(ModoVista.DETALLES)

func cambiar_modo_vista(nuevo_modo: ModoVista) -> void:
	modo_actual = nuevo_modo
	if modo_actual == ModoVista.DETALLES:
		self.columns = 3
		self.set_column_custom_minimum_width(0, 250)
		self.set_column_clip_content(0, true)
	else:
		self.columns = 1
	
	actualizar_explorador()

func actualizar_explorador() -> void:
	self.clear()
	
	if modo_actual == ModoVista.DETALLES:
		self.set_column_title(0, "Nombre")
		self.set_column_title(1, "Tamaño")
		self.set_column_title(2, "Última Modificación")
		self.set_column_titles_visible(true)
	else:
		self.set_column_titles_visible(false)
		
	var desktop_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	
	var root: TreeItem = self.create_item()
	if root == null: return
	
	root.set_text(0, "Escritorio")
	root.set_metadata(0, desktop_path)
	
	if filtro_busqueda != "":
		agregar_nodos_recursivo(desktop_path, root)
	else:
		cargar_contenido_carpeta(desktop_path, root)

# --- CARGA SUPERFICIAL (Segura contra bloqueos de hilos) ---
func cargar_contenido_carpeta(ruta_carpeta: String, item_padre: TreeItem) -> void:
	if item_padre == null: return
	
	# Eliminamos los hijos antiguos de forma segura
	var hijos = item_padre.get_children()
	for hijo in hijos:
		hijo.free()
		
	var dir = DirAccess.open(ruta_carpeta)
	if dir:
		dir.list_dir_begin()
		var nombre = dir.get_next()
		
		while nombre != "":
			if nombre != "." and nombre != "..":
				var ruta_completa = ruta_carpeta + "/" + nombre
				var es_dir = dir.current_is_dir()
				
				var sub_item: TreeItem = self.create_item(item_padre)
				if sub_item == null:
					nombre = dir.get_next()
					continue # Si el motor sigue ocupado, pasa al siguiente de forma segura
					
				sub_item.set_text(0, nombre)
				sub_item.set_metadata(0, ruta_completa)
				
				if es_dir:
					sub_item.set_custom_color(0, color_carpeta)
					sub_item.set_selectable(0, true)
					
					sub_item.collapsed = true
					var item_falso = self.create_item(sub_item)
					if item_falso:
						item_falso.set_text(0, "Cargando...")
					
					if modo_actual == ModoVista.DETALLES:
						sub_item.set_text(1, "--")
						sub_item.set_text(2, "Carpeta de archivos")
						sub_item.set_custom_color(1, color_texto_detalles)
						sub_item.set_custom_color(2, color_texto_detalles)
				else:
					sub_item.set_custom_color(0, color_archivo)
					if modo_actual == ModoVista.DETALLES:
						sub_item.set_text(1, dar_formato_tamano(ruta_completa))
						sub_item.set_text(2, dar_formato_fecha(ruta_completa))
						sub_item.set_custom_color(1, color_texto_detalles)
						sub_item.set_custom_color(2, color_texto_detalles)
						
			nombre = dir.get_next()
		dir.list_dir_end()

# --- RECURSIVIDAD PARA BÚSQUEDAS ---
func agregar_nodos_recursivo(ruta_actual: String, item_padre: TreeItem) -> void:
	var dir = DirAccess.open(ruta_actual)
	if dir:
		dir.list_dir_begin()
		var nombre = dir.get_next()
		while nombre != "":
			if nombre != "." and nombre != "..":
				var ruta_completa = ruta_actual + "/" + nombre
				var es_dir = dir.current_is_dir()
				
				if nombre.to_lower().contains(filtro_busqueda.to_lower()):
					var sub_item: TreeItem = self.create_item(item_padre)
					if sub_item != null:
						sub_item.set_text(0, nombre)
						sub_item.set_metadata(0, ruta_completa)
						if es_dir:
							sub_item.set_custom_color(0, color_carpeta)
						else:
							sub_item.set_custom_color(0, color_archivo)
				
				if es_dir:
					agregar_nodos_recursivo(ruta_completa, item_padre)
			nombre = dir.get_next()
		dir.list_dir_end()

# --- SEÑAL AL EXPANDIR (CORREGIDA CON CALL_DEFERRED) ---
func _on_item_collapsed(item: TreeItem) -> void:
	if not item.collapsed:
		var ruta_guardada = item.get_metadata(0)
		if ruta_guardada and DirAccess.dir_exists_absolute(ruta_guardada):
			# TRUCO DE RENDIMIENTO: Postergamos la carga al siguiente frame.
			# Así el árbol termina de animarse y "blocked" vuelve a ser 0.
			call_deferred("cargar_contenido_carpeta", ruta_guardada, item)

# --- FORMATEROS AUXILIARES ---
func dar_formato_tamano(ruta: String) -> String:
	var f = FileAccess.open(ruta, FileAccess.READ)
	if f:
		var bytes = f.get_length()
		if bytes < 1024: 
			return str(bytes) + " B"
		elif bytes < 1024 * 1024: 
			return str(round(bytes / 1024.0)) + " KB"
		else: 
			return str(snapped(bytes / (1024.0 * 1024.0), 0.01)) + " MB"
	return "0 B"

func dar_formato_fecha(ruta: String) -> String:
	var unix_time = FileAccess.get_modified_time(ruta)
	var datetime = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d/%02d/%04d %02d:%02d" % [datetime.day, datetime.month, datetime.year, datetime.hour, datetime.minute]
