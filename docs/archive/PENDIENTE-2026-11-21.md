# PENDIENTE — Lo que queda por hacer

**Proyecto:** Vectopen (Godot 4.7, GDScript)
**Fecha:** 2026-11-21 · versión publicada: **0.2.3-beta** · preparada sin
publicar: **0.2.4-beta** (etiqueta `v0.2.4-beta` subida; release cancelada a la
espera de terminar este documento)
**Solo trabajo abierto.** Lo terminado sale de este documento: la versión
completa anterior (Fase A UX-01…UX-24, REG-01…03, DBG-01…11 y la Fase B
hasta el encargo 10, con todas sus resoluciones) está en
`docs/archive/PENDIENTE-2026-11-02.md` y en el historial de git.

---

## 0. Modo de trabajo (`/loop`)

Un encargo o incidencia por iteración:
`reproducir → prueba que falla → corregir → prueba en verde → suite unitaria → commit`.

- Los defectos de severidad **alta o media** se corrigen en la misma iteración,
  en un commit aparte, antes de aprobar el encargo; los **bajos** se acumulan
  en el §2.
- Pruebas e2e en la Huion (`--screen 1`) con ajustes de fábrica; suite
  unitaria (`bash test/run_unit.sh`) en verde antes de cada commit.
- Al cerrar algo, **se quita de este documento** (queda en git).

---

## 0 bis. Tanda del usuario (2026-11-03) — en curso

| ID | Petición | Estado |
|---|---|---|
| USR-01 | Smart: quitar abajo-izquierda Shader/Script/Vectorizar/Complementos (repetidos en Efectos) | Hecho (`c2ea826`) |
| USR-02 | Texto y párrafo: duplicar con Alt + arrastrar (y Ctrl+D / pegar) | Hecho (`c905ecc`) |
| USR-03 | Panel «Teclado y ratón»: corregir y mejorar la UI | Hecho: pestañas Atajos/Teclado/Ratón, categorías, nombres traducidos (10 idiomas), aviso ⚠ de tecla repetida, tema claro y oscuro (`keyboard_panel_e2e` 28/0) |
| USR-04 | Teclado simulado: ver qué teclas tienen atajo y cuáles están libres | Hecho: teclado simulado con modificadores; colores configurable/fijo/repetido/libre; clic en una tecla ocupada la busca en Atajos |
| USR-05 | Pinceles: el trazo se ve regular → mejorar la calidad (VGSE fase 1) | Hecho: borde con antialias por sombreador (1 px a cualquier zoom), opacidad del trazo compuesta en grupo (sin manchas en cruces, uniones ni puntas), vista previa con el mismo render que el trazo final (`brush_quality_e2e`) |
| USR-06 | VGSE (`docs/roadmap/VGSE-…md`): plan por fases, empezar por la fase 1 | Fases 1–6 hechas salvo los puntos «Pendiente» del §0 ter |

**Tanda 2 (2026-11-03, prueba de un cliente):**

| ID | Petición | Estado |
|---|---|---|
| USR-07 | Doble clic / «Abrir con» abre en Vectopen: vtp, svg, eps, ai, pdf, Affinity…; Vectopen el primero de la lista (por encima de Inkscape) | Hecho: la app abre el archivo que recibe al arrancar (`LaunchFiles`); paquetes con tipos de archivo (.desktop + `vectopen.xml`, Info.plist en macOS); Ajustes ▸ Archivos ▸ «Hacer Vectopen la app predeterminada» (Linux: xdg-mime; Windows: «Abrir con» + .vtp) |
| USR-08 | Estilos del pincel (lápiz, rotulador, aerógrafo, caligráfico) se ven mal mientras se dibuja | Hecho: todos con el render de calidad (en vivo y al soltar); grano, tinta y aerógrafo en el sombreador, sin imágenes; caligráfico = geometría por ángulo de plumilla |
| USR-09 | Panel Pincel: diseño compacto, sin deslizadores (ya hay casillas numéricas); que no quede tapado por abajo | Hecho: estilos arriba, grosor/opacidad en una fila, presión resumida con casillas; siempre dentro de la ventana (se desplaza por dentro si no cabe); muestra los valores reales del pincel (`brush_panel_theme_e2e` 95/0) |
| USR-10 | Al salir (o apagar) avisar si hay cambios sin guardar | Hecho: cada paso del historial marca el documento; al cerrar (X, Alt+F4, cerrar sesión) guarda solo o pregunta Guardar / No guardar / Cancelar, y antes deja copia en Recuperar |
| USR-11 | Guardado automático continuo de los proyectos .vtp (como Figma / Penpot) | Hecho: .vtp con nombre se guarda solo 2 s después de cada cambio (espera a soltar el ratón); sin nombre → copia en Recuperar. Ajustes ▸ Archivos |
| USR-12 | Historial de deshacer hasta 1000 pasos | Hecho (configurable en Ajustes ▸ Archivos, 10–5000) |

## 0 ter. VGSE — Vectopen Geometric Stroke Engine (plan por fases)

Documento: `docs/roadmap/VGSE-informe-conceptual-y-propuesta-tecnica.md`.
Proyecto grande: se avanza por fases, cada una con pruebas propias, sin
romper documentos existentes (el Line2D sigue siendo el modelo guardado).

**Fase 1 — Núcleo geométrico** (hecha)

| Punto | Estado |
|---|---|
| Anchura variable + perfiles de presión (meta `stroke_profile`, editable en Trazos) | Existía |
| Remates (plano / redondo / cuadrado) y uniones (inglete / redonda / bisel) | Existía (`StrokeGeom`) |
| Offsets (`offset_line`, doble / triple / vía) | Existía |
| Cúspides: giro cerrado → unión redonda sin pico infinito | Existía |
| Borde con antialias a cualquier zoom (sombreador) | Hecho (`c996e1b`) |
| Autointersecciones al pintar: trazo semitransparente sin manchas | Hecho (`c996e1b`) |
| Vista previa = render final | Hecho (`c996e1b`) |
| Convertir trazo en contorno (Ctrl+Mayús+O / menú): figura rellena editable con la misma forma | Hecho |
| Perfil de anchura medido sobre el trazado ajustado (no sobre las muestras crudas) | Hecho: cada muestra se proyecta sobre el trazado ajustado (`arc_on_path`); el engorde queda donde se apretó |
| Modelo Stroke: fuente / derivado / caché separados (sin cambiar el formato) | Hecho: la geometría derivada (eje, malla, UV) va en caché con clave de forma; color, opacidad y degradado solo repintan (`BrushStrokeGeomCache_test`) |

**Fase 2 — Pinceles vectoriales** (en curso)

| Punto | Estado |
|---|---|
| Básico, caligráfico, anchura variable (presión) | Existía (pluma, caligráfico, perfiles) |
| Pincel de objeto: la selección (o estrella / hoja / punto) estampada a lo largo del trazo; tamaño con la presión, giro con el trazo, separación, dispersión | Hecho (`object_brush.gd`, estilo «Objeto» del panel; `object_brush_e2e`) |
| Multiobjeto: varias figuras una a una o al azar (semilla guardada) | Hecho |
| Distribución por longitud de arco | Hecho (estampas por distancia, no por puntos) |
| Pincel de patrón: la figura se repite y se DOBLA siguiendo la curva; teselas que encajan justas | Hecho (casilla «Patrón: doblar con la curva») |
| Convertir trazo de objeto / patrón en figuras sueltas (Ctrl+Mayús+O) | Hecho (grupo de figuras con sus colores, con deshacer) |
| Antialias del borde de las estampas | No hace falta: MSAA 2D 8× del proyecto |
| Patrón con piezas distintas de inicio / esquina / final (como Illustrator) | Pendiente |
**Fase 3 — Trazado y texto** (en curso)

| Punto | Estado |
|---|---|
| Trazado como pincel (Bézier, polígonos, trazos, grupos con «Selección») | Hecho |
| Texto como pincel (letras con sus huecos; con «Patrón» se doblan) | Hecho |
| Texto en trazado: una vez, apoyado en la curva, alineado (inicio / centro / final), desplazamiento, al otro lado | Hecho (menú contextual con texto + trazado; `text_on_path_e2e`) |
| Referencias: el texto en trazado se rehace al editar el texto o cambiar la curva; se guarda el enlace | Hecho |
| Panel para alinear / desplazar / dar la vuelta a un texto en trazado ya creado | Hecho: inspector de Modern y Pro («En el trazado», «Desplazamiento», «Al otro lado»), con deshacer |
**Fase 4 — Pintura y shaders** (en curso)

