# VECTOPEN

## VGSE — Vectopen Geometric Stroke Engine

### Informe conceptual y propuesta técnica

**Proyecto:** Vectopen
**Motor principal:** Godot Engine
**Subsistema propuesto:** Vectopen Geometric Stroke Engine (VGSE)
**Tipo de tecnología:** Motor vectorial de trazados, pinceles, materiales y efectos
**Estado:** Propuesta conceptual y técnica
**Promotor:** Casimiro Ondo Obiang Ayevegue
**Fecha:** Noviembre de 2026

---

# 1. Resumen ejecutivo

Se propone desarrollar **VGSE (Vectopen Geometric Stroke Engine)**, un sistema avanzado de trazados vectoriales integrado en Vectopen y basado en las capacidades de renderizado 2D de Godot Engine.

El objetivo es transformar el concepto tradicional de Stroke. En lugar de representar únicamente una línea con un grosor, color y estilo, VGSE permitirá que cada Stroke funcione como un objeto vectorial inteligente al que se puedan aplicar diferentes tipos de geometría, pinceles, patrones, objetos, textos, materiales, shaders, máscaras, filtros y efectos.

El usuario podrá dibujar una trayectoria y modificar posteriormente su geometría, apariencia y comportamiento sin perder la trayectoria original.

La propuesta contempla un sistema no destructivo, modular y extensible que separa la geometría del trazado, el contenido del pincel, los materiales, las máscaras y los efectos de renderizado.

VGSE aspira a convertirse en una de las tecnologías diferenciadoras de Vectopen, especialmente en el ámbito de la creación y edición avanzada de trazados vectoriales.

# 2. Visión conceptual

La mayoría de los flujos de trabajo vectoriales distinguen entre la trayectoria (Path), el contorno (Stroke) y el relleno (Fill).

VGSE propone ampliar esta concepción: el Stroke podrá contener y combinar diferentes elementos visuales y geométricos.

Un único trazado podrá utilizar:

- Geometría de anchura constante o variable.
- Pinceles vectoriales personalizados.
- Patrones y objetos distribuidos a lo largo de una trayectoria.
- Texto y otros trazados como contenido.
- Colores sólidos, degradados y texturas.
- Materiales y shaders de Godot.
- Máscaras vectoriales y de opacidad.
- Efectos geométricos y filtros visuales.
- Combinaciones de diferentes operaciones.

La trayectoria original seguirá siendo editable. Los resultados generados serán representaciones derivadas de sus parámetros, no sustitutos de la información original.

**Principio fundamental:** cualquier Stroke debe poder evolucionar visualmente sin obligar al usuario a reconstruir su trayectoria desde cero.

# 3. Objetivos principales

## 3.1. Objetivo general

Crear un motor de trazados vectoriales avanzado que unifique geometría, pinceles, contenido, materiales, máscaras y efectos dentro de un sistema modular integrado con Godot Engine.

## 3.2. Objetivos específicos

1. Implementar geometría de trazados con anchura variable y control de presión.
2. Permitir pinceles vectoriales basados en formas y objetos personalizados.
3. Distribuir patrones, símbolos y elementos vectoriales a lo largo de una trayectoria.
4. Utilizar otros Paths y textos como contenido del Stroke.
5. Integrar materiales y shaders 2D de Godot.
6. Crear un sistema de máscaras y recortes.
7. Incorporar filtros y efectos encadenables.
8. Mantener la edición no destructiva.
9. Permitir la ampliación mediante nuevos pinceles, materiales, shaders y efectos.
10. Optimizar el procesamiento y la visualización mediante CPU y GPU.

# 4. Arquitectura funcional

VGSE estará dividido en módulos independientes que compartirán un modelo de datos común.

## 4.1. Geometric Stroke Engine

Responsable de construir y modificar la geometría del trazado.

Funciones:

- Stroke de anchura constante.
- Variable Width Stroke.
- Control de anchura mediante nodos.
- Presión de tableta gráfica.
- Inclinación y orientación del lápiz.
- Taper inicial y final.
- Curvas Bézier.
- Generación de contornos mediante offsets.
- Uniones: Miter, Round y Bevel.
- Terminaciones: Butt, Round y Square.
- Detección y resolución de autointersecciones.
- Deformación y escultura del trazado.
- Conversión de geometría derivada a Paths editables.

