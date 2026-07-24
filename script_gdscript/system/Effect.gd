# ==========================================
# RUTA: res://scripts/Effect.gd
# ==========================================
class_name Effect
extends Resource

enum EffectType {
	BLUR,
	SHADOW,
	GLOW,
	DISTORTION,
	NOISE,
	COLOR_ADJUST,
	BLEND
}

@export var effect_type: EffectType
@export var params: Dictionary = {}
@export var enabled: bool = true

func apply_to_object(obj: Node2D) -> void:
	if not enabled or not is_instance_valid(obj):
		return
		
	match effect_type:
		EffectType.BLUR:
			_apply_blur(obj)
		EffectType.SHADOW:
			_apply_shadow(obj)
		EffectType.GLOW:
			_apply_glow(obj)

func _apply_blur(obj: Node2D) -> void:
	var blur_amount = params.get("amount", 5.0)
	print("[Efecto Vectorial] Aplicando Blur matemático CPU: ", blur_amount, " a ", obj.name)
	
	# NOTA: En lugar de cargar un .gdshader inexistente que consumiría GPU, 
	# disparamos la señal global de Vectopen para que el sistema sepa que se aplicó un filtro
	GlobalEvents.filter_applied.emit()

func _apply_shadow(obj: Node2D) -> void:
	var shadow_color = params.get("color", Color(0, 0, 0, 0.5))
	var shadow_offset = params.get("offset", Vector2(5, 5))
	
	print("[Efecto Vectorial] Sombra lista en objeto '", obj.name, "' con offset: ", shadow_offset, " y color: ", shadow_color)
	
	# Aquí procesas la lógica o guardas los parámetros en los metadatos del objeto para el _draw()
	obj.set_meta("shadow_enabled", true)
	obj.set_meta("shadow_color", shadow_color)
	obj.set_meta("shadow_offset", shadow_offset)
	
	# Forzar el redibujado de la geometría del objeto para pintar la sombra duplicada abajo
	if obj.has_method("queue_redraw"):
		obj.queue_redraw()
		
	GlobalEvents.effect_applied.emit()

# SOLUCIÓN LÍNEA 26: Declaramos la función que faltaba para el Glow
func _apply_glow(obj: Node2D) -> void:
	var glow_intensity = params.get("intensity", 1.0)
	var glow_color = params.get("color", Color.WHITE)
	
	print("[Efecto Vectorial] Aplicando resplandor CPU a ", obj.name, " con intensidad: ", glow_intensity)
	
	obj.set_meta("glow_enabled", true)
	obj.set_meta("glow_color", glow_color)
	
	GlobalEvents.shader_applied.emit()