| Punto | Estado |
|---|---|
| Color, transparencia, degradado 2D (lineal / radial, varias paradas), degradado a lo largo | Existía |
| Sombreador propio con parámetros y filtros por trazo de pincel | Existía (comprobado: `brush_paint_e2e`) |
| Texturas dentro del trazo: lienzo, papel, rayas, puntos; siguen el trazo o el papel; escala e intensidad (inspector, con deshacer, se guarda) | Hecho |
| Variación de color a lo largo del trazo (tono y luz, solo pintura) | Hecho (inspector «Variación de color») |
| Texturas desde una imagen del usuario | Hecho («Textura ▸ Imagen…»). Límite: se guarda la RUTA (si la imagen se mueve o se comparte el .vtp, sale «papel»); incrustarla en el documento queda pendiente |
| Modos de fusión del panel Capas (Multiplicar, Pantalla, Superponer, Aclarar, Oscurecer, Diferencia) | Hecho (2026-11-21): `blend_modes.gd` — Multiplicar nativo, el resto con sombreador que lee lo de detrás; grupos y textos heredan; deshacer, .vtp y PNG (`blend_modes_e2e` 16/0). Pendiente: llevarlos al SVG (`mix-blend-mode`) y al PDF (`/BM`); si el objeto ya tiene desenfoque o shader propio, ese manda |
**Fase 5 — Máscaras y efectos** (en curso)

| Punto | Estado |
|---|---|
| Máscara de recorte con trazos de pincel dentro | Existía (comprobado: `brush_mask_fx_e2e`) |
| Sombras / efectos en trazos de pincel (TextFx) | Existían (comprobado) |
| Efectos geométricos del trazo: ondulado, zigzag, rugoso (forma real: contorno, sombra, exportar) | Hecho (inspector «Forma del trazo», amplitud, tamaño de onda) |
| Caché de geometría (solo se rehace lo que cambia) | Hecho en fase 1 + malla nativa |
| Composición (modos de fusión) | Hecho (ver fase 4) |
**Fase 6 — Optimización y extensiones** (en curso)

Un trazo con N muestras (`test/e2e/stroke_samples_bench.gd`, sin ventana):

| Muestras | pluma | lápiz | aerógrafo |
|---|---|---|---|
| 1 000 | 0,9 ms | 1,7 ms | 2,6 ms (antes 8,5) |
| 10 000 | 7 ms | 16 ms | 17 ms (antes 51) |
| 100 000 | 79 ms | 160 ms | 59 ms (antes 101) |

| Punto | Estado |
|---|---|
| Pruebas de rendimiento de documentos (N elementos) y de trazos (N muestras) | Hecho (`scene_benchmark_e2e`, `stroke_samples_bench`) |
| Aerógrafo: sellos y colores en Rust (`stroke_stamps`, `colors_from_alpha`) | Hecho |
| Lápiz: opacidad por vértice en Rust y en caché (16 → 9,6 ms con 10 000) | Hecho |
| Trazos de 100 000 muestras al dibujar: rehacer solo la cola (incremental) | Pendiente |
| Serialización / compatibilidad (trazos antiguos sin metas nuevas) | Hecho (`BrushStrokeCompat_test`) |
| Pinceles personalizados guardados («Mis pinceles») | Hecho: tarjeta del panel Pincel (guardar con nombre, un clic para usarlo, × para borrar; `brush_presets_e2e`) |

Validación (§13 del documento): rectas, círculos, Bézier, cerradas, cúspides,
cambios bruscos de anchura, autointersecciones, presión; deshacer/rehacer,
cambiar anchura y pincel después de dibujar, guardar y recuperar.

---

## 0 quater. Tanda nocturna (2026-11-09): rendimiento, escala de la UI, VGSE 4–6

**Rendimiento** (`scene_benchmark_e2e`, `E2E_ENV="BENCH_N=… BENCH_MODE=high|low"`):

| N | crear | cargar | fps todo visible (alta / baja) | fps zoom | memoria |
|---|---|---|---|---|---|
| 1 000 | 0,25 s | 0,3 s | 194 / 264 | 78 | 290 MB |
| 5 000 | 1,3 s | 1,5 s | 38 / 54 | 23 | 412 MB |
| 10 000 | 2,2 s (antes 63 s) | 2,4 s (antes 25 s) | 50 (antes 21) | 15 | 509 MB |
| 50 000 (baja) | 15 s | 12 s | 9,6 (antes 4) | 6,5 | 1,5 GB (antes 1,8) |

| Punto | Estado |
|---|---|
| Panel de Capas congelaba con miles de capas (fotogramas de 2–4 s) | Hecho (`133477a`): grupos grandes por demanda, tandas de 200 |
| Guardar / cargar no pierde elementos | Comprobado (mismo recuento antes y después) |
| Memoria ~31 KB por elemento (50 000 → 2 GB: no cabe en un PC de 2 GB) | En curso: texto 83 → 39 KB (editor en línea por demanda). Figuras ~22 KB y trazos ~24 KB: sin una causa única (1 nodo, 4 objetos por figura; script con 49 variables + órdenes de dibujo); rebajarlo exige rehacer la estructura de VectorShape — **decidir si merece la pena** (50 000 en modo débil hoy: 1,5 GB) |
| Dibujar con todo a la vista (50 000 → 3 fps) y zoom: nivel de detalle / caché al alejar | En curso: 10 000 visibles 21 → 52 fps (lápiz sin grupo salvo pliegues; CullManager conectado a la cámara, textos sin _process con la vista quieta). Quedan ~1,8 llamadas de dibujo por elemento |
| CullManager: «dormir» páginas lejanas (stream_artboards) | Apagado: nunca funcionó (no tenía cámara); activarlo cambia mucho el comportamiento — probar con documentos de muchas páginas antes |
| Seleccionar todo (50 000 → 5 s) y mover la selección (630 ms por paso) | En curso: el inspector usa una muestra con miles de objetos (current_props 617 → 34 ms con 10 000; fotograma tras seleccionar 967 → 382 ms). Mover 10 000 seleccionadas: 110 → ~10 ms por fotograma (sin contorno por figura por encima de 300) |

**Escala de la interfaz**: hecho — `ui_scale.gd` (automática por escala del
sistema / DPI / tamaño; Ajustes ▸ Interfaz 80–200 %; Ctrl+Alt+= / - / 0; aviso;
`VECTOPEN_UI_SCALE` para pruebas; `ui_scale_e2e` 10/0). Un solo control para
toda la UI (los 382 tamaños de letra fijados a mano impiden un «solo texto» fiable).

## 0 quinquies. Tanda del usuario (2026-11-09, día): precisión de editor profesional