El sistema debe conservar el trazado central como fuente principal de información.

## 4.2. Vector Brush Engine

Permitirá utilizar diferentes fuentes de contenido para construir la apariencia de un Stroke.

Tipos de pincel previstos:

- Basic Brush.
- Variable Width Brush.
- Calligraphy Brush.
- Pressure Brush.
- Ribbon Brush.
- Pattern Brush.
- Object Brush.
- Multi-Object Brush.
- Text Brush.
- Custom Vector Brush.

Parámetros principales:

- Tamaño.
- Anchura.
- Espaciado.
- Rotación.
- Escala.
- Orientación respecto al trazado.
- Dispersión.
- Variación aleatoria controlada.
- Sensibilidad a presión e inclinación.
- Deformación del contenido.
- Repetición y distribución de elementos.

El contenido de un pincel podrá proceder de un objeto vectorial, un conjunto de objetos, una forma personalizada o un recurso reutilizable.

## 4.3. Pattern Along Path Engine

Permitirá distribuir elementos siguiendo una trayectoria.

Ejemplos de uso:

- Repetir símbolos e iconos.
- Crear bordes decorativos.
- Distribuir hojas, estrellas o figuras.
- Colocar elementos industriales o mecánicos.
- Construir líneas ornamentales.
- Repetir formas con variaciones de escala y rotación.
- Crear patrones con separación y orientación personalizadas.

El motor deberá calcular la posición de cada elemento mediante la longitud de arco del trazado, evitando depender exclusivamente del parámetro matemático de la curva.

Deberá contemplar:

- Separación constante.
- Distribución por cantidad.
- Distribución proporcional.
- Alineación tangencial.
- Alineación normal.
- Escala progresiva.
- Rotación personalizada.
- Desplazamiento lateral.
- Variaciones de tamaño y posición.

## 4.4. Path y Text Integration Engine

VGSE permitirá utilizar otros elementos vectoriales como contenido de un Stroke.

Funciones previstas:

**Path as Brush**

- Utilizar un trazado como fuente de pincel.
- Repetirlo siguiendo otra trayectoria.
- Adaptar su orientación y escala.
- Mantener una referencia al objeto original.

**Text on Path**

- Colocar texto siguiendo una trayectoria.
- Controlar orientación y alineación.
- Modificar espaciado entre caracteres.
- Ajustar posición inicial y final.

**Text as Brush**

- Utilizar texto como contenido distribuido a lo largo de una trayectoria.
- Controlar repetición, separación, orientación y escala.

**Object as Stroke**

- Utilizar una forma vectorial como representación del trazado.
- Crear elementos decorativos o técnicos.
- Permitir que el objeto fuente se actualice sin reconstruir manualmente el Stroke.

Es importante mantener diferenciadas las operaciones de texto sobre trayectoria y texto utilizado como pincel.

## 4.5. Paint and Material Engine

Controlará la apariencia cromática y los materiales aplicados al Stroke.

Características:

- Color sólido.
- Transparencia.
- Degradado lineal.
- Degradado radial.
- Degradados con múltiples puntos de control.
- Texturas.
- Pattern Fill.
- Materiales personalizados.
- Modos de mezcla.
- Variaciones de color a lo largo del trazado.

El sistema deberá permitir aplicar materiales sin modificar la geometría original.

## 4.6. Shader Engine

Permitirá utilizar materiales y shaders 2D de Godot sobre los trazados.

Posibilidades:

- Shaders personalizados.
- Distorsión.
- Ruido.
- Brillo.
- Efectos de iluminación.
- Variaciones de color.
- Deformación visual.
- Animación de parámetros.
- Desplazamiento de texturas.
- Efectos dependientes de coordenadas UV.

La arquitectura deberá ofrecer parámetros editables desde el Inspector de Vectopen.

Se deberá distinguir entre los shaders que modifican únicamente la apariencia y los algoritmos que alteran realmente la geometría vectorial.

## 4.7. Mask Engine

Sistema para controlar la visibilidad y composición del Stroke.

Tipos previstos:

