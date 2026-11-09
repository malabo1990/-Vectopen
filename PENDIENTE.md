# PENDIENTE — Lo que queda por hacer

**Proyecto:** Vectopen (Godot 4.7, GDScript)
**Fecha:** 2026-11-03 · versión publicada: **0.2.2-beta**
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
| USR-06 | VGSE (`docs/roadmap/VGSE-…md`): plan por fases, empezar por la fase 1 | Plan escrito (§0 ter); fase 1 en curso |

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
| Texturas desde una imagen del usuario; variación de color aleatoria a lo largo | Pendiente |
| **FALLO: los modos de fusión del panel Capas (Multiplicar, Pantalla, Superponer…) no hacen nada** — `layers_system` llama a `ic.apply("blend_mode", …)` pero InspectorCore no tiene esa propiedad. Para todos los objetos. Multiplicar/Sumar se pueden hacer con CanvasItemMaterial; Pantalla/Superponer/Aclarar/Oscurecer/Diferencia necesitan leer lo de detrás (screen texture / BackBufferCopy por objeto: coste). **Decidir con el usuario** | Pendiente (prioridad alta) |
**Fase 5 — Máscaras y efectos** (en curso)

| Punto | Estado |
|---|---|
| Máscara de recorte con trazos de pincel dentro | Existía (comprobado: `brush_mask_fx_e2e`) |
| Sombras / efectos en trazos de pincel (TextFx) | Existían (comprobado) |
| Efectos geométricos del trazo: ondulado, zigzag, rugoso (forma real: contorno, sombra, exportar) | Hecho (inspector «Forma del trazo», amplitud, tamaño de onda) |
| Caché de geometría (solo se rehace lo que cambia) | Hecho en fase 1 + malla nativa |
| Composición (modos de fusión) | Ver fallo de modos de fusión (fase 4) |
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
| Lápiz: colores por vértice y pliegues en Rust (16 → ~6 ms con 10 000) | Pendiente |
| Trazos de 100 000 muestras al dibujar: rehacer solo la cola (incremental) | Pendiente |
| Serialización / compatibilidad (trazos antiguos sin metas nuevas) | Pendiente de prueba |
| Pinceles personalizados guardados («Mis pinceles») | Pendiente |

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
| Memoria ~31 KB por elemento (50 000 → 2 GB: no cabe en un PC de 2 GB) | En curso: texto 83 → 39 KB (editor en línea por demanda); figuras ~22 KB y trazos ~24 KB por elemento siguen |
| Dibujar con todo a la vista (50 000 → 3 fps) y zoom: nivel de detalle / caché al alejar | En curso: 10 000 visibles 21 → 52 fps (lápiz sin grupo salvo pliegues; CullManager conectado a la cámara, textos sin _process con la vista quieta). Quedan ~1,8 llamadas de dibujo por elemento |
| CullManager: «dormir» páginas lejanas (stream_artboards) | Apagado: nunca funcionó (no tenía cámara); activarlo cambia mucho el comportamiento — probar con documentos de muchas páginas antes |
| Seleccionar todo (50 000 → 5 s) y mover la selección (630 ms por paso) | En curso: el inspector usa una muestra con miles de objetos (current_props 617 → 34 ms con 10 000; fotograma tras seleccionar 967 → 382 ms). Mover la selección sigue pendiente |

**Escala de la interfaz**: hecho — `ui_scale.gd` (automática por escala del
sistema / DPI / tamaño; Ajustes ▸ Interfaz 80–200 %; Ctrl+Alt+= / - / 0; aviso;
`VECTOPEN_UI_SCALE` para pruebas; `ui_scale_e2e` 10/0). Un solo control para
toda la UI (los 382 tamaños de letra fijados a mano impiden un «solo texto» fiable).

## 1. Funciones nuevas para la 0.2.3

Salieron del encargo 10 (UI kit), que queda **bloqueado** hasta tenerlas.

| ID | Función | Esperado | Hoy |
|---|---|---|---|
| VAL-23 | Componentes vinculados (símbolos) | Un maestro y sus copias: cambiar el maestro actualiza todas; una copia puede tener cambios propios; se guardan y se exportan | Recursos coloca copias independientes |
| VAL-24 | Estilos de texto con nombre | Título / cuerpo / pie con nombre: aplicar a varios textos y, al editar el estilo, que se actualicen todos; guardados con el documento | No existen |

Al terminarlas: repetir `test/e2e/proyecto_10_e2e.gd` (ya comprueba si las
copias se actualizan, mensaje `INFO VAL-23` / `INFO VAL-24`) y aprobar el
encargo 10.

---

## 2. Defectos leves acumulados

