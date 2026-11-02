# PENDIENTE — Informe técnico de incidencias y plan de corrección

**Proyecto:** Vectopen (Godot 4.7, GDScript)
**Documento:** registro vigente de incidencias abiertas
**Fecha:** 2026-11-02
**Sustituye a:** `docs/archive/PENDIENTE-2026-09.md` (sesiones de septiembre, ya commiteadas)
**Alcance:** experiencia de usuario de texto y párrafo, panel de páginas, geometría de anillo, paneles de Modern/Pro, cobertura del Inspector y rendimiento de pincel
**Método de cierre:** corrección guiada por prueba de interfaz, en bucle iterativo (§9)

---

## 1. Resumen ejecutivo

Se registran **siete incidencias**, una de ellas crítica por bloqueo de la aplicación.
Todas exigen verificación mediante pruebas de interfaz antes de considerarse resueltas.

| ID | Área | Incidencia | Severidad |
|---|---|---|---|
| UX-01 | Texto / Párrafo | El panel de tipografía bloquea la edición de párrafo | Alta |
| UX-02 | Texto (T) | El tamaño al soltar el arrastre no coincide con el previsualizado | Alta |
| UX-03 | Panel Pages | Interfaz poco profesional y sin modos de vista editoriales | Media |
| UX-04 | Polígonos | El modo anillo dibuja una línea espuria en 0°/360° | Media |
| UX-05 | Modern / Pro | Faltan los paneles de Script y Plugins | Media |
| UX-06 | Inspector | Cobertura incompleta de propiedades (trazo y detalles) | Media |
| UX-07 | Pincel | Bloqueo con 300–1000 trazos y al seleccionar ~389 elementos | **Crítica** |

---

## 2. UX-01 — El panel de tipografía bloquea la edición de párrafo

**Síntoma.** Al editar un párrafo, la interacción con el panel de tipografía y
texto no responde con fluidez: la edición queda interceptada y el flujo se
interrumpe.

**Hipótesis técnica.** Concurren dos fuentes de foco: el editor en línea del
párrafo (`TextEdit` embebido) y los controles del panel, que reclaman el foco o
reconstruyen el contenedor mientras se escribe. La reconstrucción provoca
pérdida de selección y, en el peor caso, reentrada en el manejador de cambios.

**Evidencia.** `script_gdscript/ui/panel_paragraph.gd`,
`script_gdscript/text/text_core.gd` (`ensure_inline_editor`, `editing_range`),
`script_gdscript/tools/ParagraphTool.gd`.

**Corrección propuesta.**
1. Separar el ciclo de *commit* del panel del ciclo de escritura: aplicar
   cambios en diferido (una sola escritura por fotograma).
2. No reconstruir el contenedor de texto mientras `TextCore.editing_range()`
   devuelva un rango activo; en su lugar, actualizar solo el atributo afectado.
3. Bloquear la reemisión de señales durante la aplicación de un cambio
   (guarda de reentrada).

**Criterio de aceptación.**
- [x] Escribir 200 caracteres con el panel abierto no pierde el cursor.
- [x] Cambiar tamaño y color con el párrafo en edición no cancela la edición.
- [x] Sin parpadeos ni saltos de línea al aplicar cambios.

**Resolución (2026-11-02).** En Smart y Modern el panel ya funcionaba (el
deslizador cambia el tamaño sin cancelar la edición). El bloqueo estaba en los
campos numéricos (`NumericField`, panel Pro y resto de la app): desde Godot 4.4
tener el foco no implica estar editando, y sin `LineEdit.edit()` el campo
ignoraba lo tecleado y el Intro; el foco se quedaba en el campo y el párrafo
dejaba de recibir teclas. Corregido en `ui/components/numeric_field.gd`: entra
en edición real y, tras Intro, devuelve el foco al texto en edición. Prueba:
`test/e2e/paragraph_panel_e2e.gd` (tres modos).

**Prueba de interfaz.** `test/e2e/paragraph_panel_e2e.gd`: abrir párrafo, editar
texto, cambiar tamaño y color desde el panel, verificar contenido y foco.

---

## 3. UX-02 — El tamaño del texto no coincide tras el arrastre

**Síntoma.** Con la herramienta de texto (T), el arrastre previsualiza un tamaño;
al soltar, el texto aparece **más pequeño** que lo previsualizado. Si después se
arrastra para moverlo, el texto se muestra de pronto **más grande**. El tamaño
final no es estable ni predecible.

**Hipótesis técnica.** El tamaño se calcula durante el arrastre
(`drag_font_size`, `TextTool.gd:463-473`) y se vuelve a calcular al soltar
(`_finish_drag_creation`, `TextTool.gd:477-488`). Los criterios difieren —margen
de seguridad, alto del contenedor y ajuste del `WorldTextLabel`—, de modo que el
valor previsualizado y el aplicado no coinciden. El desplazamiento posterior
dispara un nuevo reajuste, revelando la discrepancia acumulada.