- Alpha Mask.
- Vector Mask.
- Clipping Path.
- Máscara de imagen.
- Máscara basada en otro objeto.
- Máscara invertida.
- Máscaras combinadas.
- Máscaras con transparencia.

Debe permitir utilizar otros elementos del documento como fuentes de máscara, conservando referencias editables cuando sea posible.

## 4.8. Effects and Filters Engine

Permitirá aplicar efectos de manera independiente y encadenada.

Efectos visuales:

- Blur.
- Glow.
- Drop Shadow.
- Inner Shadow.
- Noise.
- Displacement.
- Distortion.
- Color Adjustment.
- Opacity.
- Texture Effects.

Efectos geométricos:

- Offset.
- Expand.
- Contract.
- Taper.
- Twist.
- Wave.
- Roughen.
- Simplify.
- Morph.
- Deform.

Los efectos geométricos deberán generar nuevas representaciones de la geometría, mientras que los filtros visuales podrán procesarse durante el renderizado.

El usuario podrá activar, desactivar, reorganizar y modificar los parámetros de cada efecto.

# 5. Modelo de datos no destructivo

Uno de los elementos más importantes de VGSE será conservar la información original.

Se propone utilizar un modelo de datos similar al siguiente:

```text
StrokeModel
│
├── SourcePath
│   ├── Anchors
│   ├── BézierHandles
│   └── Closed
│
├── InputSamples
│   ├── Position
│   ├── Pressure
│   ├── Tilt
│   ├── Azimuth
│   └── Timestamp
│
├── Geometry
│   ├── WidthProfile
│   ├── WidthKnots
│   ├── Caps
│   ├── Joins
│   └── OffsetSettings
│
├── Brush
│   ├── BrushType
│   ├── SourceObject
│   ├── Pattern
│   ├── Spacing
│   └── Distribution
│
├── Paint
│   ├── Color
│   ├── Gradient
│   ├── Texture
│   └── BlendMode
│
├── ShaderMaterial
│   └── Parameters
│
├── MaskStack
│
└── EffectsStack
    ├── Effect
    ├── Parameters
    └── Enabled
```

La estructura definitiva deberá adaptarse al sistema de escenas, recursos y serialización que utiliza Vectopen.

## 5.1. Separación entre modelo y resultado

VGSE deberá mantener tres niveles:

1. **Source Model:** trayectoria, muestras, anchura y parámetros originales.
2. **Derived Geometry:** contornos y elementos vectoriales generados.
3. **Render Cache:** mallas, buffers, texturas y resultados temporales para la visualización.

Esta separación permitirá actualizar únicamente los componentes afectados cuando el usuario cambie un parámetro.

Por ejemplo, cambiar el color no debería obligar a recalcular las curvas Bézier y sus offsets.

# 6. Integración con Godot Engine

Godot será responsable de la interfaz, la gestión del documento y el renderizado 2D.

Tecnologías y recursos que se estudiarán:

| Tecnología | Aplicación |
|---|---|
| CanvasItem | Renderizado de elementos 2D |
| CanvasItem Shader | Materiales y efectos visuales |
| ShaderMaterial | Parámetros de materiales personalizados |
| ArrayMesh / Mesh | Geometría personalizada |
| RenderingServer | Gestión avanzada del renderizado |
| SubViewport | Procesamiento y composición intermedia |
| ViewportTexture | Texturas generadas mediante Viewports |
| GDExtension | Integración de módulos nativos |
| InputEvent | Captura de entrada y tableta, según compatibilidad |

La implementación deberá aprovechar las capacidades existentes de Godot y evitar duplicar funciones innecesariamente.

## 6.1. Arquitectura híbrida

Se recomienda mantener:

**Godot**

- Interfaz de usuario.
- Inspector.
- Gestión de documentos.
- Herramientas de dibujo.
- Visualización.
- Gestión de escenas y recursos.

**VGSE Core**

- Geometría vectorial.
- Cálculo de offsets.
- Curvas y normales.
- Anchura variable.
- Distribución de patrones.
- Deformación geométrica.
- Detección de intersecciones.

**GPU**

- Vista previa de trazados.
- Shaders.
- Materiales.
- Filtros visuales.
- Composición y máscaras cuando resulte eficiente.

