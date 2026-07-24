# Renderizado Vectorial en Godot 4 — Guía Técnica para Vectopen

## 1. El Problema: Curvas "en Escalera"

En Godot, las líneas curvas se ven escalonadas porque:

1. **Godot renderiza vectores como polígonos rasterizados** — convierte curvas en triángulos/textura
2. **El monitor tiene píxeles cuadrados** — una línea diagonal siempre se aproxima
3. **Sin anti-aliasing, cada píxel es o 100% color o 0%** → escalones visibles

El anti-aliasing (AA) suaviza esto haciendo que los píxeles del borde tengan opacidad parcial.

---

## 2. Renderers de Godot 4

Godot 4 tiene 3 renderers backend:

### 2.1 gl_compatibility (OpenGL 3.3 / GLES 3.0)
| Aspecto | Valor |
|---------|-------|
| **MSAA 2D** | ❌ No soportado (el error que ves) |
| **Performance** | Alta (GPU vieja) |
| **Usa** | Hardware mínimo, Web export, móvil viejo |
| **AA disponible** | FXAA en 3D, 2D no tiene |

### 2.2 forward+ (Vulkan)
| Aspecto | Valor |
|---------|-------|
| **MSAA 2D** | ✅ x2, x4, x8, x16 |
| **Performance** | Excelente |
| **Usa** | PC, consolas, calidad máxima |
| **AA disponible** | MSAA + FXAA + TAA |

### 2.3 mobile (Vulkan)
| Aspecto | Valor |
|---------|-------|
| **MSAA 2D** | ✅ x2, x4 |
| **Performance** | Balanceada |
| **Usa** | Android/iOS |

**Conclusión 1:** Cambiar a `forward+` habilita MSAA 2D y las curvas se ven suaves al instante.

---

## 3. Anti-Aliasing (AA) — Tipos

### 3.1 MSAA (Multisample Anti-Aliasing)
- **Cómo funciona**: Toma varias muestras por píxel y promedia
- **Calidad**: Muy buena (x4, x8)
- **Costo**: Alto (x8 = 8x más trabajo de GPU)
- **Godot**: `Project Settings > Rendering > Anti Aliasing > Quality > MSAA 2D`
- **Mejor para**: Escenas 3D con geometría, también mejora 2D

### 3.2 FXAA (Fast Approximate AA)
- **Cómo funciona**: Post-process que detecta bordes y los suaviza
- **Calidad**: Aceptable, bordes un poco borrosos
- **Costo**: Muy bajo
- **Godot**: `Project Settings > Rendering > Anti Aliasing > Quality > Screen Space AA`
- **Mejor para**: Cuando MSAA es muy caro

### 3.3 TAA (Temporal AA)
- **Cómo funciona**: Usa frames anteriores para suavizar
- **Calidad**: Muy buena, pero puede tener ghosting
- **Costo**: Medio
- **Godot**: `Project Settings > Rendering > Anti Aliasing > Quality > Use TAA`
- **Mejor para**: Escenas estáticas o con movimiento lento

### 3.4 SSAA (Super-Sampling AA)
- **Cómo funciona**: Renderiza a resolución más alta, escala hacia abajo
- **Calidad**: Perfecta
- **Costo**: Altísimo (4K renderizado para 1080p)
- **No recomendado** para Vectopen

### 3.5 Custom Shader AA
- **Cómo funciona**: Shader que aplica anti-aliasing analítico en bordes de primitivas
- **Calidad**: Depende del shader
- **Costo**: Bajo a medio
- **Control total**: Podés implementar tu propio algoritmo

**Comparativa visual:**

| Método | Calidad | Performance | Implementación |
|--------|---------|-------------|----------------|
| MSAA x4 | ⭐⭐⭐⭐ | Medio | 1 clic en settings |
| MSAA x8 | ⭐⭐⭐⭐⭐ | Bajo | 1 clic |
| TAA | ⭐⭐⭐⭐ | Alto | 1 clic |
| FXAA | ⭐⭐⭐ | Muy alto | 1 clic |
| Custom shader | ⭐⭐⭐⭐⭐ | Medio | Requiere código |

---

## 4. Renderizado Vectorial vs Rasterizado

### 4.1 Rasterizado (Godot nativo)
```
Curva vectorial → Triángulos → Píxeles
```
- Godot convierte todo a triángulos
- Las curvas se aproximan con segmentos rectos
- La calidad depende de la cantidad de segmentos
- Más segmentos = más suave pero más lento

**Settings que afectan:**
```gdscript
# En el dibujo de curvas (draw_arc, draw_circle, etc.)
draw_arc(center, radius, start, end, segments, color)
# Más segments = curva más suave
```

### 4.2 Vectorial puro (Skia, Cairo, NanoVG, Blend2D)
```
Curva vectorial → Fragment shader → Píxel perfecto
```
- No aproxima con triángulos
- Calcula el color de cada píxel analíticamente
- Anti-aliasing por sub-píxel nativo
- Curvas perfectas sin escalones

---

## 5. Implementación Práctica para Vectopen

### Opción A: Cambiar a forward+ (más simple)
```
Project Settings > Rendering > Renderer > forward+
Rendering > Anti Aliasing > Quality > MSAA 2D > x4
```

**Ventajas:** 1 cambio de config, MSAA funciona  
**Desventajas:** No es vectorial puro, las curvas siguen siendo aproximaciones poligonales

### Opción B: GDExtension + Librería Vectorial
```
Godot (UI) ←→ GDExtension (C++) ←→ Skia/Blend2D/NanoVG ←→ OpenGL/Vulkan
```

