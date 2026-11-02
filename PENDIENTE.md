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
- [x] Los tres modos conmutan sin perder la selección ni el desplazamiento.
- [x] En pliego, la portada va sola y el emparejamiento es correcto hasta el final.
- [x] En rejilla, el zoom y el número de columnas se ajustan al ancho del panel.
- [x] El modo elegido persiste entre sesiones.

**Resolución (2026-11-02).** `pages_panel.gd` tiene `ViewMode {SIMPLE,
SPREAD, GRID}` con tres botones (▯ ▯▯ ▦) junto a añadir / duplicar / borrar.
La rejilla virtualizada sigue siendo un solo Control; ahora calcula una celda
por página según el modo (`_build_rects`), y clic, arrastrar para
reordenar, «Ir a» y miniaturas en segundo plano funcionan igual en los tres.
- Simple: el comportamiento de antes (miniaturas de tamaño fijo).
- Pliegos: portada sola a la derecha, luego 2‑3, 4‑5…; con nº par de
  páginas la última queda sola a la izquierda (`PagesPanel.spreads(n)`).
- Rejilla: el deslizador pasa a ser «columnas» (1–8) y las miniaturas llenan
  el ancho del panel.
- Al cambiar de modo se conserva la selección y queda a la vista la página
  activa (o la que estaba arriba). Modo, tamaño y columnas se guardan en
  `user://vectopen_pages.cfg`.
- Corregido de paso: con la barra de desplazamiento apareciendo y
  desapareciendo, la rejilla se recalculaba sin fin (cola de mensajes llena
  y cierre de Godot): la barra queda siempre visible.
Prueba: `test/e2e/pages_panel_modes_e2e.gd` (1, 2, 5, 8 y 40 páginas, clics
reales); `pages_e2e.gd` (500 páginas) sigue en verde.
**Pendiente (requisito 1, acabado visual):** el panel usa la misma paleta y
botones que Capas, pero no sus miniaturas por capa ni menú contextual propio.

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
- [x] Ambas pestañas visibles y funcionales en Modern y Pro.
- [x] El script abierto y los plugins activos sobreviven al cambio de modo.
- [x] Sin regresiones en Smart.

**Resolución (2026-11-02).** La sección SCRIPT (módulos Scripts y
Complementos, el mismo `script_panel.gd` de Smart) ya estaba en el inspector
de Modern y en la pestaña Efectos de Pro, pero fallaba: (1) la lista de
complementos medía 0 px dentro del inspector y no se veía ninguno; (2) el
plegado es compartido y, al cambiar de modo, la cabecera decía «abierta»
con el cuerpo oculto; (3) cada modo tenía su propio script. Ahora la lista
crece con su contenido en modo compacto, la sección se resincroniza al
verse y el script abierto (nombre, código y módulo) se comparte entre
instancias. Los complementos activos ya eran globales (`PluginManager`).
Prueba: `test/e2e/panels_script_plugins_e2e.gd` (clics reales, Modern → Pro
→ Modern y Smart).

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
- [x] Cada propiedad de `PROPS` es editable desde la interfaz.
- [x] Ninguna propiedad del panel carece de efecto real.
- [x] Deshacer/rehacer cubre todas las nuevas propiedades.

**Resolución (2026-11-02).** Prueba nueva `test/e2e/inspector_props_coverage_e2e.gd`:
en Modern y Pro, con rectángulo, elipse, polígono, estrella, trazado y texto,
usa todos los controles visibles del inspector (y de los desplegables que
abren), apunta qué propiedades se escriben (`InspectorCore.prop_written`) y
deshace todo comprobando que el objeto vuelve a como estaba. Lo que faltaba:
- Componente nuevo `ui/components/inspector_extra_props.gd` (tabla de
  propiedades → controles; cada modo elige las que le faltan): nombre,
  opacidad, visibilidad, radios de esquina, lados/regular/giro/proporción,
  puntas/radio interior/redondeo de valles/giro, forma y ángulos de la
  elipse, curvatura de la gota, alineación horizontal y vertical, sangrías,
  columnas, y botones Inicio / Fin / Estilo / Perfil que abren el desplegable
  de trazo de Smart (puntas, remates, tamaño de puntas, guiones, perfil).
- Modern: la alineación del trazo no estaba conectada; el ojo de Trazo no
  hacía nada y el de Relleno ocultaba el OBJETO (ahora ocultan/muestran
  trazo y relleno).
- Deshacer W/H de trazados, polígonos libres, líneas e imágenes girados no
  devolvía la forma (se reescalaba): ahora guarda y repone la geometría.
- `VectopenAPI.add_text` no fijaba width/height (el inspector mostraba 350 × 65).
- `filter_fx.gd`: un filtro (cristal…) sobre un texto daba miles de errores
  por fotograma (leía mal los polígonos de las letras).

**Seguimiento (no bloquea).** El alto de un texto autoajustado se recalcula
de la maquetación del editor nativo y no se guarda en el paso de deshacer:
tras deshacer muchos cambios puede quedar 4 px distinto (40 → 36) hasta el
siguiente ajuste. La prueba admite ±6 px en el ancho/alto del texto.
El modelo 3D también entra en la prueba: Pro no tenía ningún control 3D
(ahora todos) y a Modern le faltaba el giro de la luz. Relleno y trazo ya no
se ofrecen en modelos 3D (no los dibujan: eran controles sin efecto).
`model_path` se elige con diálogo de archivo, `text` en el lienzo y
`custom_shader` desde la sección Shader: excluidos de la prueba a propósito.

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
| UX-03 | `ui/panels/pages/pages_panel.gd` | `pages_panel_modes_e2e.gd` | **Cerrada** (2026-11-02) |
| UX-04 | `tools/CircleTool.gd` | `ring_full_circle_e2e.gd` | **Cerrada** (2026-11-02) |
| UX-05 | `ui/adaptive_ui_manager.gd`, `PluginManager.gd` | `panels_script_plugins_e2e.gd` | **Cerrada** (2026-11-02) |
| UX-06 | `InspectorCore.gd`, `docked_inspector.gd` | `inspector_props_coverage_e2e.gd` | **Cerrada** (2026-11-02) |
| UX-07 | `InspectorCore.gd`, `SelectionCore.gd`, `line_bounds.gd` | `brush_selection_perf.gd` | **Cerrada** (2026-11-02) |

---

*Documento de trabajo. La versión anterior (septiembre de 2026) permanece
archivada en `docs/archive/PENDIENTE-2026-09.md`.*
