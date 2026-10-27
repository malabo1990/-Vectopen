// Silueta de una imagen para su sombra (LayerFx): blanco con el alfa de la
// textura; el CanvasGroup de la sombra la desenfoca y la tiñe.
shader_type canvas_item;

void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * COLOR.a);
}