| ID | Petición | Estado |
|---|---|---|
| USR-20 | Smart: «Texto en trazado» en el clic derecho | Hecho (`84a2650`): `smart_menu_extras.gd` (sin tocar `clickrigth_nodo.gd`) |
| USR-21 | Texto en trazado deformado, separado al principio y amontonado al final | Hecho (`84a2650`): letras rígidas sobre su línea base real (mediana del pie de las letras) |
| USR-22 | Tamaño, espaciado, inicio/final y tiradores como Illustrator/Affinity | Hecho (`84a2650`): ▶ ◀ ◆ en el lienzo, filas del inspector (Modern y Pro), deshacer de un paso |
| USR-23 | Texto debajo del trazo y modo espejo | Hecho (`84a2650`): Posición encima/debajo/centrado, Invertir dirección, Espejo |
| USR-24 | Con el texto ya en el trazo no funcionaba el panel de texto | Hecho (`84a2650`): InspectorCore redirige fuente, peso, cursiva, tamaño, color y letras avanzadas al texto de origen |
| USR-25 | Tamaño de la UI sin teclado (tableta) | Hecho (`3c92d44`): Configuración ▸ Ventana con − / + / lista / Auto; modo y tamaño de ventana como botones |
| USR-26 | Nodos y tiradores enormes con mucho zoom; línea roja y marca azul gruesas | Hecho (`f488564`): tamaños en px de pantalla; estilo Affinity |
| USR-27 | Edición de nodos sin historial | Hecho (`f488564`): cada gesto es un paso de deshacer/rehacer |
| USR-28 | Nodo nuevo deforma la línea | Hecho (`f488564`): De Casteljau (desviación < 0,15 px) |
| USR-29 | Relleno incompleto / parpadeante en contornos que se cruzan | Hecho (`f488564`): regla «no cero» con unión de Clipper, sin errores en el depurador |
| USR-30 | Recuadro enorme y corrido con mucho zoom; selección por recuadro | Hecho (`8bf358f`): caja exacta, sin redondeo de Godot; clic y marquee por la forma |
| USR-31 | No se podía arrastrar tras seleccionar | Hecho (`8bf358f`): la caja deja pasar el ratón durante el gesto; tallo del giro sin clic |
| USR-32 | Con zoom > 3000 % bordes poligonales y trazos finos transparentes; grosor mínimo 0,5 | Hecho (`f68e88f`): limpieza de puntos ≤ 2 % del tamaño; grosor mínimo = 1 px de pantalla; campos de grosor hasta 0,005 con paso adaptativo; Mayús + arrastre proporcional |
| USR-33 | «Este brush también necesita trazos para poder mover» → editar sus nodos | Hecho: doble clic en un trazo de pincel (o herramienta Nodos) edita una curva Bézier ajustada a él (pocos nodos); los puntos se regeneran y la presión se conserva; deshacer también después de salir (`brush_nodes_e2e`) |
| USR-34 | Zoom ≈ 190 000 %: Mayús + arrastrar no cambiaba el grosor, paneles sin el valor al momento, redondeo «0», tiradores borrosos | Hecho: Mayús + clic quieto deselecciona y Mayús + arrastrar ajusta (umbrales en px de pantalla, también Alt + arrastrar); aviso en vivo a los paneles; decimales según el valor en todos los campos y en la píldora del recuadro; W/H desde 0,0001; arrastre de campos según el zoom; bordes de tiradores y líneas de guía en px de pantalla (`extreme_zoom_ui_e2e`) |

Pruebas nuevas: `text_path_ui_e2e`, `settings_ui_e2e`, `node_handles_zoom_e2e`,
`node_undo_e2e`, `fill_cross_e2e`, `fill_drag_e2e`, `select_precision_e2e`,
`drag_move_e2e`, `zoom_quality_e2e`, `brush_nodes_e2e`, `extreme_zoom_ui_e2e`, `VectorPathFill_test`, `NumericFieldAdaptive_test`. Guía:
`docs/es/guides/TEXTO_EN_TRAZADO_Y_EDICION_PRECISA.md`.

## 0 sexies. Tanda 0.2.3-beta (2026-11-09): campañas profesionales y rendimiento

Cinco campañas publicitarias como pruebas e2e (kit común `test/e2e/lib/campaign_kit.gd`):

| # | Campaña | Modo | Qué ejercita |
|---:|---|---|---|
| 31 | Festival de música | Modern | 3 mesas, ondas Bézier, manchas, estrellas, máscara, 3 estilos de pincel, pincel de figuras de una estrella seleccionada, texto en un aro, 7 formatos + reimportar |
| 32 | AERO RUN (zapatilla) | Pro | silueta Bézier, 60 hexágonos, pincel de figuras de un hexágono, aerógrafo, máscara redondeada, texto debajo e invertido |
| 33 | Café de especialidad | Smart | sello con texto encima e invertido debajo, pincel de figuras de un GRUPO, lápiz, máscara en arco |
| 34 | Residencial Bahía | Modern | ~1 000 figuras (horizonte), máscara del cielo, texto sobre la bahía, rendimiento |
| 35 | Muro de marca | Pro | N elementos (10 000 / 50 000) mezclando todo: rendimiento masivo |

Fallos que han destapado (corregidos):

| ID | Fallo | Estado |
|---|---|---|
| VAL-27 | SVG / PDF / EPS sin NINGÚN trazo de pincel (ni texto en trazado) | Hecho (`306bf1a`): forma real; figuras y letras con su color |
| VAL-28 | Etiqueta de la mesa siempre «Artboard» | Hecho (`306bf1a`) |
| VAL-29 | Zoom con 10 000 elementos a 1,7 fps (trazos finos redibujados en cada paso) | Hecho (`306bf1a`): 14,5 fps |
| VAL-30 | Resaltado al pasar el ratón: 35–50 ms por movimiento con 10 000 | Hecho: rejilla espacial (0,06 ms; el clic sigue comprobándolo todo) |
| VAL-31 | Crear por script: coste creciente (10 000 → 85 s) | Hecho: nombres únicos en O(1) (0,6 ms por figura, constante) |
| VAL-32 | Arrastrar una selección de 10 000 con el ratón: 40 s POR PASO (candidatos del imán O(n²), recalculados en cada movimiento) | Hecho: 38 ms por paso (conjuntos O(1), cachés por gesto, caja del recuadro desplazada) |
| VAL-33 | `set_props` de un objeto NO seleccionado reconstruía el inspector (9 ms por figura) | Hecho: solo si afecta a la selección o al panel Capas |
| VAL-34 | Textos en trazado: cualquier movimiento releía y retriangulaba todas sus letras | Hecho: firma de contenido y de colocación relativa |
| VAL-35 | Curvas con tramos rectos diminutos: Godot metía hasta 64 puntos por recta (abrir un archivo: 25 s) | Hecho: tramos rectos sin subdividir (0,58 s); exportación sin puntos repetidos y contornos simplificados |
| VAL-36 | Caja de curvas y polígonos recalculada punto a punto en cada fotograma | Hecho: caché por curva y transformación nativa de vértices |
| VAL-37 | Exportar PNG/JPEG/WEBP de una mesa mayor de 16 384 px fallaba | Hecho: la escala se reduce lo justo, con aviso |
| VAL-38 | Letras avanzadas: arrastrar la curva / onda sincronizaba todos los paneles en cada paso | Hecho: 34 → 21 ms (curva) y 26 → 12 ms (onda, interletra) |
| VAL-41 | El pool de recuadros de selección se agotaba (100) con recuadros ya borrados junto a su lienzo: luego no aparecía la caja | Hecho: `ObjectPool.acquire` descarta las referencias muertas antes de contar |
| VAL-40 | `letter_fx_e2e`: Esc no sale de la edición y la caja del texto cambia al salir (3 fallos) | **Abierto**: ya fallaba antes de esta tanda (comprobado en `4d99afb`) |
| VAL-39 | 50 000 elementos en modo débil: **3 GB de memoria** y 5,6 fps con todo a la vista (7 500 trazos de pincel incluidos) | **Abierto**: la memoria por trazo (malla en caché) y por figura obliga a rehacer estructuras; arrastrar la selección: 184 ms por paso |

**Rendimiento con el muro de 10 000 elementos mezclados (encargo 35, modo potente):**

| Medida | Antes | Ahora |
|---|---|---|
| Crear por script | 85 s | 11,6 s (figuras 0,1–0,3 ms) |
| Resaltado al pasar el ratón | 50 ms | 0,06 ms |
| Arrastrar la selección completa | 40 000 ms por paso | 38 ms por paso |
| Todo a la vista | 44 fps | 45 fps |
| Zoom (escenas, 10 000) | 1,7 fps (regresión) | 14,5 fps |
| Guardar / abrir | 0,55 s / 4 s | igual |


## 0 septies. Plataformas y memoria (2026-11-09, tarde)

Petición: exportar para Apple, Windows, Linux y Android; Mac lo más antiguo
posible (¿10.10?); memoria al mínimo sin perder fluidez.

