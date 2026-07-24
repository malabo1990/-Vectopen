extends Node
class_name CalculadoraNumeros

# --- CONFIGURACIÓN EXPORTADA ---
@export var lista_botones_numeros: Array[Button] 
@export var lineedit_entrada: LineEdit
@export var lineedit_salida: LineEdit
@export var boton_borrar: Button
@export var boton_punto: Button
@export var barra_progreso: ProgressBar

# --- VARIABLES INTERNAS ---
var _valor_actual: String = "0"

func _ready():
	# Conectar botones de números (0-9)
	for i in range(lista_botones_numeros.size()):
		if lista_botones_numeros[i] != null:
			lista_botones_numeros[i].pressed.connect(_on_numero_presionado.bind(i))
	
	# Conectar botones de función
	if boton_borrar:
		boton_borrar.pressed.connect(_on_borrar_presionado)
	
	if boton_punto:
		boton_punto.pressed.connect(_on_punto_presionado)
	
	# Conectar cambios de texto - SEÑAL EN TIEMPO REAL
	if lineedit_entrada:
		lineedit_entrada.text_changed.connect(_on_texto_cambiado)
	
	# Inicializar
	_set_valor_interno("0")

# ============================================
# 🔧 FUNCIONES GET/SET PARA OTROS SCRIPTS
# ============================================

# Obtener el valor actual (para otros scripts)
func get_valor() -> String:
	return _valor_actual

# Obtener el valor como número (float)
func get_valor_numerico() -> float:
	if _valor_actual.is_valid_float():
		return _valor_actual.to_float()
	return 0.0

# Establecer el valor desde otro script (ej: drag horizontal)
func set_valor(nuevo_valor: String):
	_set_valor_interno(nuevo_valor)

# Establecer el valor numérico desde otro script
func set_valor_numerico(nuevo_valor: float):
	_set_valor_interno(str(nuevo_valor))

# ============================================
# 🔄 FUNCIÓN INTERNA DE ACTUALIZACIÓN
# ============================================

func _set_valor_interno(nuevo_texto: String):
	# Validar que solo contenga números y punto
	var texto_limpio = _limpiar_texto(nuevo_texto)
	
	# Actualizar variable interna
	_valor_actual = texto_limpio if texto_limpio != "" else "0"
	
	# Actualizar AMBOS LineEdit en tiempo real
	if lineedit_entrada:
		lineedit_entrada.text = _valor_actual
		lineedit_entrada.caret_column = lineedit_entrada.text.length()
	
	if lineedit_salida:
		lineedit_salida.text = _valor_actual
	
	# Actualizar ProgressBar
	_actualizar_barra_progreso()

func _limpiar_texto(texto: String) -> String:
	# Permitir solo números y un punto decimal
	var resultado = ""
	var tiene_punto = false
	
	for caracter in texto:
		if caracter == "." and not tiene_punto:
			resultado += caracter
			tiene_punto = true
		elif caracter.is_valid_int():
			resultado += caracter
	
	return resultado

func _actualizar_barra_progreso():
	if barra_progreso:
		var valor_numerico = 0.0
		if _valor_actual.is_valid_float():
			valor_numerico = _valor_actual.to_float()
		
		var valor_seguro = clamp(valor_numerico, barra_progreso.min_value, barra_progreso.max_value)
		barra_progreso.value = valor_seguro

# ============================================
# 🎯 SEÑALES DE LOS BOTONES
# ============================================

func _on_numero_presionado(indice_numero):
	var nuevo_texto = _valor_actual
	if nuevo_texto == "0" and indice_numero != 0:
		nuevo_texto = str(indice_numero)
	elif nuevo_texto == "0" and indice_numero == 0:
		nuevo_texto = "0"
	else:
		nuevo_texto += str(indice_numero)
	
	_set_valor_interno(nuevo_texto)
	
	if lineedit_entrada:
		lineedit_entrada.grab_focus()

func _on_borrar_presionado():
	if _valor_actual.length() > 1:
		var nuevo_texto = _valor_actual.substr(0, _valor_actual.length() - 1)
		_set_valor_interno(nuevo_texto)
	else:
		_set_valor_interno("0")
	
	if lineedit_entrada:
		lineedit_entrada.grab_focus()

func _on_punto_presionado():
	if "." not in _valor_actual:
		_set_valor_interno(_valor_actual + ".")
	
	if lineedit_entrada:
		lineedit_entrada.grab_focus()

# ============================================
# 📝 SEÑAL DE CAMBIO DE TEXTO (TIEMPO REAL)
# ============================================

func _on_texto_cambiado(_nuevo_texto: String):  # ⚠️ Prefijo _ para evitar warning
	if lineedit_entrada:
		# Esto permite que cambios externos (drag, otro script) se sincronicen
		_set_valor_interno(lineedit_entrada.text)