**Arquitectura recomendada:**
```
┌─────────────────────────────────────────┐
│  Godot Editor (UI, events, scene tree)   │
│  ┌───────────────────────────────────┐  │
│  │ TextureRect (muestra el canvas)   │  │
│  │   ↑ textura cada frame            │  │
│  └───────────────────────────────────┘  │
│              ↕ GDExtension               │
│  ┌───────────────────────────────────┐  │
│  │ Motor Vectorial (Blend2D/Skia)    │  │
│  │ - Renderiza curvas perfectas      │  │
│  │ - Anti-aliasing nativo            │  │
│  │ - Dash arrays, strokes, gradients │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**Flujo por frame:**
1. Godot detecta input (mouse)
2. Pasa coordenadas a la GDExtension
3. Motor vectorial renderiza curvas a un buffer
4. Buffer se copia a una textura Godot (ViewportTexture o ImageTexture)
5. TextureRect muestra el resultado

### Opción C: Shader-based vector rendering (custom)
Podés escribir shaders que dibujen curvas analíticamente:

```glsl
// Fragment shader para curva bezier
// Cada píxel calcula su distancia a la curva
// y aplica anti-aliasing según la distancia
void fragment() {
    float dist = sd_bezier(UV, control_points);
    float alpha = 1.0 - smoothstep(0.0, 1.0/SCREEN_PIXEL_SIZE, abs(dist));
    COLOR = vec4(stroke_color, alpha);
}
```

**Ventajas:** Sin dependencias externas  
**Desventajas:** Extremadamente complejo para curvas arbitrarias, performance variable

---

## 6. Performance de Scripts

### 6.1 Cuello de botella CPU (GDScript)
GDScript es interpretado, no compilado. Operaciones intensivas:

| Operación | Costo |
|-----------|-------|
| Llamadas a función | Alto (dynamic dispatch) |
| Loops grandes (>1000 iteraciones) | Alto |
| `get_node()` frecuente | Medio |
| Asignación de Variant | Medio |
| Cálculos matemáticos simples | Bajo |

**Recomendaciones para Vectopen:**
- El **loop de dibujo** debe ser en C++ (GDExtension) o en fragment shader
- GDScript maneja UI, eventos, lógica de herramientas — no renderizado
- Usar `PackedVector2Array` en vez de `Array[Vector2]` para datos densos
- Evitar `get_node()` en loops — cachear referencias
- Usar `@onready` para todo nodo que se accede frecuentemente

### 6.2 Cuello de botella GPU
| Factor | Impacto |
|--------|---------|
| MSAA x4 | 4x más píxeles a procesar |
| Cantidad de curvas | Draw calls |
| Tamaño de texturas | Memoria |
| Shaders complejos | Instrucciones por píxel |

### 6.3 Llamadas al RenderingServer
En vez de nodos, podés operar directamente sobre el `RenderingServer`:

```gdscript
# En vez de CanvasItem (nodet)
var ci = RenderingServer.canvas_item_create()
RenderingServer.canvas_item_set_parent(ci, canvas)
RenderingServer.canvas_item_add_line(ci, from, to, color)
```

Esto es ~10x más rápido que usar nodos para draw calls masivos.

---

## 7. Recomendación Final

### Para Vectopen hoy:
1. **Cambiar a `forward+`** — solución inmediata, MSAA 2D funciona
2. **Reducir MSAA a x4** — balance calidad/performance

### Para Vectopen a futuro (calidad profesional):
1. **Implementar GDExtension con Blend2D** — open source (zlib), moderna, rápida
2. **El canvas renderiza en un buffer off-screen** via GDExtension
3. **Godot solo muestra el resultado** en un TextureRect
4. **Anti-aliasing nativo de Blend2D** — curvas perfectas siempre
5. **Sin dependencia del renderer de Godot** — funciona en gl_compatibility y forward+

### Stack recomendado:
```
┌────────────────────────────────────────────┐
│  Godot 4.7 (forward+)                       │
│  ├── UI: Control nodes (menús, paneles)     │
│  ├── Lógica: GDScript (tools, eventos)      │
│  └── Render: GDExtension (Blend2D C++)      │
│       └── Anti-aliasing: nativo (sub-pixel) │
│       └── Curvas: bezier analíticas         │
│       └── Strokes: dash arrays, caps, joins │
└────────────────────────────────────────────┘
```

### Tabla comparativa de calidad visual:

| Método | Curva suave? | Anti-aliasing | Performance | Esfuerzo |
|--------|-------------|---------------|-------------|----------|
| `gl_compatibility` + sin AA | ❌ Escalones | ❌ | ✅ Alto | 0 |
| `forward+` MSAA x4 | ✅ Mejorada | ✅ Bueno | 🟡 Medio | 5 min |
| `forward+` MSAA x8 | ✅ Muy buena | ✅ Muy bueno | 🔴 Bajo | 5 min |
| Custom shader AA | ✅✅ Suave | ✅✅ Bueno | ✅ Alto | 2-3 días |
| GDExtension + Blend2D | ✅✅✅ Perfecta | ✅✅✅ Excelente | ✅ Alto | 2-4 semanas |

---

## 8. Recursos

- **Blend2D**: https://blend2d.com/ (zlib license, open source)
- **Skia**: https://skia.org/ (Apache 2.0, open source)
- **NanoVG**: https://github.com/memononen/nanovg (zlib license)
- **Godot Rendering docs**: https://docs.godotengine.org/en/stable/tutorials/rendering/

---
*Documentado por: Agente de Desarrollo — Julio 2026*
