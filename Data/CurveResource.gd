@tool
class_name CurveResource
extends Resource

# Puntos de anclaje (Anchor Points)
@export var points: PackedVector2Array = [Vector2(0.0, 1.0), Vector2(1.0, 0.0)]
# Palancas de control (Handles) - Desplazamiento relativo al punto
@export var handles_in: PackedVector2Array = [Vector2(0,0), Vector2(-0.2, 0)]
@export var handles_out: PackedVector2Array = [Vector2(0.2, 0), Vector2(0,0)]

@export var curve_type: int = 0 # 0: Linear, 1: Bezier, etc.