**Evidencia.** `script_gdscript/tools/TextTool.gd:463-509`,
`script_gdscript/ui/panel_paragraph.gd`, `_update_shape_meta_size` en
`TextTool.gd:598`.

**Corrección propuesta.**
1. Unificar el cálculo en una única función pura:
   `calcular_tamano_para(distancia) -> int`, usada por previsualización y
   confirmación.
2. Al soltar, fijar el tamaño calculado **sin** volver a medir el contenido.
3. Corregir el anclaje: el punto de origen del arrastre debe determinar la
   posición final, no el centro recalculado.
4. Impedir que mover el objeto reajuste el tamaño (solo lo hace el usuario).

**Criterio de aceptación.**
- [x] El tamaño visible al arrastrar es idéntico al aplicado al soltar (±0 px).
- [x] Mover el texto después no altera su tamaño.
- [x] Repetible en los tres modos de interfaz (Smart, Modern, Pro).

**Resolución (2026-11-02).** La causa real no era el cálculo del tamaño (la
previsualización y el valor guardado ya coincidían) sino el ORDEN al crear el
editor nativo: se fijaba el tamaño y después `set_text()`, que reinicia el
formato. El texto se guardaba a N pt pero se DIBUJABA a 24; al moverlo, una
resincronización lo ponía a N («crecía»). Corregido en `TextTool.gd` y en dos
puntos de `ParagraphTool.gd` (un párrafo de 40 pt sin tramos volvía a 24 al
editarlo). Prueba: `test/e2e/text_drag_size_e2e.gd`.

**Prueba de interfaz.** `test/e2e/text_drag_size_e2e.gd`: simular arrastre,
comparar `font_size` y caja antes/después, mover y revalidar.

---

## 4. UX-03 — Panel de páginas: diseño y modos de vista

**Síntoma.** El panel de páginas no alcanza el nivel de acabado del panel de
capas y carece de los modos de vista propios de un editor editorial.

**Requisitos.**
1. **Diseño profesional**, coherente con el panel de capas (jerarquía, densidad,
   miniaturas, acciones contextuales).
2. **Modo libro / pliegos enfrentados**: secuencia vertical 1‑2 · 2‑3 · 4‑5 …
   con página par e impar afrontadas, al estilo InDesign.
3. **Modo página simple**: el comportamiento actual.
4. **Modo rejilla**: retícula de páginas, idónea para redes sociales y carteles.

**Evidencia.** `script_gdscript/ui/panels/pages/pages_panel.gd`,
`script_gdscript/ui/panels/layer_icons.gd`, `layer_thumbs.gd` (referencia de
acabado), `layer_settings.gd`.

**Corrección propuesta.** Introducir un enumerado de modo de vista
(`SIMPLE`, `SPREAD`, `GRID`), persistido en las preferencias del panel, y un
componente de previsualización por miniatura reutilizando el sistema de capas.
El modo pliego debe tratar la primera página como portada exenta y emparejar el
resto (impar/par), contemplando documentos con número impar de páginas.

**Criterio de aceptación.**
- [ ] Los tres modos conmutan sin perder la selección ni el desplazamiento.
- [ ] En pliego, la portada va sola y el emparejamiento es correcto hasta el final.
- [ ] En rejilla, el zoom y el número de columnas se ajustan al ancho del panel.
- [ ] El modo elegido persiste entre sesiones.

**Prueba de interfaz.** `test/e2e/pages_panel_modes_e2e.gd` con documentos de 1,
2, 5 y 8 páginas.

---

## 5. UX-04 — Línea espuria en el modo anillo con 0° y 360°

**Síntoma.** En el modo anillo, cuando los dos puntos coinciden (0° y 360°), se
dibuja una línea radial que atraviesa la figura. Se desea un anillo limpio.

**Hipótesis técnica.** El recorrido se cierra con un segmento entre el punto
inicial y el final cuando el arco abarca la vuelta completa, en lugar de tratar
el caso como circunferencia cerrada.

**Evidencia.** `script_gdscript/tools/CircleTool.gd:169-190` (`span`, comparación
con `TAU`, rama `donut`), `shape_mode` en `CircleTool.gd:7-10`.

**Corrección propuesta.**
1. Detectar `is_equal_approx(span, TAU)` antes de generar el contorno y emitir
   dos circunferencias cerradas (exterior e interior), sin segmento de cierre.
2. Unificar el criterio de cierre con el usado en `whole`, evitando duplicar la
   lógica.