| ID | Tarea | Estado |
|---|---|---|
| PLAT-01 | Perfil de exportación **Android** (APK arm64 + x86_64, `io.github.malabo1990.vectopen`) | Hecho: arranca en el emulador; render OpenGL en móviles (`rendering_method.mobile`) porque Vulkan no se ve en el emulador y falla en muchas tabletas |
| PLAT-02 | Interfaz diminuta en pantallas densas (440 ppp → 85 %) | Hecho: `UIScale.scale_for` amplía según el DPI mientras quepan 1280 × 720 puntos (móvil 2340×1080 → 150 %); también respetaba mal la escala del sistema al 150 % |
| PLAT-03 | **macOS 10.10** | **No es posible**: la plantilla de Godot 4.7 está compilada para 10.13 (Intel) y 11 (Apple Silicon). Bajado el mínimo de 10.15 a **10.13** (Macs de 2009–2010 en adelante); Rust con `MACOSX_DEPLOYMENT_TARGET=10.13`. Sin Vulkan/Metal, Godot pasa solo a OpenGL. Sin probar en un Mac real |
| PLAT-04 | iOS | No se puede desde Linux: hace falta un Mac con Xcode y una cuenta de Apple Developer |
| PLAT-05 | Release de GitHub con Android | Hecho en `release.yml`. **Decisión del usuario**: subir la clave permanente como secretos (`ANDROID_KEYSTORE_BASE64/USER/PASSWORD`); está en `~/.local/share/vectopen-release/` (copia de seguridad: sin ella no se pueden publicar actualizaciones que se instalen encima) |
| PLAT-06 | Librerías nativas en Android | Pendiente: falta el NDK; mientras, texto e importadores van por GDScript |
| PLAT-07 | Publicar la 0.2.3-beta | Hecho (2026-11-09): release de GitHub con 8 archivos; el APK publicado es el firmado con la clave permanente (GitHub firmó con una temporal porque faltan los secretos). Web con tarjeta de Android, blog ES/EN con 20 imágenes y los 64 cambios enlazados, y workflow `release-sync.yml` que pone los enlaces de cada versión nueva |
| PLAT-08 | Interfaz para Android y tabletas | **Pendiente** (el usuario lo diseñará): la APK es una vista previa |
| MEM-01 | Panel Teclado y ratón montado al arrancar (~600 nodos, 9 MB) | Hecho: se monta al abrirlo |
| MEM-02 | Lateral de Pro creado en todos los modos (1 116 nodos, 15 MB) | Hecho: solo al entrar en Pro |
| MEM-03 | Inspector de Modern creado en todos los modos (1 251 nodos, 16,5 MB) | Hecho: solo en Modern (`only_modes`) |
| MEM-04 | Capas: una fila (~10 KB) por figura añadida, sin límite | Hecho: también por tandas de 200 al añadir una a una |
| MEM-05 | Renderizador OpenGL en escritorio | Descartado: −170 MB pero 49 → 20 fps con 10 000 elementos |
| MEM-06 | Texto: ~35 KB por texto (nodo + Label oculto + texto nativo) | Abierto: el Label oculto lo usan 85 sitios |

Android (emulador, documento vacío): 374 → 279 MB. Paquetes locales en
`dist/0.2.3-beta/` (Windows zip, macOS dmg/zip, deb, rpm, tar.gz, APK firmado
con la clave permanente); Windows/macOS sin el vectorizador IA (ONNX se
compila en GitHub). Librerías nativas para Windows/macOS desde Linux:
`rust/build_cross.sh` (zig + osxcross).

Arranque en Smart: 792 → 702 MB de memoria residente (Godot: 260 → 209 MB;
6 063 → 3 083 nodos). Unos 300 MB son del controlador NVIDIA/Vulkan.
Sonda: `test/e2e/memory_probe_e2e.gd` (MEM_QUICK, MEM_MICRO, MEM_TREE).

## 0 octies. Tanda del usuario (2026-11-13/21) — sin empezar

Ninguna de estas peticiones está diseñada ni implementada: son el encargo
tal cual lo pidió el usuario, para abrirlas una por iteración (§0).

| ID | Petición | Estado |
|---|---|---|
| USR-35 | Notificaciones de errores y bugs dentro de la app, con botón «Enviar a técnico» y reporte determinante (traza, `archivo:línea`, versión, SO, cola del log) | Pendiente |
| USR-36 | Diálogo de Contacto con área de texto multilínea para escribir al técnico: motivo (bug/error/sugerencia), email opcional, abrible desde Ayuda y desde la notificación de error | Pendiente |
| USR-37 | Action/servicio que RECIBA los reportes de bug (contrato de datos, almacenamiento y reintento, privacidad) | Pendiente |
| USR-38 | Bug: no se pueden editar ni arrastrar los elementos hijos de un padre (la selección salta al padre) | Pendiente |
| USR-39 | Grosor de trazo tipo Affinity: arrastrar el número para cambiarlo, presets, vista previa en vivo, unidades y un solo paso de deshacer | Pendiente |

Notas de arranque:

- USR-35/USR-36/USR-37 dependen de una decisión que el usuario aún no ha
  tomado: transporte del reporte (issue pre-rellenado en GitHub, `mailto:`
  o endpoint propio con backend). Sin eso solo se pueden hacer la captura y
  el formulario local. `reports/` de la raíz es la salida de gdUnit4, no un
  buzón: los reportes irían a `user://bug_reports/`.
- USR-35: incluir también el manejador de fallos del build de release, no
  solo los `push_error` de depuración.
- USR-38: reproducir antes de tocar nada (¿falla selección, bounding box,
  inspector o arrastre? ¿con grupo, artboard anidado, hijo de texto?).
  Sospechosos: `script_gdscript/tools/MoveTool.gd` (`_edit_frame_for()`,
  `target_artboard`), `SelectionManager` (hit-test que devuelve el padre),
  `InspectorCore`/`HistoryManager` (padre con transformación) y
  `Layertree.gd` / `layers_system.gd` (clic en la capa hija selecciona la
  hija). Prueba que falle primero: seleccionar hijo → mover → Ctrl+Z.
- USR-39: el arrastre del deslizador debe registrar **un** paso de
  `HistoryManager` al soltar, no uno por píxel. Respetar el grosor por lado
  que ya existe (`VectorRectangle.stroke_sides`).

### Informe técnico de propuestas de mejora (2026-11-21)

Informe aportado por el usuario. Se guarda como backlog de producto; el
texto original termina a media frase («La incorporación») y se cierra abajo
con una línea de resumen. El §6 de este informe es el mismo USR-38.

**Área:** Geometría vectorial, herramientas de composición, maquetación
profesional y experiencia de usuario (UI/UX).

**Objetivo:** Ampliar las capacidades de Vectopen para convertirlo en una
herramienta de diseño vectorial y composición visual más flexible,
eficiente y adecuada para proyectos profesionales.

#### 1. Geometría avanzada: esquinas y redondeado inverso

Ampliar las opciones de edición de esquinas para ofrecer mayor control
sobre la geometría de los objetos.

**Mejoras propuestas:**

- Incorporar el redondeado inverso de esquinas (Inverted Corner Radius).
- Añadir controles individuales para cada esquina.
- Integrar todas estas propiedades en el Inspector.
- Permitir modificar esquinas cóncavas y convexas.
- Ofrecer diferentes perfiles geométricos de esquina.

**Edición avanzada:**

Incorporar perfiles personalizados para generar esquinas con formas
especiales, como zigzag, dientes de sierra (Sawtooth) y otros patrones
geométricos.

La edición debería permitir ajustar los parámetros y visualizar los cambios
en tiempo real.

> Relacionado: USR-39 (grosor, mismo panel) y el core Bézier de
> `docs/roadmap/VGSE-informe-conceptual-y-propuesta-tecnica.md`.

#### 2. Iluminación y efectos visuales 2D

Incorporar un sistema de iluminación 2D para ampliar las posibilidades de
ilustración y composición gráfica.

**Funciones propuestas:**

- Fuentes de luz puntuales y direccionales.
- Sombras dinámicas.
- Iluminación radial.
- Efectos de brillo y resplandor (Glow).
- Control de intensidad, dirección, distancia y color.
- Degradados luminosos.
- Interacción entre iluminación y objetos.

Esta funcionalidad permitiría crear ilustraciones, interfaces y
composiciones visuales más elaboradas sin depender de aplicaciones
externas.

