shader_type canvas_item;

// Smart Cursor Shader para Vectopen
// Dibuja un cursor personalizado con formas, colores y animaciones

uniform int shape : hint_range(0, 5) = 0; // 0: Rounded Triangle, 1: Circle, 2: Crosshair, 3: Hand, 4: I-Beam, 5: Custom
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float size = 24.0;
uniform float pulse_factor = 1.0;
uniform float halo_factor = 0.0;
uniform float rotation_angle = 0.0;
uniform bool accessibility_mode = false;

// Parámetros de estilo
uniform float border_width = 1.5;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shadow_opacity = 0.3;
uniform float shadow_offset = 2.0;

// Función para calcular distancia a un triángulo
float sdTriangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
    vec2 e0 = p1 - p0;
    vec2 e1 = p2 - p1;
    vec2 e2 = p0 - p2;
    
    vec2 v0 = p - p0;
    vec2 v1 = p - p1;
    vec2 v2 = p - p2;
    
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    
    return -sqrt(d.x) * sign(d.y);
}

void fragment() {
    // Obtener coordenadas UV
    vec2 uv = UV;
    
    // Aplicar rotación
    if (rotation_angle != 0.0) {
        float cos_a = cos(rotation_angle);
        float sin_a = sin(rotation_angle);
        uv = (uv - 0.5) * mat2(vec2(cos_a, sin_a), vec2(-sin_a, cos_a)) + 0.5;
    }
    
    // Calcular tamaño final con pulso
    float final_size = size * pulse_factor;
    
    // Normalizar UV según el tamaño
    vec2 center = vec2(0.5);
    vec2 pos = (uv - center) * vec2(final_size, final_size) * 2.0;
    
    // Dibujar según la forma
    float alpha = 0.0;
    
    if (shape == 0) { // Rounded Triangle
        // Triángulo redondeado
        vec2 p0 = vec2(0.0, -0.4);
        vec2 p1 = vec2(-0.35, 0.2);
        vec2 p2 = vec2(0.35, 0.2);
        
        // Distancia a los bordes del triángulo
        float d = sdTriangle(pos, p0, p1, p2);
        
        // Redondear las esquinas
        float radius = 0.1;
        d = smoothstep(0.0, radius, d);
        
        // Borde
        float border = smoothstep(radius, radius - border_width/size, abs(d));
        
        alpha = 1.0 - d;
        
        // Aplicar color
        if (d < 0.5) {
            COLOR = color;
        } else {
            COLOR = border_color;
        }
        
        // Modo accesibilidad: patrón de líneas
        if (accessibility_mode && d < 0.5) {
            float pattern = sin(pos.x * 20.0) * sin(pos.y * 20.0);
            if (pattern > 0.5) {
                COLOR = vec4(1.0) - color;
            }
        }
    }
    else if (shape == 1) { // Circle
        float d = length(pos);
        float radius = 0.4;
        
        alpha = 1.0 - smoothstep(radius - 0.01, radius, d);
        
        // Borde
        float border = smoothstep(radius, radius - border_width/size, d);
        
        if (d < radius) {
            COLOR = color;
        } else {
            COLOR = border_color;
        }
    }
    else if (shape == 2) { // Crosshair (se maneja con el cursor del sistema)
        discard;
    }
    else if (shape == 3) { // Hand (se maneja con el cursor del sistema)
        discard;
    }
    else if (shape == 4) { // I-Beam (se maneja con el cursor del sistema)
        discard;
    }
    else if (shape == 5) { // Custom
        // Forma personalizada (ejemplo: estrella)
        float d = length(pos);
        float angle = atan(pos.y, pos.x);
        
        // Crear forma de estrella
        float star = abs(sin(5.0 * angle) * 0.2);
        float radius = 0.4 + star;
        
        alpha = 1.0 - smoothstep(radius - 0.01, radius, d);
        
        if (d < radius) {
            COLOR = color;
        }
    }
    
    // Añadir halo de interacción
    if (halo_factor > 0.0) {
        float halo_radius = 0.6 + halo_factor * 0.3;
        float halo = smoothstep(halo_radius, halo_radius - 0.05, length(pos));
        halo *= halo_factor;
        
        // Mezclar con el color existente
        COLOR.rgb = mix(COLOR.rgb, vec3(1.0), halo * 0.5);
    }
    
    // Aplicar sombra
    if (alpha > 0.0) {
        vec2 shadow_pos = pos + vec2(shadow_offset, shadow_offset);
        float shadow_alpha = alpha * shadow_opacity;
        
        // Dibujar sombra
        if (shape == 0) { // Rounded Triangle
            float d = sdTriangle(shadow_pos, vec2(0.0, -0.4), vec2(-0.35, 0.2), vec2(0.35, 0.2));
            float radius = 0.1;
            d = smoothstep(0.0, radius, d);
            shadow_alpha *= 1.0 - d;
        }
        else if (shape == 1) { // Circle
            float d = length(shadow_pos);
            float radius = 0.4;
            shadow_alpha *= 1.0 - smoothstep(radius - 0.01, radius, d);
        }
        
        // Mezclar sombra
        if (shadow_alpha > 0.0) {
            vec4 shadow_color = vec4(0.0, 0.0, 0.0, shadow_alpha);
            COLOR = mix(COLOR, shadow_color, shadow_alpha);
        }
    }
    
    // Aplicar alpha
    COLOR.a = alpha;
}