3. Añadir un margen de tolerancia angular para valores límite (359,999°).

**Criterio de aceptación.**
- [x] Anillo a 360° sin línea radial, con grosor uniforme.
- [x] Arcos parciales siguen cerrando correctamente por el centro.
- [x] Sin artefactos al cambiar `inner_radius_ratio`.

**Resolución (2026-11-02).** El anillo completo se generaba como UN contorno
que iba de la circunferencia exterior a la interior por un puente en 0°, y el
trazo dibujaba ese puente. Ahora `VectorCircle` lo trata como dos
circunferencias cerradas: relleno con una tira de triángulos entre ambas
(admite degradado), trazo de cada una por separado y SVG con dos subtrazados
`fill-rule="evenodd"`. Tolerancia de 0,01° (359,999° = vuelta completa) en
`VectorCircle.arc_span`, compartida con la vista previa de `CircleTool`, que
también dibuja las dos circunferencias. Prueba: `test/e2e/ring_full_circle_e2e.gd`
(dibuja con la herramienta real y comprueba píxeles con hueco 25/50/80 %).

**Prueba de interfaz.** `test/e2e/ring_full_circle_e2e.gd`: crear anillo 0–360,
inspeccionar la malla generada y comparar el número de vértices con el esperado.

---

## 6. UX-05 — Paneles de Script y Plugins ausentes en Modern y Pro

**Síntoma.** En los modos Modern y Pro no existe acceso a Script ni a Plugins,
presentes en otros modos o en la arquitectura del producto.

**Requisitos.**
- Pestaña **Script** operativa en Modern y Pro, reutilizando el editor existente.
- Pestaña **Plugins** con listado, activación y ajustes, sin duplicar lógica.
- Estado y contenido preservados al cambiar de modo.

**Evidencia.** `script_gdscript/ui/adaptive_ui_manager.gd`,
`autoloads/PluginManager.gd`, `docs/en/guides/SCRIPTS_AND_ADDONS.md`.

**Criterio de aceptación.**
- [ ] Ambas pestañas visibles y funcionales en Modern y Pro.
- [ ] El script abierto y los plugins activos sobreviven al cambio de modo.
- [ ] Sin regresiones en Smart.

**Prueba de interfaz.** `test/e2e/panels_script_plugins_e2e.gd`.

---

## 7. UX-06 — Cobertura incompleta del Inspector

**Síntoma.** El panel no expone numerosas propiedades: trazo en todas sus
variantes y detalles de figura que sí existen en el modelo.

**Requisitos.** Completar la superficie del Inspector con, al menos:
- Trazo: color, grosor, perfil, extremos, uniones, guiones, alineación,
  puntas y escala de puntas.
- Figura: radio de esquina por lado, opacidad, modos de mezcla, visibilidad,
  bloqueo, máscara de recorte.
- Texto: familia, peso, cursiva, interlineado, espaciado, alineación e
  indentación.
- Efectos: pila ordenable con activación individual.

**Evidencia.** `autoloads/InspectorCore.gd` (constante `PROPS`, lectura y
escritura), `script_gdscript/ui/docked_inspector.gd`,
`script_gdscript/ui/components/inspector_fx_sections.gd`.

**Corrección propuesta.** Derivar la interfaz de `PROPS` para impedir
divergencias entre modelo y panel; añadir una prueba que verifique que toda
propiedad declarada tiene lector, escritor y control visible.

**Criterio de aceptación.**
- [ ] Cada propiedad de `PROPS` es editable desde la interfaz.
- [ ] Ninguna propiedad del panel carece de efecto real.
- [ ] Deshacer/rehacer cubre todas las nuevas propiedades.

**Prueba de interfaz.** `test/e2e/inspector_props_coverage_e2e.gd`.

---

## 8. UX-07 — Bloqueo con muchos trazos de pincel (crítico)

**Síntoma.** Tras un número elevado de trazos de pincel (rango observado entre
300 y 1000), seleccionar todos los elementos —del orden de 389— bloquea la
aplicación. Debe reproducirse con el archivo `face.vtp`.

**Hipótesis técnica.** La selección dispara un recálculo o redibujado por
elemento, con complejidad al menos lineal por objeto y potencialmente cuadrática
al recalcular la caja envolvente o el orden de dibujo. La ausencia de
presupuesto por fotograma convierte esa operación en un bloqueo del hilo
principal.

**Evidencia a confirmar.** `script_gdscript/tools/brushtool.gd`
(creación de trazos), `script_gdscript/ui/panel_brush.gd`,
`autoloads/SelectionManager.gd`, `autoloads/ObjectPool.gd`.

**Plan de diagnóstico.**
1. Perfilar la operación con 100, 300, 500 y 1000 trazos; registrar tiempo por
   fotograma y pico de memoria.