#### 3. Blend Tool: fusión e interpolación de objetos

Incorporar una herramienta Blend equivalente a la de Adobe Illustrator y
Affinity Designer.

Su función principal sería generar automáticamente una secuencia de objetos
intermedios entre dos o más elementos vectoriales.

**Modos principales:**

1. **Specified Steps:** definir el número exacto de objetos intermedios. Por
   ejemplo, generar 34 elementos entre el objeto A y el objeto B.
2. **Specified Distance:** establecer la distancia entre los objetos
   generados.
3. **Smooth Color:** realizar una transición progresiva de color entre los
   elementos iniciales y finales.
4. **Blend Along Path:** distribuir los objetos intermedios siguiendo una
   trayectoria personalizada.

**Propiedades de interpolación:**

- Posición.
- Escala.
- Rotación.
- Color.
- Opacidad.
- Propiedades de trazo compatibles.

**Funciones adicionales:**

- Actualización automática cuando se modifican los objetos originales.
- Control de orientación de los elementos siguiendo una trayectoria.
- Posibilidad de utilizar grupos y objetos complejos.
- Edición no destructiva.
- Conversión del resultado en objetos vectoriales independientes mediante
  Expand Blend.

**Ejemplos de aplicación:**

- Transformar visualmente un cuadrado en un círculo mediante elementos
  intermedios.
- Crear transiciones entre polígonos y estrellas.
- Generar secuencias geométricas repetitivas.
- Crear efectos de profundidad y perspectiva.
- Diseñar patrones decorativos.
- Distribuir elementos a lo largo de una curva.

El objetivo es disponer de una herramienta de fusión flexible, con controles
propios en el Inspector y una experiencia de edición similar a Illustrator y
Affinity Designer.

#### 4. Sistema de Layout: Grid, Flex y contenedores

Incorporar un sistema de organización automática de objetos inspirado en
Figma, Penpot y los sistemas de contenedores de interfaces.

Actualmente, sería interesante reducir la necesidad de posicionar
manualmente cada elemento.

**Sistemas propuestos:**

- **Grid Layout:** organización mediante filas y columnas.
- **Flex Layout:** distribución flexible y automática de elementos.
- **HBoxContainer:** distribución horizontal.
- **VBoxContainer:** distribución vertical.
- **Content Flow:** reorganización automática del contenido según el espacio
  disponible.

**Propiedades configurables:**

- Margin (margen exterior).
- Padding (espacio interior).
- Gap (separación entre elementos).
- Alineación horizontal y vertical.
- Distribución del espacio disponible.
- Ancho y alto automáticos.
- Tamaños mínimos y máximos.
- Ajuste y reorganización responsiva.
- Orden de los elementos.

También sería interesante permitir convertir rectángulos y grupos en
contenedores con reglas de distribución automática.

> Nota: Godot ya trae `HBoxContainer`/`VBoxContainer`/`GridContainer`; el
> trabajo real es exponerlos como objetos del documento sin romper el modelo
> de formas actual (grupos, capas, .vtp).

#### 5. Maquetación profesional y composición editorial

Ampliar las capacidades de composición y maquetación para facilitar la
creación de documentos grandes y productos gráficos profesionales.

**Posibles aplicaciones:**

- Catálogos comerciales.
- Documentación técnica.
- Manuales y publicaciones.
- Presentaciones profesionales.
- Interfaces de productos digitales.
- Documentos extensos con múltiples páginas.
- Composiciones editoriales complejas.

La experiencia de trabajo debería combinar la rapidez de Figma y Penpot con
las posibilidades de precisión y control editorial de Adobe InDesign.

Es importante que el sistema de Layout permita trabajar con estructuras
complejas, grupos, contenedores y elementos anidados sin tener que ajustar
manualmente cada objeto.

#### 6. Mejoras de UI/UX: selección y jerarquía de objetos

He observado un posible problema en la interacción con objetos anidados.

Cuando intento seleccionar o arrastrar un objeto que pertenece a un grupo o
contenedor, la selección parece saltar automáticamente al objeto padre. Esto
dificulta mover y editar elementos individuales.

**Comportamiento esperado:**

- Priorizar la selección del objeto situado directamente bajo el cursor.
- Permitir seleccionar objetos hijos sin activar automáticamente el grupo
  padre.
- Mantener la posibilidad de seleccionar el objeto padre mediante una acción
  específica.
- Permitir arrastrar elementos hijos independientemente.
- Incorporar una opción para atravesar grupos y contenedores durante la
  selección.
- Diferenciar visualmente el objeto seleccionado, su contenedor y su
  jerarquía.

**Propuesta adicional:**

Implementar un sistema de selección inteligente con diferentes niveles de
profundidad, similar al funcionamiento de Figma y otros editores
profesionales.

La prioridad debe ser respetar el objeto seleccionado y evitar que la
jerarquía de grupos interfiera inesperadamente con las acciones del usuario.

> Es el mismo USR-38: ese punto es el bug, este es el comportamiento
> esperado (tipo Figma) para el arreglo. No son dos tareas.

#### 7. Conclusión y visión técnica

Estas propuestas buscan ampliar Vectopen más allá de las funcionalidades de
un editor vectorial tradicional.

La incorporación de estas capacidades (esquinas avanzadas, iluminación 2D,
Blend, layout automático, maquetación multipágina y selección por
profundidad) acercaría a Vectopen a un estudio de diseño completo en una
sola app, sin perder el control preciso del objeto ni la salida a imprenta.

> **Prioridad sugerida** (no acordada): 1) USR-38 (hijos), 2) USR-39
> (grosor), 3) esquinas avanzadas, 4) layout, 5) Blend, 6) iluminación 2D,
> 7) maquetación editorial. Cada bloque grande merece su propio documento de
> diseño en `docs/roadmap/` antes de codear.

## 0 nonies. VTP Preview — visor de documentos (2026-11-21) — propuesta

> Informe conceptual aportado por el usuario. **No hay diseño ni código
> hecho**: es una propuesta para evaluar. El texto se guarda completo abajo;
> las notas de arranque son mías, para conectar la propuesta con lo que ya
> existe.

**Notas de arranque:**

- El punto 9 de los criterios («editor y visor con el mismo núcleo») hoy no se
  cumple tal cual: `canvas_serializer._element_from()`
  (`scripts/canvas/canvas_serializer.gd:1064-1256`) **crea nodos de Godot**
  (`VectorCircle`, `Line2D`, `Sprite2D`…), no un modelo neutral. Un visor
  reutilizable y un runtime web exigen separar «decodificar a modelo de
  documento» de «instanciar nodos». Es la decisión arquitectónica de fondo.
- La lectura perezosa por página ya existe (`rebuild_from_vtc`), igual que el
  manifest con offsets: el visor puede reutilizarla sin cargar el documento
  entero. Base: `docs/es/reference/VTP_FORMAT.md`.
- El §8 del informe (validar cabecera/versión, limitar descompresión,
  comprobar offsets) coincide con los huecos reales del formato descritos en
  `docs/es/reference/VTP_FORMAT.md` §8.1: hoy no hay checksum, no se rechazan
  versiones futuras y `decompress_dynamic(-1)` no tiene tope.
- Miniaturas: el informe propone sidecar `proyecto.vtp.preview.png`. Alternativa
  a considerar: miniatura **dentro** del manifest (como un bloque más), que
  evita archivos sueltos y cachés huérfanas al mover/renombrar el `.vtp`.
- Un `.vtp` es contenido no confiable: el visor no debe ejecutar `shader_code`
  ni cargar `shader_path`/`tex_path`/`model_path` arbitrarios (ver
  `VTP_FORMAT.md` §8.6).

### Informe de concepto técnico

#### VTP Preview — Visor integrado de documentos en Vectopen

- **Proyecto:** Vectopen
- **Componente propuesto:** VTP Preview
- **Tipo:** Visor de documentos vectoriales de solo lectura
- **Estado:** Propuesta conceptual para evaluación técnica

---

#### 1. Objetivo

Desarrollar un visor de documentos VTP integrado en Vectopen que permita
explorar, previsualizar y consultar archivos desde el entorno de escritorio,
sin necesidad de abrir el editor completo.