El núcleo geométrico podrá implementarse en C++ o Rust mediante una interfaz estable de integración con Godot.

No es necesario reescribir Vectopen en otro lenguaje.

# 7. API conceptual

Se propone diseñar una API interna que permita ampliar el motor sin modificar toda su arquitectura.

Ejemplo conceptual:

```text
StrokeModel
    create_path()
    set_width_profile()
    set_pressure_samples()
    set_brush()
    set_paint()
    set_shader()
    add_mask()
    add_effect()
    rebuild_geometry()
    update_render_cache()

BrushResource
    set_source_object()
    set_spacing()
    set_rotation_mode()
    set_scale_mode()
    set_distribution()

EffectResource
    set_parameters()
    set_enabled()
    update()

StrokeResult
    outline_paths
    generated_objects
    preview_mesh
    diagnostics
```

Las funciones son una propuesta de diseño, no una API existente de Godot.

# 8. Flujo de trabajo del usuario

El funcionamiento esperado será:

1. El usuario dibuja una trayectoria con ratón o tableta gráfica.
2. VGSE registra posición, presión, inclinación y tiempo cuando estén disponibles.
3. El motor procesa y suaviza la trayectoria.
4. Se genera la geometría del Stroke.
5. El usuario selecciona un pincel o contenido vectorial.
6. Configura color, degradado, patrón o material.
7. Puede añadir un shader.
8. Aplica máscaras y efectos.
9. Modifica los parámetros desde el Inspector.
10. El sistema actualiza el resultado conservando el modelo original.

El usuario podrá volver a modificar el trazado, cambiar el pincel o reorganizar los efectos sin perder el trabajo anterior.

# 9. Rendimiento y optimización

El motor deberá diseñarse pensando en documentos complejos y edición interactiva.

Estrategias:

- Muestreo adaptativo de curvas.
- Caché de geometría.
- Actualización incremental.
- Separación entre cálculo y renderizado.
- Reutilización de recursos.
- Instanciación de elementos repetidos cuando sea viable.
- Procesamiento GPU para tareas visuales apropiadas.
- Cálculo CPU para operaciones geométricas que requieran precisión.
- Actualización selectiva de efectos y materiales.

Se deberán realizar pruebas con trazados de 1.000, 10.000 y 100.000 muestras, midiendo memoria, tiempo de generación y fluidez de edición.

Objetivo de rendimiento inicial: mantener una experiencia interactiva fluida, con una referencia de 60 FPS y una actualización de vista previa de aproximadamente 16,6 ms por fotograma en el escenario de prueba definido.

No se debe prometer este rendimiento hasta validar los prototipos en hardware real.

# 10. Diferenciación tecnológica

VGSE no pretende afirmar que ninguna otra aplicación tenga pinceles vectoriales, patrones, trazados de anchura variable, máscaras o efectos.

Existen antecedentes y soluciones parciales en diferentes herramientas:

- Inkscape incorpora PowerStroke y efectos de trayectoria.
- Los editores de fuentes utilizan técnicas de trazado variable y plumillas.
- SVG contempla trazados, patrones, degradados y filtros.
- Los motores gráficos permiten utilizar shaders y materiales.

La oportunidad de Vectopen está en desarrollar una arquitectura unificada que integre estas capacidades en un único sistema de edición interactivo.

Los principales elementos diferenciadores que se pretenden explorar son:

1. Un Stroke como contenedor de múltiples tipos de contenido.
2. Integración de geometría editable y pinceles vectoriales.
3. Uso de Paths, objetos y textos como fuentes de pincel.
4. Integración de shaders y materiales de Godot.
5. Sistema de máscaras y efectos encadenados.
6. Edición no destructiva desde una única estructura.
7. Extensibilidad mediante recursos y módulos propios.
8. Interacción con tableta gráfica y perfiles de presión.

La diferenciación no dependerá de una sola herramienta, sino de la integración y coherencia de todo el sistema.

# 11. Plan de desarrollo

## Fase 1 — Geometric Stroke Core

- Modelo de datos Stroke.
- Generación de offsets.
- Anchura variable.
- Perfiles de presión.
- Caps y joins.
- Gestión de cúspides.
- Detección de autointersecciones.

**Resultado:** motor geométrico funcional.