2. Instrumentar el camino de selección para identificar la función dominante.
3. Incorporar presupuesto: procesar la selección por lotes con
   `await get_tree().process_frame` cada N elementos.
4. Cachear la caja envolvente y evitar recomputarla si la geometría no cambió.

**Criterio de aceptación.**
- [x] Seleccionar 389 elementos con 1000 trazos mantiene la interfaz fluida
      (< 100 ms de bloqueo por fotograma). *Medido: 39 ms con 1065 trazos;
      seleccionar los 1065 a la vez, 98 ms; `face.vtp` (267 trazos), 32 ms
      (antes 206 ms).*
- [x] El dibujo de la selección aparece de forma progresiva, no de golpe.
      *No hizo falta: la selección completa se dibuja en un solo fotograma
      por debajo de 100 ms.*
- [x] Memoria estable tras 10 ciclos de selección y deselección (+3 MB con
      1065 trazos, +0,3 MB con `face.vtp`).

**Resolución (2026-11-02).** Causa: cada trazo de pincel es un `Line2D` de
hasta ~26 000 puntos y su caja se recalculaba recorriendo todos los puntos
en cada consulta (inspector, herramienta Mover, recuadro), además de leer
~60 propiedades por trazo dos veces seguidas. Corrección: caja cacheada por
trazo (`script_gdscript/utils/line_bounds.gd`, precalculada al entrar en el
documento), propiedades del inspector agrupadas por tipo de objeto, con corte
en cuanto un valor es «mixto» y un solo cálculo por fotograma en selecciones
grandes, perfil de trazo normalizado cacheado y selección sin búsquedas
cuadráticas (`SelectionCore`). Prueba: `test/perf/brush_selection_perf.gd`
(`VTP_PATH=…/face.vtp`, `STRESS=4` para ~1000 trazos).

**Prueba de interfaz.** `test/perf/brush_selection_perf.gd` con `face.vtp`.
**Material de prueba:** `face.vtp` localizado en
`/mnt/win_sdb1/2025/Vectopen/VTC/face.vtp` (fuera del repositorio, por lo que la
prueba debe recibir la ruta como parámetro de entorno).

---

## 9. Protocolo de ejecución: corrección automática en bucle

Cada incidencia se cierra con el mismo ciclo, sin excepciones:

```
reproducir → medir → corregir → prueba de interfaz → medir de nuevo
      ↑                                                    │
      └────────────── si falla, repetir ───────────────────┘
```

**Reglas del bucle.**
1. **Reproducir primero.** Ninguna corrección sin una prueba que falle antes del
   cambio.
2. **Una incidencia por iteración.** No se mezclan correcciones en el mismo
   ciclo.
3. **Puerta de calidad.** El ciclo solo termina con la prueba en verde y la suite
   de regresión intacta.
4. **Límite de intentos.** Tras tres iteraciones fallidas se detiene, se
   documenta la causa y se replantea el enfoque en lugar de insistir.
5. **Cierre global.** Al completar las siete, se ejecuta la suite completa de
   gdUnit4 y una pasada manual de humo en los tres modos de interfaz.

**Orden recomendado.** UX-07 (crítico) → UX-02 → UX-01 → UX-04 → UX-05 →
UX-06 → UX-03.

**Comandos de verificación.**

```sh
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests res://test
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests res://test/e2e
```

---

## 10. Trazabilidad

| ID | Archivos principales | Prueba asociada | Estado |
|---|---|---|---|
| UX-01 | `panel_paragraph.gd`, `text_core.gd` | `paragraph_panel_e2e.gd` | **Cerrada** (2026-11-02) |
| UX-02 | `tools/TextTool.gd`, `ParagraphTool.gd` | `text_drag_size_e2e.gd` | **Cerrada** (2026-11-02) |
| UX-03 | `ui/panels/pages/pages_panel.gd` | `pages_panel_modes_e2e.gd` | Abierta |
| UX-04 | `tools/CircleTool.gd` | `ring_full_circle_e2e.gd` | **Cerrada** (2026-11-02) |
| UX-05 | `ui/adaptive_ui_manager.gd`, `PluginManager.gd` | `panels_script_plugins_e2e.gd` | Abierta |
| UX-06 | `InspectorCore.gd`, `docked_inspector.gd` | `inspector_props_coverage_e2e.gd` | Abierta |
| UX-07 | `InspectorCore.gd`, `SelectionCore.gd`, `line_bounds.gd` | `brush_selection_perf.gd` | **Cerrada** (2026-11-02) |

---

*Documento de trabajo. La versión anterior (septiembre de 2026) permanece
archivada en `docs/archive/PENDIENTE-2026-09.md`.*