| ID | Encargo | Modo | Pasos | Esperado | Obtenido |
|---|---|---|---|---|---|
| VAL-05 | 01, 05, 09 | Pro | Renombrar páginas | El rótulo sobre la página dice su nombre | Dice «Artboard» |
| VAL-10 | 02 Revista | Pro | Marco de varias columnas: editar y deshacer | Mismo alto | El alto medido cambia unos px (88 → 72) |
| VAL-13 | 03, 04 | Smart/Modern | Cambiar el tamaño de la página (p. ej. a A1) | La vista se reencuadra a la página | Sigue el zoom anterior y la página queda cortada |
| VAL-17 | 06 Isotipo | Smart | Seleccionar un círculo y buscar «Forma» en el inspector | Forma/anillo/ángulos también en el inspector, como en Pro | Solo desde el botón «Figuras» |
| VAL-18 | 06 Isotipo | Smart | Botón «Figuras» con una elipse seleccionada | Título acorde (p. ej. «FIGURAS») | Dice «POLÍGONOS Y ESTRELLAS» |

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
- e2e que siguen en rojo: `text_format_e2e` (3 fallos) y `text_advanced_e2e` (sin resultado) — ya fallaban antes del 2026-11-09; `pages_e2e` (clic en la miniatura 3 no va a la página 3) y `assets_ui_e2e` (clic derecho no abre el menú del recurso), ya fallaban el 2026-11-09 antes de tocar Capas; `theme_switch_strokes_e2e` (no encuentra los botones «Claro/Oscuro» del menú desde `823d1e7`), `text_render_e2e` (desde el 2026-11-02) y
  `google_fonts_e2e` (necesita red).
- Avisos «leaked at exit» al cerrar las pruebas con `quit()` (salen en todas;
  no se han visto al cerrar la app normal). Revisar si la app instalada
  cierra limpia (punto 20 de la lista del §5.2).

---

## 5. Fase B — Validación con proyectos reales (encargos 11–30)

Encargos 01–09 **aprobados**; 10 **bloqueado** (§1). Quedan 20.

### 5.1. Encargos pendientes

| # | Encargo | Modo principal | Foco de la prueba |
|---:|---|---|---|
| 10 | UI kit de aplicación | Modern | Bloqueado por VAL-23 / VAL-24 |
| 11 | Wireframe de landing | Modern | Bloques, alineación, snapping |
| 12 | Set de 24 iconos | Smart | Trazo coherente, export SVG individual |
| 13 | Ilustración con pinceles | Smart | 300+ trazos, fluidez y memoria |
| 14 | Retrato con máscaras | Pro | Clip entre dos Bézier |
| 15 | Mapa estilizado | Pro | Trazos cerrados, capas anidadas |
| 16 | Diagrama técnico | Modern | Trazos con puntas, guiones, etiquetas |
| 17 | Portada de álbum | Modern | Degradados, texto en curva |
| 18 | Packaging con texto en curva | Pro | Texto sobre trayectoria, 3D de texto |
| 19 | Menú de restaurante | Smart | Párrafos, estilos, export PDF |
| 20 | Invitación con caligrafía | Smart | Pincel caligráfico, presión |
| 21 | Póster tipográfico | Pro | Solo texto, interlineado, tracking |
| 22 | Historieta de 4 viñetas | Modern | Máscaras, capas, export por página |
| 23 | Tabla comparativa | Pro | Tablas, alineación, bordes |
| 24 | Certificado / diploma | Modern | Texto centrado, adornos, PDF |
| 25 | Manual de marca (12 páginas) | Pro | Pliegos, muestras de color, paleta |
| 26 | Presentación de 10 diapositivas | Pro | Rejilla, export por página |
| 27 | Shader: degradado animado con ruido | Pro | Shader simple, parámetros en Inspector |
| 28 | Script avanzado (automatización) | Pro | API de script, errores controlados |
| 29 | Vectorizar un logo bitmap | Modern | VTracer, limpieza de nodos |
| 30 | Vectorizar una foto y depurar | Pro | Umbrales, simplificación, rendimiento |

Cada encargo: `test/e2e/proyecto_NN_e2e.gd`, fixture en
`test/fixtures/proyectos/NN-nombre.vtc`, capturas en `user://proyectos/NN/`
(revisarlas). Los defectos nuevos siguen la numeración desde **VAL-27**.

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

- [ ] Repetición cruzada: cada encargo también en los otros dos modos, sin
      divergencias de severidad alta o media.
- [ ] Cero `VAL-nn` abiertos de severidad alta o media.
- [ ] Suite completa (unitaria + e2e) en verde y sin errores en consola.
- [ ] Exportaciones deterministas (mismo archivo → mismo resultado).
- [ ] Actualizar `ROADMAP.md`.