## Fase 2 — Vector Brush System

- Basic Brush.
- Calligraphy Brush.
- Variable Width Brush.
- Pattern Brush.
- Object Brush.
- Multi-Object Brush.
- Distribución y orientación por longitud de arco.

**Resultado:** pinceles vectoriales avanzados.

## Fase 3 — Path and Text Integration

- Path as Brush.
- Text on Path.
- Text as Brush.
- Referencias a objetos.
- Actualización de contenido fuente.

**Resultado:** utilización de elementos del documento como contenido de Stroke.

## Fase 4 — Paint and Shader System

- Colores.
- Degradados.
- Texturas.
- Materiales.
- Shaders personalizados.
- Parámetros editables.

**Resultado:** apariencia visual avanzada.

## Fase 5 — Mask and Effects System

- Máscaras.
- Recortes.
- Efectos geométricos.
- Filtros visuales.
- Composición de efectos.
- Caché y actualización incremental.

**Resultado:** sistema completo de composición y efectos para Stroke.

## Fase 6 — Optimización y extensibilidad

- Optimización CPU/GPU.
- Pruebas de rendimiento.
- Gestión de recursos.
- Serialización.
- Compatibilidad de documentos.
- Sistema de extensiones y pinceles personalizados.

**Resultado:** VGSE integrado en Vectopen como subsistema estable.

# 12. Riesgos técnicos y consideraciones

El desarrollo presenta retos que deben estudiarse antes de comprometer la arquitectura definitiva:

- Autointersecciones en geometría de anchura variable.
- Cúspides y discontinuidades en curvas.
- Precisión de offsets en curvas cerradas.
- Distribución uniforme de elementos mediante longitud de arco.
- Gestión de transformaciones y escalas.
- Compatibilidad entre geometría vectorial y shaders.
- Coste de filtros y máscaras complejas.
- Sincronización de las actualizaciones CPU/GPU.
- Entrada de presión e inclinación de diferentes tabletas.
- Gestión de memoria y cachés.

También será necesario diferenciar los resultados vectoriales editables de los efectos que, por su naturaleza, se renderizan como texturas.

No todos los efectos visuales podrán convertirse automáticamente en geometría vectorial editable. Esta limitación deberá quedar clara en el diseño del sistema.

# 13. Criterios de validación

VGSE deberá superar pruebas funcionales antes de considerarse estable.

**Geometría**

- Curvas rectas, circulares y Bézier.
- Curvas cerradas.
- Curvas con cúspides.
- Cambios bruscos de anchura.
- Autointersecciones.
- Presión variable.

**Pinceles**

- Distribución de objetos.
- Separación constante.
- Rotación siguiendo la tangente.
- Escala variable.
- Actualización de la fuente original.

**Materiales y efectos**

- Degradados.
- Shaders.
- Máscaras.
- Filtros.
- Efectos combinados.
- Actualización sin pérdida de geometría.

**Edición**

- Deshacer y rehacer.
- Modificar anchura después de dibujar.
- Cambiar el pincel después de dibujar.
- Editar el objeto fuente.
- Guardar y recuperar documentos.
- Mantener la edición no destructiva.

# 14. Resultado esperado

El resultado será un subsistema propio de Vectopen que amplíe significativamente las posibilidades de creación y edición de trazados vectoriales.

VGSE permitirá que un Stroke sea mucho más que una línea: podrá convertirse en una cinta, un pincel, un patrón, una composición de objetos, un texto sobre trayectoria o una estructura visual con materiales, máscaras y efectos.

La arquitectura modular facilitará incorporar nuevas tecnologías sin reconstruir el motor desde cero.

**Visión final:**

Vectopen no solo ofrecerá herramientas para dibujar trazados vectoriales. Permitirá construir, transformar, combinar y personalizar objetos visuales completos a partir de cualquier trayectoria.

---

**Conclusión**

VGSE representa una línea de desarrollo tecnológico con potencial para diferenciar a Vectopen frente a los editores vectoriales tradicionales.

Su valor principal será la integración de geometría, contenido vectorial, pinceles, materiales, shaders y efectos dentro de un único sistema editable, modular y no destructivo, aprovechando Godot Engine como plataforma de renderizado e interacción.
