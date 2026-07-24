shader_type canvas_item;

// Colores e información geométrica
uniform vec4 fill_color : source_color = vec4(0.88, 0.88, 0.88, 1.0);
uniform vec4 stroke_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float stroke_width_px = 2.0; // Grosor en píxeles reales

void fragment() {
    // Centramos las coordenadas (0.0 a 1.0) para que el centro sea (0.5, 0.5)
    vec2 uv = UV - 0.5;
    
    // Distancia al centro (SDF de un círculo)
    float dist = length(uv) * 2.0;
    
    // fwidth() detecta cuánto cambia la distancia entre píxeles de pantalla
    // Esto es lo que hace que sea nítido incluso con zoom de 5000%
    float anti_alias = fwidth(dist);
    
    // Calculamos el grosor del borde proporcional al tamaño
    float half_stroke = (stroke_width_px * anti_alias);
    
    // Máscara del borde exterior e interior
    float outer_edge = smoothstep(1.0 + anti_alias, 1.0 - anti_alias, dist);
    float inner_edge = smoothstep(1.0 - half_stroke + anti_alias, 1.0 - half_stroke - anti_alias, dist);
    
    float stroke_mask = outer_edge - inner_edge;
    float fill_mask = inner_edge;
    
    // Mezcla final de colores
    vec4 color_out = mix(vec4(0.0), stroke_color, stroke_mask);
    color_out = mix(color_out, fill_color, fill_mask);
    
    // Si el píxel está fuera del círculo, no pintamos nada
    if (color_out.a < 0.01) discard;
    
    COLOR = color_out;
}