La idea es proporcionar una experiencia similar a los sistemas de vista previa
de documentos e imágenes de aplicaciones como GIMP y otros programas de
escritorio.

El visor deberá facilitar la administración de proyectos, la identificación
visual de documentos y la consulta rápida de su contenido.

El objetivo no es sustituir el editor, sino incorporar una herramienta
complementaria, ligera y especializada.

#### 2. Concepto general

VTP Preview será un módulo independiente del entorno de edición, pero integrado
en la aplicación Vectopen.

Se plantean tres niveles de funcionamiento:

1. **Miniaturas:** identificación visual rápida de los documentos.
2. **Visor de documentos:** visualización detallada sin herramientas de edición.
3. **Editor completo:** apertura del documento para modificar sus elementos.

El usuario podrá pasar del visor al editor cuando necesite realizar cambios.

#### 3. Explorador y administración de documentos

Crear una interfaz para explorar los documentos VTP guardados en el ordenador.

**Funciones principales**

- Mostrar documentos `.vtp` disponibles.
- Presentar miniaturas de cada documento.
- Mostrar nombre del proyecto.
- Mostrar fecha de modificación.
- Mostrar tamaño del archivo.
- Mostrar número de páginas y mesas de trabajo.
- Mostrar dimensiones del documento.
- Permitir ordenar por nombre, fecha y tamaño.
- Permitir cambiar entre vista de cuadrícula y lista.
- Mostrar una vista previa ampliada al seleccionar un archivo.

La interfaz deberá adaptarse a diferentes resoluciones y permitir una navegación
sencilla.

#### 4. Visor de documentos VTP

El visor permitirá abrir documentos en modo de solo lectura.

**Funciones de visualización**

- Renderizado de figuras vectoriales.
- Zoom y desplazamiento.
- Ajustar documento a pantalla.
- Ajustar mesa de trabajo a pantalla.
- Navegar entre páginas y mesas de trabajo.
- Visualizar transparencias.
- Cambiar el fondo de visualización.
- Mostrar u ocultar cuadrícula.
- Consultar dimensiones y propiedades generales.
- Visualizar imágenes y recursos compatibles.
- Mostrar información de los elementos seleccionados.

El visor no deberá modificar el documento original ni ejecutar automáticamente
scripts, código o contenido externo.

**Interacción**

Se propone una interfaz sencilla, con una zona central para visualizar el
documento y un panel lateral opcional para consultar sus propiedades.

#### 5. Sistema de miniaturas y caché

Para evitar tener que descomprimir y renderizar todos los documentos cada vez
que se abre el explorador, se propone implementar un sistema de miniaturas
automáticas.

**Generación de miniaturas**

Cuando se guarde un documento, Vectopen podrá generar una imagen de vista previa
en formato PNG.

Ejemplo conceptual:

- `proyecto.vtp`
- `proyecto.vtp.preview.png`

La imagen será una caché auxiliar y no un requisito para que el documento pueda
abrirse.

**Requisitos**

- Generación automática al guardar.
- Regeneración cuando cambie el contenido del documento.
- Identificación de cachés obsoletas.
- Tamaño optimizado para el explorador.
- Posibilidad de regenerar miniaturas manualmente.
- No modificar ni corromper el archivo VTP si falla la generación de la
  miniatura.

Se recomienda guardar las miniaturas en una ubicación de caché administrada por
Vectopen, evitando llenar las carpetas de proyectos con archivos auxiliares.

#### 6. Arquitectura técnica propuesta

La arquitectura deberá reutilizar el sistema actual de lectura y deserialización
de VTP.

No se recomienda implementar un segundo lector independiente, ya que podría
provocar diferencias de interpretación entre el editor, el visor de escritorio y
el futuro runtime web.

**Componentes**

**A. VTP Core / Decoder**

Responsable de:

- Leer el contenedor VTP.
- Validar su estructura y versión.
- Descomprimir los datos necesarios.
- Interpretar el manifest.
- Leer páginas y elementos.
- Resolver referencias a recursos.
- Entregar una representación común del documento.

**B. VTP Preview Renderer**

Responsable de representar visualmente el documento sin activar las
herramientas de edición.

**C. Desktop Document Browser**

Responsable de explorar documentos, mostrar miniaturas y administrar las vistas
previas.

**D. Thumbnail Generator**

Responsable de generar y mantener las imágenes de caché.

**Flujo conceptual**

Archivo VTP → VTP Core / Decoder → Modelo de documento → Renderer → Vista
previa.

El mismo núcleo podrá utilizarse posteriormente en otros entornos.

#### 7. Compatibilidad con el futuro runtime web

Una de las ventajas estratégicas de esta arquitectura es que VTP Preview puede
convertirse en la base de un sistema de visualización multiplataforma.

Se propone mantener una separación entre el formato del documento, su
interpretación y su representación gráfica.

En una evolución futura, el mismo núcleo de lectura podrá utilizarse para
desarrollar:

- Visor de documentos VTP para navegadores.
- Aplicación web de previsualización.
- Visor independiente para compartir proyectos.
- Integración con otras aplicaciones.
- Runtime JavaScript o WebAssembly, si resulta conveniente.

El navegador no necesitará interpretar directamente el archivo VTP. Será la
aplicación web la que cargue el archivo y utilice el runtime para visualizarlo.

#### 8. Seguridad y fiabilidad

El visor deberá tratar los documentos como contenido potencialmente externo y no
confiable.

Se establecen los siguientes requisitos:

- Validar la cabecera y la versión del formato.
- Limitar el tamaño de los datos descomprimidos.
- Comprobar los tamaños y offsets de los bloques.
- Evitar accesos a rutas externas no autorizadas.
- No ejecutar scripts automáticamente.
- No ejecutar shaders o código externo sin autorización y controles
  específicos.
- Manejar documentos dañados sin bloquear toda la aplicación.
- Mostrar mensajes comprensibles cuando un documento no sea compatible.

El visor debe funcionar en modo de solo lectura y no sobrescribir archivos
originales.

#### 9. Rendimiento

El rendimiento es un aspecto importante, especialmente cuando el usuario
administra muchos proyectos.

Se recomienda:

- Carga diferida de páginas.
- Renderizado únicamente de la vista necesaria.
- Miniaturas de resolución reducida.
- Caché de imágenes de previsualización.
- Evitar cargar todos los recursos del documento al mismo tiempo.
- Liberar memoria cuando se cierre una vista previa.
- Evitar descompresiones repetidas cuando los datos ya estén disponibles.

La apertura de una miniatura no debería requerir cargar el documento completo.

#### 10. Interfaz de usuario propuesta

La interfaz puede organizarse en tres áreas:

**Panel principal**

- Cuadrícula o lista de documentos.
- Miniaturas.
- Nombre y metadatos básicos.

**Panel de vista previa**

- Representación ampliada del documento seleccionado.
- Navegación entre páginas.
- Zoom y controles de visualización.

**Panel de información**

- Nombre del proyecto.
- Fecha de modificación.
- Tamaño.
- Dimensiones.
- Número de páginas.
- Información técnica del documento.

Se recomienda permitir ocultar los paneles para maximizar el espacio de
visualización.

#### 11. Fases de desarrollo

**Fase 1 — MVP: visor básico**

- Crear el módulo VTP Preview.
- Integrar el lector VTP existente.
- Abrir documentos en modo de solo lectura.
- Renderizar páginas y mesas de trabajo.
- Implementar zoom y navegación.

**Fase 2 — Explorador de documentos**

- Crear la interfaz de administración.
- Añadir vista de cuadrícula y lista.
- Mostrar metadatos.
- Añadir selección y vista previa ampliada.

**Fase 3 — Miniaturas y caché**

- Generar miniaturas PNG.
- Implementar actualización automática.
- Detectar cachés obsoletas.
- Optimizar la carga de documentos.

**Fase 4 — Mejoras avanzadas**

- Mostrar información de objetos y capas.
- Mejorar la gestión de recursos.
- Incorporar navegación avanzada.
- Preparar interfaces reutilizables para el runtime web.

#### 12. Criterios de aceptación

El desarrollo se considerará funcional cuando:

1. Se puedan abrir archivos VTP desde el visor sin entrar en el editor.
2. El visor represente correctamente los elementos compatibles.
3. Se pueda navegar entre páginas y mesas de trabajo.
4. Se pueda ampliar y reducir la visualización.
5. Se generen miniaturas sin alterar el documento original.
6. Las miniaturas se actualicen cuando cambie el contenido.
7. Los documentos dañados o incompatibles se gestionen de forma controlada.
8. El visor no ejecute scripts externos ni modifique documentos.
9. El editor y el visor interpreten los documentos mediante el mismo núcleo de
   lectura.

#### 13. Conclusión

VTP Preview permitirá que Vectopen evolucione desde un editor vectorial hacia un
entorno más completo de administración, consulta y visualización de documentos.

La principal decisión arquitectónica consiste en reutilizar el núcleo de lectura
VTP y separar el renderizado de la edición.

Esta separación reducirá duplicaciones de código, facilitará el mantenimiento y
permitirá desarrollar posteriormente un runtime web compatible con el ecosistema
Vectopen.

**Recomendación:** desarrollar primero un visor de escritorio de solo lectura y
un sistema de miniaturas. Una vez consolidado el núcleo de visualización,
utilizarlo como base para el futuro visor web.

## 1. Funciones nuevas (encargo 10)

Hechas (2026-11-21): **VAL-23** componentes vinculados (`script_gdscript/shapes/symbols.gd`:
copias iguales al estilo Affinity, «Sincronizar» apagado = retoques locales,
desvincular, menú contextual, Recursos ▸ «Colocar vinculado», API `make_symbol`…;
`Symbols_test` 5/0) y **VAL-24** estilos de texto con nombre
(`script_gdscript/text/text_styles.gd`, fila «Estilo» del panel de texto en
los tres modos, API `add_text_style`…; `TextStyles_test` 5/0,
`text_styles_ui_e2e` 35/0). Encargo 10 **aprobado** (`proyecto_10_e2e` 14/0).


---

## 2. Defectos leves acumulados

Ninguno abierto. Cerrados el 2026-11-21 (`defectos_leves_e2e` 8/0): VAL-05
(rótulo de la página, ya arreglado con VAL-28), VAL-10 (alto del marco de
columnas tras deshacer: ya no cambia), VAL-13 (cambiar el tamaño de la página
reencuadra la vista: `canvas.frame_artboard`), VAL-17 (Smart: clic derecho ▸
«Forma de la figura…» abre el panel Figuras) y VAL-18 (título «FIGURAS · ELIPSE»…).


---

## 3. Publicación y actualizaciones

- [ ] Mac Intel: el vectorizador IA no existe (ONNX Runtime no tiene binarios
	  para `x86_64-apple-darwin`); valorar compilarlo desde fuente o avisarlo
	  en la app.
- [ ] Windows: el paquete es un `.zip`; el botón de actualizar solo lo abre.
	  Un instalador (`.exe`/`.msi`) permitiría actualizar de verdad.
- [ ] Firmar los binarios de Windows y macOS (avisos de «desarrollador desconocido»).

---

## 4. Otros pendientes

- `AdaptiveUI_test` (ancho mínimo de Pro 272/280) falla a veces solo en la
  batería completa; aislado pasa siempre: depende del orden de las pruebas.
- e2e que siguen en rojo (revisado 2026-11-21): `pages_e2e` y
  `theme_switch_strokes_e2e` ya pasan; `assets_ui_e2e` arreglado (la rejilla
  no aceptaba el botón derecho y la prueba no desplazaba la lista: 37/0).
  Siguen: `text_format_e2e` (3), `letter_fx_e2e` (3, = VAL-40),
  `text_render_e2e` (3: «la letra asoma por fuera del efecto»),
  `text_advanced_e2e` (sin resultado) y `google_fonts_e2e` (red).
  **Pista de VAL-40 / «Escape sale de edición»**: en esas pruebas Escape
  llega a `_input` pero no al editor nativo ni a `_unhandled_key_input`;
  algo lo consume en `_input`. Ya corregidos (VAL-67): los popovers
  (letras, color, trazo), el menú de Modern y el
  explorador de archivos (que además se quedaba con ESPACIO) solo atienden
  Esc cuando se ven de verdad; el canvas deja pasar Esc a la herramienta
  mientras se edita y el editor nativo ya no lo consume. Falta localizar el
  último consumidor (sospecha: un tooltip abierto de Godot).
- Avisos «leaked at exit» al cerrar las pruebas con `quit()` (salen en todas;
  no se han visto al cerrar la app normal). Revisar si la app instalada
  cierra limpia (punto 20 de la lista del §5.2).

---

## 5. Fase B — Validación con proyectos reales (encargos 11–30)

Encargos 01–30 **aprobados** (11: `proyecto_11_e2e` 22/0; 12: `proyecto_12_e2e` 12/0; 13: `proyecto_13_e2e` 16/0 — 302 trazos a 60 fps, también con zoom 400 %; 14: `proyecto_14_e2e` 24/0; 15: `proyecto_15_e2e` 23/0; 16: `proyecto_16_e2e` 20/0; 17: `proyecto_17_e2e` 26/0; 18: `proyecto_18_e2e` 21/0; 19: `proyecto_19_e2e` 17/0; 20: `proyecto_20_e2e` 21/0; 21: `proyecto_21_e2e` 24/0; 22: `proyecto_22_e2e` 23/0; 23: `proyecto_23_e2e` 23/0; 24: `proyecto_24_e2e` 19/0; 25: `proyecto_25_e2e` 17/0; 26: `proyecto_26_e2e` 14/0; 27: `proyecto_27_e2e` 16/0; 28: `proyecto_28_e2e` 22/0 — un script genera un calendario de 12 tablas en 0,3 s; 29: `proyecto_29_e2e` 14/0; 30: `proyecto_30_e2e` 15/0). **Los 30 encargos de la Fase B están aprobados.** Del §5.3 quedan dos casillas.

Defectos destapados en la Fase B (2026-11-21):

| ID | Encargo | Fallo | Estado |
|---|---|---|---|
| VAL-66 | 30 | Una foto vectorizada (1 650 trazados, ~75 000 nodos) tardaba **25 s en dibujarse** la primera vez al abrirla (y recalculaba el relleno en cada repintado) | **Mejorado → 13 s**: relleno en caché por trazado; contornos enormes sin los puntos sobrantes (Douglas-Peucker 0,02 px) antes de triangular (un contorno de 21 000 puntos: 4,3 s → 0,25 s). **Abierto**: ~15 formas con huecos «pellizcados» siguen costando ~0,5 s cada una (la triangulación de Godot falla y se rehace con todos los puntos): otro triangulador (p. ej. nativo en Rust) o teselar los rellenos con tolerancia por longitud |
| VAL-65 | 29 | Al vectorizar un logo escaneado, el fondo blanco salía como un trazado más (estorba al colocarlo sobre color) | Hecho: Vectorizar ▸ «Ignorar el fondo blanco» (activado; quita solo el blanco que cubre la imagen, no los huecos interiores) |
| VAL-64 | 29 | No había «Simplificar trazado» (reducir nodos) | Hecho: clic derecho ▸ «Simplificar trazado» y API `simplify_path` / `count_nodes` (también dentro de grupos, un paso de deshacer). El ajuste de curvas ya no deforma la costura de un contorno cerrado ni duplica esquinas (logo: 125 → 40 nodos, 1,2 % de píxeles distintos) (`SimplifyPath_test`) |
| VAL-63 | 27 | Al deshacer (o quitar) un parámetro del shader, el material conservaba el último valor (el color no volvía) | Hecho: los uniforms sin valor vuelven al de su código |
| VAL-62 | 27 | Los parámetros (uniforms) de un shader propio no se podían editar en el Inspector | Hecho: `shader_params_box.gd` en la sección Shader (Modern y Pro): deslizador + número con su rango, color, interruptor, vec2; vista previa en vivo y un paso de deshacer |
| VAL-61 | 26 | Al reabrir, los números de página («{pág} / {total}») de las páginas que se despertaban después se quedaban sin resolver | Hecho: se resuelven al despertar cada página |
| VAL-60 | 26 | La página seleccionada tomaba la posición del cursor del sistema, no la del evento: un clic sobre una figura (tableta, eventos seguidos) se interpretaba como clic en un hueco y arrastraba la página | Hecho: usa la posición del propio evento |
| VAL-59 | 26 | Duplicar «Diapositiva 2» daba «Diapositiva 2 2» (y luego «2 2 2»…) | Hecho: sigue la serie («Diapositiva 3»), en todo nombre numerado |
| VAL-58 | 26 | La retícula de la página (márgenes y columnas) se dibujaba pero NO atraía al arrastrar | Hecho: márgenes y columnas son candidatos del imán |
| VAL-57 | 25 | La paleta era de la APLICACIÓN: no había colores del documento ni colores globales (cambiar el color de marca obligaba a repintar objeto a objeto) | Hecho: colores globales del documento (`script_gdscript/shapes/global_colors.gd`): relleno/trazo vinculados, cambiar la muestra cambia todo (también dentro de componentes), un color a mano desvincula, deshacer, .vtp; Recursos ▸ «Colores del documento» (clic = relleno, Mayús = trazo, clic derecho = editar/renombrar); API `add_global_color`… (`GlobalColors_test`) |
| VAL-56 | 23 | No había **tablas** | Hecho (v1): `script_gdscript/shapes/table.gd` — grupo «Tabla» generado desde datos (cabecera, cebreado, rejilla, anchos y alineación por columna); clic derecho ▸ Insertar tabla / añadir-borrar fila o columna (según la celda elegida); API `add_table`, `table_set_cell`, `table_insert_row`…; el texto de una celda se edita normalmente y se conserva; se guarda en el .vtp (`Table_test`). Pendiente v2: herramienta de tabla con tiradores para redimensionar columnas en el lienzo y panel propio |
| VAL-55 | 22 | La API no podía bloquear capas | Hecho: `set_prop(objeto, "locked", true)` con deshacer |
| VAL-54 | 22 | Una FIGURA sin relleno usada como máscara (marco de viñeta) solo dejaba ver el contenido bajo su borde: el interior salía vacío (en pantalla y al exportar) | Hecho: recorta por su área, como los trazados |
| VAL-53 | 21 | Un marco de VARIAS columnas ponía todo el texto en la primera (el alto se ajustaba a una sola columna y desbordaba la página) | Hecho: columnas equilibradas (el alto mínimo en que el texto cabe repartido) |
| VAL-52 | 21 | El **tracking** (espaciado entre letras) de un texto no se veía: solo cambiaba la meta y la etiqueta oculta, no el texto nativo ni su caja | Hecho: llega al motor nativo (por tramos), la caja se reajusta, también al abrir documentos antiguos (`TrackingColumns_test`) |
| VAL-51 | 20 | El ángulo de la plumilla del pincel caligráfico era fijo (45°) y no se guardaba | Hecho: propiedad «Ángulo de plumilla» en el inspector (Modern y Pro), con deshacer, guardada en el .vtp |
| VAL-50 | 19 | No se podía exportar un PDF de VARIAS páginas (solo uno por página) | Hecho: Exportar ▸ «PDF de todas las páginas» (cada página con su tamaño y sangrado), API `export_pdf_pages` |
| VAL-49 | 19 | Textos creados por la herramienta Texto, la API o al importar SVG salían **DOBLES** (bitmap de la etiqueta + texto nativo): se ocultaba la etiqueta con `visible = false` y el CullManager la volvía a encender | Hecho: la etiqueta queda transparente (`TextLabelHidden_test`) |
| VAL-48 | 18 | Un texto con efectos guardaba sus capas internas (TextFxBack/Front) como hijos: al reabrir aparecía un nodo fantasma dentro del texto | Hecho (`TextFxNotSaved_test`) |
| VAL-47 | 17 | Un TEXTO no admitía relleno con degradado (`fill_paint` se quedaba en sólido) | Hecho: degradado en el relleno del texto (se pinta con la superposición de degradado recortada a las letras; se guarda y se reabre). Ojo: el ángulo de `fill_paint` va en radianes |
| VAL-46 | 15 | Con la página activa (queda SELECCIONADA al crearla o activarla), el primer clic con Mover sobre una figura de dentro arrastraba la página y no seleccionaba nada | Hecho: la página solo se arrastra desde un hueco vacío o con la herramienta Página (como Figma) |
| VAL-45 | 15 | El bloqueo de las capas se perdía al guardar y reabrir | Hecho (`LockedPersist_test`) |
| VAL-44 | 14 | No había orden «Crear máscara de recorte» con la selección (solo arrastrar en Capas + botón) | Hecho: clic derecho ▸ «Crear máscara de recorte» / «Soltar máscara» (la figura de arriba recorta) y API `make_mask` / `release_mask`, con deshacer |
| VAL-43 | 14 | **Máscaras anidadas** (una máscara dentro de otra): Godot ignora el recorte interior (`clip_children` no se puede anidar, limitación documentada del motor) | **Abierto (media), decidir con el usuario**: hoy `make_mask` lo rechaza con aviso; el panel Capas aún permite crearlas. Solución real = recorte geométrico propio (intersección de polígonos al dibujar figuras/trazos; las imágenes necesitarían un sombreador con la máscara como textura) |
| VAL-42 | 13 | Con una página SELECCIONADA, el pincel / la pluma / el texto no podían empezar dentro de ella: el clic arrastraba la página (`artboard._is_selection_tool` buscaba un nodo «Canvas» inexistente y respondía siempre «sí») | Hecho (`ArtboardToolClick_test`) |

### 5.1. Encargos pendientes

Ninguno. Cada encargo: `test/e2e/proyecto_NN_e2e.gd` (kit
`test/e2e/lib/campaign_kit.gd`), capturas en `user://proyectos/NN/`. Los
defectos nuevos siguen la numeración desde **VAL-68**.

### 5.2. Lista de comprobación por encargo (los puntos que apliquen)

1. Formato exacto (mm/px, sangrado, orientación).
2. Páginas/artboards: crear, reordenar, pliegos y rejilla.
3. Capas: renombrar, agrupar, anidar, ocultar, bloquear.
4. Máscara de recorte y su persistencia al reabrir.
5. Trazo: grosor, perfil, extremos, uniones, guiones, puntas.
6. Relleno: sólido, degradado (lineal/radial/cónico) y patrón.
7. Texto: título, párrafo, texto en curva y estilos.
8. Transformar, rotar, escalar y voltear sin deformar el texto.
9. Alinear, distribuir y snapping con guías.
10. Efectos: aplicar, desactivar, reordenar y eliminar.
11. Shader o script cuando el encargo lo requiera.
12. Vectorizar cuando el encargo lo requiera.
13. Deshacer/rehacer al menos 20 pasos seguidos.
14. Guardar, cerrar, reabrir sin pérdidas.
15. Exportar PNG, SVG y PDF y comparar con la pantalla.
16. Rendimiento: 60 FPS de referencia, sin bloqueos.
17. Atajos: `X`, `Delete`, `Supr`, herramientas y `Escape`.
18. Tema claro y oscuro: legibilidad y contraste.
19. Coherencia entre Smart, Modern y Pro.
20. Cierre limpio: sin errores en consola ni autosave corrupto.

Severidad: **Alta** si impide terminar el encargo o corrompe el archivo;
**Media** si obliga a dar un rodeo; **Baja** si es cosmético.

### 5.3. Al terminar los 30

- [x] Repetición cruzada: encargos 11–30 en los otros dos modos (kit con
	  `FORCE_MODE`, script `~/.cache/vectopen_tests/cruzada.sh`): 40/40 en verde
	  tras dar a la ventana Shader de Smart los parámetros del shader. Los
	  encargos 01–10 no usan el kit: quedan sin repetir en otros modos.
- [ ] Cero `VAL-nn` abiertos de severidad alta o media.
- [ ] Suite completa (unitaria + e2e) en verde y sin errores en consola.
- [x] Exportaciones deterministas: SVG, PDF, EPS y VOP idénticos byte a byte
	  entre dos exportaciones (`DeterministicExport_test`).
- [x] Actualizar `ROADMAP.md` (sección 0c, 2026-11-21).
