# PENDIENTE — Informe técnico de incidencias y plan de corrección

**Proyecto:** Vectopen (Godot 4.7, GDScript)
**Documento:** registro vigente de incidencias abiertas
**Fecha:** 2026-11-02
**Sustituye a:** versión anterior del 2026-11-02 (máscaras, texto y rendimiento)
**Alcance:** máscaras de recorte, entrada de teclado, selector de color, paneles de
Modern/Pro, pincel, Bézier, trazos, Inspector, Script/Shader/Plugins y disposición
de paneles
**Método de cierre:** corrección guiada por prueba de interfaz, en bucle iterativo (§16)

---

## 0. Instrucción operativa — modo automático en bucle (`/LOOP`)

> **Ejecutar este documento en modo automático y en bucle.**
> No detenerse a pedir permiso entre incidencias: encadenar una tras otra hasta
> cerrar las catorce. Solo se interrumpe el bucle por las causas del §16.5.
>
> Ciclo por incidencia:
> `reproducir → prueba que falla → corregir → prueba en verde → regresión → siguiente`.
>
> Cada iteración debe: (1) dejar constancia en la tabla de progreso del §18,
> (2) no mezclar dos incidencias en el mismo cambio y (3) terminar en verde o
> marcar la incidencia como bloqueada con la causa concreta.
>
> Prohibido declarar «terminado» sin la prueba de interfaz ejecutada y su salida
> adjunta. Si una prueba no existe, se escribe antes de tocar el código.
>
> **Fase A:** las catorce incidencias. **Fase B:** validación de campo con 30
> proyectos reales (§19), que solo comienza cuando la Fase A esté íntegramente en
> verde. El bucle no termina hasta que ambas fases lo estén.

---

## 1. Resumen ejecutivo

Se registran **catorce incidencias**. Cuatro son de severidad alta por impedir una
función completa o afectar al resultado visual; ninguna es un bloqueo total de la
aplicación. La revisión transversal del Inspector (§14) debe ejecutarse en último
lugar, porque recoge los hallazgos de las anteriores.

| ID | Área | Incidencia | Severidad |
|---|---|---|---|
| UX-01 | Máscaras | El recorte se ve mal en la zona de las dos Bézier | Alta |
| UX-02 | Inspector | El teclado actúa como atajo de herramienta al escribir | Alta |
| UX-03 | Color | No se pueden borrar colores guardados; no guarda con degradado | Media |
| UX-04 | Modern/Pro | El panel de paleta no se muestra | Alta |
| UX-05 | Pro | Falta un panel por identificar | Baja (por aclarar) |
| UX-06 | Pincel | Panel de pincel y estilos sin acabado ni tema | Media |
| UX-07 | Bézier | Panel Bézier y estilos: gris fijo y diseño deficiente | Media |
| UX-08 | Trazos | Faltan propiedades en Modern y Pro | Alta |
| UX-09 | Pro | Pestañas no reubicables ni flotantes | Media |
| UX-10 | Teclado | Borrado: cubrir también `Delete` y `Supr` | Baja |
| UX-11 | Modern | Los trazos no se muestran | Alta |
| UX-12 | Inspector | Revisión profunda: texto, trazos, párrafos, relleno | Alta |
| UX-13 | Paneles | Shader, Script, Vectorizar y Plugins como iconos junto a Exportar | Media |
| UX-14 | Inspector | Sin redimensionado por arrastre; Script/Shader necesitan más ancho | Media |

---

## 2. UX-01 — Máscara de recorte mal renderizada entre dos Bézier

**Síntoma.** Al aplicar una máscara de recorte, el trazado se ve incorrecto en la
zona comprendida entre dos curvas Bézier: el borde recortado no sigue la
geometría real.

**Hipótesis técnica.** El recorte se resuelve con `clip_children`, que opera sobre
la máscara de píxeles del `CanvasItem`. En tramos con dos Bézier, la malla del
trazo no cubre exactamente el área teórica (el contorno se aproxima por
polilínea), por lo que el clip corta sobre una silueta distinta de la dibujada.

**Evidencia.** `script_gdscript/ui/layers_system.gd` (gestión de
`clip_children`), `scripts/canvas/canvas_serializer.gd` (persistencia del clip),
`script_gdscript/VectorPath*.gd` (generación de contorno).

**Corrección propuesta.**
1. Usar como máscara la **misma** malla generada para el relleno, no una
   aproximación independiente.
2. Elevar la calidad de teselado solo en el tramo afectado (subdivisión adaptativa
   entre nodos con curvatura alta).
3. Si la máscara es vectorial, resolver el recorte por geometría (intersección de
   contornos) y no por píxeles cuando el usuario lo solicite.

**Criterio de aceptación.**
- [x] Recorte correcto en curvas con dos Bézier y en S.
- [x] El borde recortado coincide con el trazo a cualquier zoom (hasta 800 %).
- [x] Sin cambios en el rendimiento con máscaras simples.

**Prueba de interfaz.** `test/e2e/clip_mask_bezier_e2e.gd`: crear trazo con dos
Bézier, aplicar máscara, capturar y comparar contra referencia.

**Resolución (2026-11-02).** Causa real: `clip_children` recorta con lo que
**dibuja** la máscara, y cuando la máscara no dibujaba nada Godot enseñaba el
contenido **entero, sin recortar**. Pasaba en dos casos: (1) dos Bézier que se
cruzan (una «S» cerrada): la triangulación fallaba y el relleno no se dibujaba;
(2) trazado abierto o sin relleno: solo se dibujaba la línea. Ahora
`VectorPath.fill_polygons()` parte el contorno que se corta a sí mismo en piezas
simples (`Geometry2D.merge_polygons` + par-impar) y una máscara sin relleno, o
abierta, recorta por su área implícita (como Illustrator). El botón de Capas
usa «solo recortar» si la figura no tiene relleno (no pinta un área blanca).
Las máscaras simples siguen el mismo camino de antes (sin coste). La prueba
compara píxel a píxel con la geometría exacta (400 muestras por tramo) en
cuatro casos (lente de dos nodos, S cruzada, cierre repetido, abierta) a 100 %
y 800 %: 0,00 % de error; antes 43–58 % en la S y la abierta.

**Pendiente de la propuesta (revisión 2026-11-02):** punto 3, recorte por geometría (intersección de contornos) a petición del usuario, no hecho.

---

## 3. UX-02 — El teclado del Inspector se comporta como atajo de herramienta

**Síntoma.** Al escribir en un campo del Inspector, las teclas se interpretan como
atajos de herramienta (equivalente a hacer clic en la herramienta), en lugar de
llegar al campo de texto.

**Hipótesis técnica.** El mapa de entrada de herramientas se evalúa antes de
comprobar si un control de interfaz tiene el foco. Falta la guarda de foco en el
manejador global.

**Evidencia.** `autoloads/VectopenInput.gd`, manejadores `_input` de
`script_gdscript/tools/*.gd`, `script_gdscript/ui/docked_inspector.gd`,
`script_gdscript/ui/components/inspector_extra_props.gd` (ya consulta
`has_focus` en algunos campos).

**Corrección propuesta.**
1. Guarda única y centralizada: si existe un control con foco de texto
   (`LineEdit`, `TextEdit`, `SpinBox`), los atajos de herramienta no se evalúan.
2. Aplicarla en `VectopenInput` antes de despachar a las herramientas.
3. Excepción explícita para `Escape` (sale del campo) y para atajos con `Ctrl`.

**Criterio de aceptación.**
- [x] Escribir `t`, `v` o `p` en un campo no cambia de herramienta.
- [x] `Escape` devuelve el foco al lienzo.
- [x] Los atajos siguen funcionando con el lienzo enfocado.

**Prueba de interfaz.** `test/e2e/inspector_keyboard_focus_e2e.gd`.

**Resolución (2026-11-02).** Guarda única `VectopenInput.is_typing()` (LineEdit,
TextEdit o SpinBox editables, o editor propio con `is_editing()`):
`tool_for_event()` no devuelve herramienta mientras se escribe. `Escape` en un
campo: el campo lo procesa y después se suelta el foco (salvo en editores de
código, que lo usan para el autocompletado). Antes, en Pro el campo hexadecimal
del color se quedaba con el teclado tras `Escape` y las letras dejaban de ser
atajos. La prueba pulsa con el ratón los 14 campos de Modern y los 22 de Pro y
escribe `t`, `v`, `p`.

---

## 4. UX-03 — Selector de color: sin borrado y sin guardado de degradados

**Síntoma.** No existe botón para eliminar colores guardados y tampoco se pueden
guardar degradados en la paleta.

**Requisitos.**
1. **Borrado por clic derecho** sobre la muestra, con confirmación opcional.
2. Soportar **degradados** como elemento guardable, conservando sus puntos de
   control.
3. Persistencia coherente entre sesiones.

**Evidencia.** `script_gdscript/ui/PaletteSaveGrid.gd`,
`script_gdscript/ui/ListaColor.gd`,
`script_gdscript/ui/managercolor_pickrColor.gd`,
`script_gdscript/ui/getcolor_pickrcolor.gd`.

**Corrección propuesta.**
1. Menú contextual en la muestra (`gui_input` con `MOUSE_BUTTON_RIGHT`) con
   «Eliminar» y «Duplicar».
2. Modelo de muestra polimórfico: color plano **o** degradado; serializar ambos.
3. Confirmar la eliminación solo si la muestra está en uso por algún objeto.

**Criterio de aceptación.**
- [x] Clic derecho sobre una muestra permite eliminarla.
- [x] Se guarda un degradado y se reaplica idéntico tras reiniciar.
- [x] Deshacer recupera una muestra eliminada.

**Prueba de interfaz.** `test/e2e/palette_delete_gradient_e2e.gd`.

**Resolución (2026-11-02).** `PaletteSaveGrid` guarda cada muestra como color
plano **o** degradado (el «paint» de ColorCore: tipo, puntos, ángulo y centro);
«+» guarda lo que esté activo. Clic derecho → menú Eliminar / Duplicar, con
deshacer; si algún objeto usa la muestra (y no la tapa un degradado) pide
confirmación. La muestra de degradado se dibuja como degradado y al pulsarla se
aplica tal cual. Persistencia en `user://vectopen_palette.cfg` (compatible con
las listas de colores antiguas) y los selectores de los tres modos se
actualizan juntos. 25 comprobaciones con clics reales.

---

## 5. UX-04 — Modern y Pro no muestran el panel de paleta

**Síntoma.** En los modos Modern y Pro el panel de paleta no aparece, pese a
existir en la arquitectura.

**Hipótesis técnica.** La paleta está registrada solo en el conjunto de paneles
del modo Smart o su visibilidad no se restablece al cambiar de modo.

**Evidencia.** `script_gdscript/ui/adaptive_ui_manager.gd`,
`script_gdscript/ui/docked_inspector.gd`, `script_gdscript/ui/ListaColor.gd`.

**Criterio de aceptación.**
- [x] La paleta se muestra en los tres modos.
- [x] Conserva posición y estado al alternar.
- [x] No duplica instancias.

**Prueba de interfaz.** `test/e2e/palette_modes_e2e.gd`.

**Resolución (2026-11-02).** En Modern y Smart la paleta se abría bien; en Pro
se abría **dentro** del lateral (497 px a la izquierda del selector) y el
contenedor la recortaba entera: 0 % visible. Ahora el selector (`GestorColor`)
comprueba al abrirla si se ve completa; si no, la hace flotar (`top_level`)
junto al selector y dentro de la ventana. La prueba abre el selector como el
usuario en los tres modos, pulsa el botón de paleta y mide el área realmente
visible (ventana + contenedores que recortan), que reciba el ratón, que haya una
sola, que siga abierta al cambiar de modo y que no se dupliquen selectores.

---

## 6. UX-05 — Pro: panel sin identificar

**Descripción.** La solicitud menciona «en Pro: falta panel de…» sin especificar
cuál. **Requiere aclaración del solicitante** antes de planificarlo.

**Acción inmediata.** Confirmar el panel ausente (candidatos: Paleta, Trazos,
Script, Plugins, Vectorizar) y, una vez identificado, asignarle un ID propio.

---

## 7. UX-06 — Panel de pincel y estilos: acabado y tema

**Síntoma.** El panel de pincel no alcanza el nivel visual del resto ni adapta sus
colores al tema.

**Evidencia.** `script_gdscript/ui/panel_brush.gd`, referencia de acabado en
`script_gdscript/ui/panels/layers_settings.gd`.

**Corrección propuesta.** Migrar a los componentes compartidos (secciones
plegables, campos numéricos, iconografía), eliminar colores literales y tomar los
del tema activo (`ThemeDB`/`theme_changed`).

**Criterio de aceptación.**
- [x] Sin colores literales en el panel.
- [x] Legible en tema claro y oscuro.
- [ ] Estructura y densidad equivalentes al panel de capas — **siguen los emojis** (✏️ ✒️ 🖍️ 🖌️ 💨 🧹) y campos propios (SpinBox + HSlider) en vez de los componentes compartidos (iconos SVG, `NumericField`).

**Prueba de interfaz.** `test/e2e/brush_panel_theme_e2e.gd` (captura en ambos temas).

**Reabierta (revisión 2026-11-02):** solo se migraron los colores; falta la iconografía y los campos comunes que pide la corrección propuesta.

**Resolución parcial (2026-11-02).** Componente común `ui/components/tool_panel_style.gd`
(colores del tema vía `ProUIStyle.col`): marco flotante, título, cabeceras de
sección en versalitas como Capas, textos secundarios con el color atenuado del
tema (no `modulate`), separadores y botones-interruptor. Sin `Color(` en el
script ni en la escena. Además: al soltar un panel del lateral (`ToolPanelDock`)
volvía con el marco del tema de cuando se acopló (en oscuro: título claro sobre
fondo claro, contraste 1,1:1); ahora se repinta. La prueba (base común
`tool_panel_theme_common.gd`) recorre tema claro y oscuro × Smart, Modern y
Pro: todos los colores salen del tema, contraste ≥ 4,5:1 (3:1 secundarios) y
letra ≤ 13 px.

---

## 8. UX-07 — Panel Bézier y estilos: rediseño y eliminación del gris fijo

**Síntoma.** El panel Bézier mantiene módulos con fondo gris ajeno al tema y un
acabado inferior al de capas.

**Evidencia.** `script_gdscript/ui/panel_bezier.gd`.

**Corrección propuesta.** Reutilizar el sistema visual de capas (iconos, filas,
separadores, estados hover/activo), sustituir el gris por el color de superficie
del tema y unificar la tipografía de etiquetas.

**Criterio de aceptación.**
- [x] Ningún módulo con gris fijo.
- [x] Iconos y filas consistentes con el panel de capas.
- [x] Correcto en los tres modos.

**Prueba de interfaz.** `test/e2e/bezier_panel_theme_e2e.gd`.

**Resolución (2026-11-02).** Mismo componente que UX-06: las tarjetas
(antes negro al 8 % fijo) usan la superficie y el borde del tema, cabeceras en
versalitas, iconos SVG del tema (papelera, unir, romper) en lugar de emojis,
tamaños de tirador como interruptores y el grosor con el campo numérico común.
Prueba en claro y oscuro × tres modos.

---

## 9. UX-08 — Panel de trazos incompleto en Modern y Pro

**Síntoma.** En Smart el panel de trazos está completo (incluido el botón
«avanzado»); en Modern y Pro faltan numerosas propiedades.

**Requisitos.** Paridad funcional con Smart: color, grosor, perfil, extremos,
uniones, guiones, alineación, puntas y escala.

**Evidencia.** `script_gdscript/ui/panel_trazos.gd`,
`script_gdscript/ui/adaptive_ui_manager.gd`.

**Corrección propuesta.** Extraer el panel a un único componente con variantes de
presentación por modo, en lugar de mantener tres implementaciones.

**Criterio de aceptación.**
- [x] Las mismas propiedades editables en los tres modos (incluidas las uniones).
- [x] Los cambios se reflejan al instante y son deshacibles.

**Prueba de interfaz.** `test/e2e/stroke_panel_parity_e2e.gd`.

**Reabierta (revisión 2026-11-02).** El requisito incluye «uniones»: no se puede dar por cerrada dejándolas como función nueva.

**Resolución (2026-11-02, intento 2).**
- **Uniones:** `stroke_join` (inglete / redonda / bisel) y `stroke_miter_limit` en figuras y trazados. La malla (`stroke_geom.gd`) hace cada esquina sin solapes: un trazo semitransparente ya no oscurece las esquinas. El inglete que supera el límite se bisela, como en SVG/PDF. Se exportan a SVG, PDF, EPS y JSON, y se importan de SVG.
- **Interfaz:** un único componente, `StrokeJoinRow` (fila «Unión» con iconos dibujados con la misma geometría y el límite, activo solo con inglete), en Smart, Modern y Pro.
- **Modern (petición del usuario: «trazos es malísimo»):** la sección Trazo es ahora el panel COMPLETO de Smart, sin la fila compacta («Center/Inside/Outside» a 9 px, ojo y «−»). Perfil, extremos y estilo se ocultan si el objeto no los tiene. Las muestras ya no son barras macizas.
- **Encontrado de paso:** las figuras (rectángulo, elipse, estrella, polígono) no guardaban estilo, alineación ni guiones del trazo, que se perdían al reabrir. Ahora se guardan.
- **Pruebas:** `StrokeJoin_test.gd` (8: áreas exactas de cada unión, límite → bisel, sin solapes en un cuadrado cerrado, guardado, SVG); `stroke_panel_parity_e2e.gd` (25, ahora con unión y límite en los tres modos); `modern_stroke_panel_e2e.gd` (20, clics y deshacer en Modern, capturas claro y oscuro).

**Resultado anterior (intento 1).** La paridad ya la trajo UX-06 de la lista anterior
(commit `89f28c3`, posterior al RPM instalado): la prueba usa con clics reales
todos los controles del panel «Trazos y Borde» de Smart, del Inspector de
Modern y del lateral de Pro, con una línea y con un rectángulo, y en los tres
modos se editan las mismas 11 propiedades de trazo del rectángulo y 13 de la
línea (color, grosor, alineación, remates, estilo, guion/hueco, puntas, escala
de puntas y perfil), cada una con su paso de deshacer y deshaciendo todo vuelve
a como estaba. **Uniones** (inglete/redonda/bisel) no existen en ningún modo
(tampoco en Smart): el trazo usa inglete con límite y unión redonda en giros
cerrados. Se propone como función nueva aparte (modelo + malla + SVG/PDF).

---

## 10. UX-09 — Pro: pestañas reubicables y flotantes

**Síntoma.** En Pro las pestañas del Inspector son fijas; se solicita poder
arrastrarlas para reordenarlas y desprenderlas como ventana flotante, al estilo
Affinity.

**Evidencia.** `script_gdscript/ui/docked_inspector.gd`,
`script_gdscript/ui/components/panel_edge_resizer.gd`.

**Corrección propuesta.**
1. Reordenación por arrastre con indicador de inserción.
2. Desprendimiento a ventana flotante (`Window`) conservando el contenido y el
   estado; reacoplamiento por doble clic.
3. Persistir el orden y qué pestañas están flotando.

**Criterio de aceptación.**
- [x] Reordenar sin perder la pestaña activa.
- [x] Flotar y reacoplar sin recrear el contenido.
- [x] La disposición se conserva entre sesiones.

**Prueba de interfaz.** `test/e2e/pro_tabs_dock_float_e2e.gd`.

**Resolución (2026-11-02).** Las pestañas de las dos tiras del lateral de Pro
(Color/Muestras/Trazo y Transformar/Texto/Efectos) se arrastran para cambiar el
orden, con una línea de acento donde caerán; soltadas fuera del lateral se abren
en una ventana flotante con la MISMA página. Doble clic en su cabecera (o
cerrarla) la vuelve a acoplar. Orden, flotantes, posición y tamaño se guardan en
`user://vectopen_pro_tabs.cfg` y se restauran al reconstruir el lateral (cambio
de tema) y al arrancar. Los índices de `_select_tab_a/_b` siguen siendo los de
siempre (el orden es solo visual). Arrastre real de Godot en la prueba.

---

## 11. UX-10 — Borrado con `Delete` y `Supr`

**Síntoma.** Ya existe `X`, pero clientes piden `Delete` y `Supr`, como en los
editores tradicionales.

**Evidencia parcial.** Ya hay soporte en algunos contextos:
`script_gdscript/tools/move/move_tool_keyboard.gd:41`,
`script_gdscript/tools/NodeSelectionTool.gd:280`,
`script_gdscript/tools/beziertool.gd:81`.

**Corrección propuesta.** Verificar la cobertura en **todos** los contextos
(lienzo, nodos, capas, tablas, puntos de degradado) y centralizar la lista de
teclas de borrado en una constante compartida.

**Criterio de aceptación.**
- [x] `X`, `Delete` y `Supr` borran de forma equivalente en cada contexto.
- [x] No interfieren al editar texto ni en campos numéricos.

**Prueba de interfaz.** `test/e2e/delete_keys_matrix_e2e.gd`.

**Resolución (2026-11-02).** Causa real de que «Supr no borra»: el editor de
degradado del selector de color (también el oculto) tenía siempre un punto
seleccionado y se quedaba **Supr y Retroceso en toda la aplicación**; en el
lienzo solo funcionaba la X. Ahora solo los usa si el último clic fue en él.
Lista única `VectopenInput.DELETE_KEYS` (X, Supr/Delete, Retroceso) y
`is_delete_event()` (sin Ctrl/Alt/Cmd y nunca escribiendo) en lienzo, nodos,
mover, capas, páginas, puntos de degradado y guías (antes páginas solo Supr y
degradado/guías sin X). La prueba cubre las tres teclas en los seis contextos
y que no borran escribiendo en un campo (27 comprobaciones).

---

## 12. UX-11 — Modern: los trazos no se muestran

**Síntoma.** En el modo Modern los trazos no aparecen: el lienzo queda sin
representación del trazo creado.

**Hipótesis técnica.** El panel o la capa de dibujo propia del modo no se
instancia, o el trazo se crea en un contenedor con visibilidad desactivada.

**Evidencia.** `script_gdscript/ui/panel_trazos.gd`,
`script_gdscript/ui/adaptive_ui_manager.gd`, `script_gdscript/tools/brushtool.gd`.

**Corrección propuesta.** Instrumentar la creación (¿existe el nodo?, ¿es visible?,
¿está en el árbol?) y corregir la ruta de instanciación del panel y del contenedor.

**Criterio de aceptación.**
- [ ] Dibujar en Modern muestra el trazo inmediatamente (no reproducido aún con el caso del usuario).
- [ ] El trazo persiste al cambiar de modo.
- [ ] Sin regresiones en Smart y Pro.

**Prueba de interfaz.** `test/e2e/modern_strokes_visible_e2e.gd`.

**Resultado (2026-11-02).** No reproducible en el código actual. La prueba dibuja
con clics reales pincel (arrastre) y Bézier (tres puntos + Intro) en Modern,
Smart y Pro, con presión de ratón (0) y de lápiz (`UX11_PRESSURE=1`): el nodo
existe, está en el árbol, es visible, se ve **mientras** se dibuja y al
terminar, y sigue ahí tras cambiar de modo (43 comprobaciones en verde). La
aplicación instalada es el RPM `0.2.0-0.1.alpha` del 28/10, anterior a los
últimos arreglos. **Pendiente de insumo:** pasos exactos o archivo con el que
falla (¿herramienta, pincel o ajuste concreto? ¿o se refería al *panel*
«Trazos y Borde», que es UX-08?). La prueba queda como regresión.

---

## 13. UX-12 — Revisión profunda del Inspector

**Síntoma.** La cobertura y la calidad del Inspector son desiguales entre texto,
trazos, párrafos y relleno.

**Alcance de la revisión.**
1. Inventario completo de propiedades por tipo de objeto.
2. Correspondencia entre `PROPS`, lector, escritor y control visible.
3. Comportamiento de undo/redo en cada propiedad.
4. Coherencia visual y agrupación por secciones.

**Evidencia.** `autoloads/InspectorCore.gd` (constante `PROPS`),
`script_gdscript/ui/docked_inspector.gd`,
`script_gdscript/ui/components/inspector_extra_props.gd`.

**Corrección propuesta.** Generar la interfaz desde `PROPS` y añadir una prueba que
falle si una propiedad declarada carece de control o de escritura efectiva.

**Criterio de aceptación.**
- [x] Cero propiedades declaradas sin control.
- [x] Cero controles sin efecto real.
- [x] Undo/redo correcto en todas.

**Prueba de interfaz.** `test/e2e/inspector_coverage_e2e.gd`.

**Resolución (2026-11-02).** El arnés de UX-06 en modo estricto (8 tipos de
objeto, Modern y Pro, página a página en Pro) detecta controles sin efecto
(nada escrito, sin paso de historial, nada mostrado u ocultado, sin cambio
propio), comprueba rehacer y que cada propiedad de `PROPS` la tenga algún
objeto. Encontró y se corrigió: perfil y tamaño de punta ofrecidos a figuras que
no los tienen; pestaña Texto de Pro activa sin texto seleccionado (mayúsculas,
alinear…) y Color/Muestras/Trazo con un modelo 3D; «Romper enlace» y
«Reorganizar» siempre activos (este redistribuía el texto **sin deshacer** y se
perdía); «Restablecer vista 3D» y «Encuadrar» sin deshacer; la gota de agua
tratada como polígono regular (sin su curvatura; «Regular» la rompía y deshacer
no la devolvía). Resultado: 82 comprobaciones en verde.

**Pendiente de la propuesta (revisión 2026-11-02):** la interfaz no se genera desde `PROPS`; la prueba sí falla si una propiedad no tiene control.

---

## 14. UX-13 — Shader, Script, Vectorizar y Plugins junto a Exportar

**Síntoma.** El acceso a Shader, Script, Vectorizar y Plugins no está resuelto con
la jerarquía esperada: se solicitan como **iconos junto a Exportar**, con su
contenido mostrado en el Inspector.

**Evidencia.** `script_gdscript/ui/docked_inspector.gd`,
`script_gdscript/ui/panels/effects/vectorize_panel.gd`,
`autoloads/PluginManager.gd`.

**Corrección propuesta.**
1. Barra de acciones con cuatro iconos contiguos a Exportar.
2. Cada icono abre su sección en el Inspector (patrón ya usado por otras
   pestañas), no un diálogo modal.
3. Estado activo visible y conmutable.

**Criterio de aceptación.**
- [x] Los cuatro iconos visibles en los tres modos.
- [x] Cada uno abre su panel en el Inspector sin cerrar la selección.
- [x] Sin duplicar editores ya existentes.

**Prueba de interfaz.** `test/e2e/inspector_action_icons_e2e.gd`.

**Resolución (2026-11-02).** Componente `ui/components/fx_action_icons.gd`
junto a Exportar en la barra de Modern, la de Pro y el chip de Smart: Shader,
Script, Vectorizar y Complementos (icono de pieza de puzle nuevo). Abren SU
sección (Inspector en Modern, pestaña Efectos en Pro, ventana Efectos en Smart),
la llevan a la vista y el icono queda resaltado (borde e icono de acento);
volver a pulsar la cierra. Script y Complementos abren su página. Una sección
abierta desde el icono se ve aunque no haya selección. 177 comprobaciones.

---

## 15. UX-14 — Inspector redimensionable por arrastre

**Síntoma.** El Inspector tiene ancho fijo; Script y Shader requieren más espacio
para escribir con comodidad. Se solicita arrastrar el borde como en el panel
izquierdo, y en Pro además poder flotarlo.

**Evidencia.** `script_gdscript/ui/components/panel_edge_resizer.gd` (componente
ya existente y reutilizable), `script_gdscript/ui/docked_inspector.gd`.

**Corrección propuesta.**
1. Reutilizar `panel_edge_resizer.gd` en el borde del Inspector, con ancho mínimo
   y máximo y doble clic para restablecer.
2. Persistir el ancho por modo.
3. En Pro, permitir desacoplar el Inspector a ventana flotante redimensionable.

**Criterio de aceptación.**
- [x] Arrastre fluido, sin saltos, con límites razonables.
- [x] El ancho se conserva entre sesiones y por modo.
- [x] En Pro, flotar y reacoplar conserva contenido y tamaño.

**Prueba de interfaz.** `test/e2e/inspector_resize_e2e.gd`.

**Resolución (2026-11-02).** `panel_edge_resizer.gd` en el borde izquierdo del
lateral derecho (Modern y Pro): 240 px mínimo, 60 % de la ventana máximo, la
regla y el lienzo se apartan, doble clic = ancho por defecto, guardado por modo.
En Pro, botón «Inspector flotante» en la barra superior: el lateral (el mismo
nodo, con su pestaña) pasa a una ventana redimensionable; cerrarla lo acopla con
su ancho; la ventana recuerda su tamaño; cambiar de modo lo reacopla.

---

## 15 bis. UX-15 — Inspector: barras gris claro con texto blanco (estilo de Capas)

**Síntoma (usuario, 2026-11-02).** «En el Inspector hay muchas barras gris claro
con texto blanco: no es la UI de Vectopen como la tiene Capas. La UI de Capas es
la referencia para todo el diseño de la UI, elegante.» Visto en la captura de
Modern (tema claro): el campo «Nombre» y los campos desactivados son barras
grises con texto blanco.

**Corrección propuesta.** Revisar todos los campos, botones y filas del Inspector
(Modern y Pro, tema claro y oscuro) contra el panel de Capas: superficies, bordes,
texto y estados (normal, hover, foco, desactivado) con los colores del tema de
Capas; nada de gris fijo ni texto blanco sobre gris claro.

**Criterio de aceptación.**
- [x] Ningún control del Inspector con contraste de texto < 4,5:1 (3:1 desactivado/secundario).
- [x] Superficies y bordes con los mismos colores del tema que Capas.
- [x] Claro y oscuro, Modern y Pro, con capturas.

**Prueba de interfaz.** `test/e2e/inspector_capas_style_e2e.gd`.

**Resolución (2026-11-02).** Causa: el tema de Vectopen se ponía en la ventana
raíz, pero entre ella y la interfaz hay un `Node2D` (CanvasRoot) y un
`CanvasLayer`, que cortan la herencia de temas de Godot. Todo control sin estilo
propio caía en el tema por defecto de Godot: fondo gris translúcido
`(0.1, 0.1, 0.1, 0.6)` con texto `#DFDFDF`, las «barras gris claro con texto
blanco» (campo Nombre, botones Inicio/Fin/Estilo/Perfil de Pro, cabeceras
FILTROS/SHADER/SCRIPT, cabecera de pestaña flotante…).
- `ThemeManager.adopt()` aplica el tema de Vectopen directamente al Inspector de
  Modern y al lateral de Pro, y lo renueva al cambiar de tema.
- El tema añade el campo de solo lectura y las ventanas incrustadas (barra de
  título del tema e icono de cerrar propio; antes se usaba `x.svg`, que es el
  logotipo de X).
- El Inspector repinta sus etiquetas al cambiar de tema: en oscuro las cabeceras
  se quedaban con el gris del tema claro (2,8:1).
- Sufijos de los campos numéricos con el texto secundario del tema.
- Prueba: 186 comprobaciones (Modern y Pro, cada pestaña de Pro, rectángulo,
  trazado y texto, claro y oscuro, ventana flotante). Antes: 60 fallos.
- `run_all.sh` y la batería unitaria parten ahora de los ajustes de fábrica:
  la disposición guardada del usuario cambiaba los resultados.

---

## 16. Protocolo de ejecución: corrección automática en bucle

```
reproducir → medir → corregir → prueba de interfaz → medir de nuevo
      ↑                                                    │
      └────────────── si falla, repetir ───────────────────┘
```

**Reglas.**
1. Ninguna corrección sin una prueba que falle antes del cambio.
2. Una incidencia por iteración; no se mezclan cambios.
3. El ciclo solo termina con la prueba en verde y la regresión intacta.
4. Tras tres intentos fallidos se detiene, se documenta y se replantea.
5. Al cerrar las catorce, se ejecuta la suite completa y **comienza la Fase B**
   (§19): 30 proyectos de diseñador senior en Smart, Modern y Pro. Los defectos
   que aparezcan vuelven al bucle con ID `VAL-nn` y se corrigen antes de cerrar.
6. El bucle solo se declara terminado cuando la Fase A está en verde y la Fase B
   tiene 30/30 proyectos aprobados.

**Orden recomendado.** UX-11 → UX-02 → UX-01 → UX-04 → UX-08 → UX-12 → UX-13 →
UX-14 → UX-06 → UX-07 → UX-09 → UX-03 → UX-10 → UX-05.

### 16.1. Autonomía

- Ejecutar sin preguntas intermedias: la aprobación se entiende otorgada al
  iniciar el bucle.
- Ante ambigüedad menor (nombre de un control, texto de una etiqueta), decidir
  con el criterio del proyecto y anotarlo en el progreso; no detenerse.
- Ante ambigüedad de alcance (UX-05), aislar la incidencia, continuar con el
  resto y dejar la pregunta al final.
- Nunca dejar el repositorio en estado rojo entre iteraciones: si una corrección
  no cierra, revertir ese cambio aislado antes de pasar a la siguiente.

### 16.2. Condiciones de parada del bucle

1. Las catorce incidencias están cerradas con prueba en verde.
2. Una incidencia acumula tres intentos fallidos → se marca **bloqueada** con
   causa, evidencia y propuesta alternativa, y se continúa.
3. Falta un recurso externo imprescindible (archivo de prueba, credencial,
   decisión de producto) → se marca **pendiente de insumo** y se continúa.
4. La regresión global empeora de forma sostenida → se detiene todo y se
   documenta el conflicto entre incidencias.

### 16.3. Reanudación

El bucle debe poder retomarse en cualquier momento leyendo únicamente la tabla
del §18: la primera fila que no esté en `Verde` es el siguiente objetivo.

**Comandos.**

```sh
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests res://test
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests res://test/e2e
```

---

## 17. Trazabilidad

| ID | Archivos principales | Prueba asociada | Estado |
|---|---|---|---|
| UX-01 | `ui/layers_system.gd`, `canvas_serializer.gd` | `clip_mask_bezier_e2e.gd` | Verde |
| UX-02 | `autoloads/VectopenInput.gd`, `docked_inspector.gd` | `inspector_keyboard_focus_e2e.gd` | Verde |
| UX-03 | `PaletteSaveGrid.gd`, `ListaColor.gd` | `palette_delete_gradient_e2e.gd` | Verde |
| UX-04 | `adaptive_ui_manager.gd`, `ListaColor.gd` | `palette_modes_e2e.gd` | Verde |
| UX-05 | — | — | Por aclarar |
| UX-06 | `panel_brush.gd` | `brush_panel_theme_e2e.gd` | Abierta |
| UX-07 | `panel_bezier.gd` | `bezier_panel_theme_e2e.gd` | Verde |
| UX-08 | `panel_trazos.gd`, `stroke_geom.gd` | `stroke_panel_parity_e2e.gd`, `modern_stroke_panel_e2e.gd` | Verde |
| UX-09 | `docked_inspector.gd`, `panel_edge_resizer.gd` | `pro_tabs_dock_float_e2e.gd` | Verde |
| UX-10 | `move_tool_keyboard.gd`, `NodeSelectionTool.gd` | `delete_keys_matrix_e2e.gd` | Verde |
| UX-11 | `panel_trazos.gd`, `adaptive_ui_manager.gd` | `modern_strokes_visible_e2e.gd` | Pendiente de insumo |
| UX-12 | `InspectorCore.gd`, `docked_inspector.gd` | `inspector_coverage_e2e.gd` | Verde |
| UX-13 | `docked_inspector.gd`, `vectorize_panel.gd` | `inspector_action_icons_e2e.gd` | Verde |
| UX-14 | `panel_edge_resizer.gd`, `docked_inspector.gd` | `inspector_resize_e2e.gd` | Verde |
| UX-15 | `ThemeManager.gd`, `docked_inspector.gd`, `numeric_field.gd`, `pro_studio.gd` | `inspector_capas_style_e2e.gd` | Verde |

---

## 18. Registro de progreso del bucle

Actualizar en cada iteración. Estados: `Abierta` · `En curso` · `Verde` ·
`Bloqueada` · `Pendiente de insumo`.

| ID | Intento | Estado | Prueba | Nota / causa |
|---|---:|---|---|---|
| UX-01 | 1 | Verde | `clip_mask_bezier_e2e.gd` | Máscara sin dibujo = contenido sin recortar; relleno par-impar y área implícita |
| UX-02 | 1 | Verde | `inspector_keyboard_focus_e2e.gd` | Guarda `is_typing()`; Escape suelta el campo (fallaba en Pro) |
| UX-03 | 1 | Verde | `palette_delete_gradient_e2e.gd` | Color o degradado; clic derecho Eliminar/Duplicar con deshacer |
| UX-04 | 1 | Verde | `palette_modes_e2e.gd` | En Pro la recortaba el lateral; ahora flota junto al selector |
| UX-05 | 0 | Pendiente de insumo | — | Falta identificar el panel |
| UX-06 | 2 | Abierta | `brush_panel_theme_e2e.gd` | Colores hechos; faltan iconos SVG (quedan emojis) y campos comunes |
| UX-07 | 1 | Verde | `bezier_panel_theme_e2e.gd` | Tarjetas con superficie del tema, iconos SVG, campo numérico común |
| UX-08 | 2 | Verde | `stroke_panel_parity_e2e.gd`, `modern_stroke_panel_e2e.gd` | Uniones en los 3 modos; Modern con el panel completo de Smart; trazo de figuras guardado |
| UX-09 | 1 | Verde | `pro_tabs_dock_float_e2e.gd` | Arrastrar = reordenar; soltar fuera = flotar; doble clic = acoplar; persistente |
| UX-10 | 1 | Verde | `delete_keys_matrix_e2e.gd` | El editor de degradado se quedaba Supr/Retroceso; lista única de teclas |
| UX-11 | 1 | Pendiente de insumo | `modern_strokes_visible_e2e.gd` | No reproducible (43/43 verde en los 3 modos); faltan pasos o archivo |
| UX-12 | 1 | Verde | `inspector_coverage_e2e.gd` | Modo estricto: 82 comprobaciones; 7 defectos corregidos |
| UX-13 | 1 | Verde | `inspector_action_icons_e2e.gd` | Cuatro iconos junto a Exportar en los tres modos |
| UX-14 | 1 | Verde | `inspector_resize_e2e.gd` | Borde arrastrable por modo; Pro flotante |
| UX-15 | 1 | Verde | `inspector_capas_style_e2e.gd` | El tema no llegaba a la UI (CanvasLayer corta la herencia): se aplica al Inspector y a Pro |

**Resumen Fase A:** 12 / 15 en verde · abierta: UX-06 (reabierta) · 2 pendientes de insumo (UX-05: panel
sin identificar; UX-11: no reproducible, faltan pasos o archivo). La Fase B no
puede empezar hasta que estas dos se cierren (puerta del §19.1).
**Resumen Fase B:** 0 / 30 proyectos aprobados.

**Seguimiento (no mezclado):** con la pestaña «Efectos» de Pro flotando, los
iconos Shader / Script / Vectorizar no la traen a la vista (visto al probar con
la disposición real del usuario). Pendiente como incidencia aparte.

---

## 19. Fase B — Validación de campo con 30 proyectos reales

### 19.1. Propósito y puerta de entrada

Las pruebas por incidencia demuestran que un defecto concreto está corregido; no
demuestran que el producto sirva. Esta fase lo comprueba **usándolo como lo haría
un diseñador senior**: treinta encargos realistas, con restricciones de formato,
tipografía, exportación y entrega.

- **Puerta de entrada:** Fase A completa en verde (§18). No se empieza antes.
- **Rol:** diseñador senior, exigente, que no conoce el código.
- **Regla:** cada proyecto se ejecuta en el modo indicado y, al menos una vez, se
  repite en los otros dos para detectar divergencias Smart/Modern/Pro.
- **Duración orientativa:** un encargo por iteración; sin atajos ni datos falsos.

### 19.2. Los 30 encargos

| # | Encargo | Modo principal | Foco de la prueba |
|---:|---|---|---|
| 1 | Libro de 20 páginas | Pro | Páginas, pliegos 1‑2‑2‑2, índice, numeración |
| 2 | Revista de 8 páginas | Pro | Retícula, texto en columnas, imágenes |
| 3 | Cartel A1 | Smart | Formato grande, textos a escala, export PDF |
| 4 | Flyer para redes (1080×1350) | Modern | Composición rápida, export PNG |
| 5 | Logo vectorial con variantes | Pro | Booleanas, uniones, versiones mono |
| 6 | Isotipo con anillo | Smart | Modo anillo 0–360 (UX‑04), degradado |
| 7 | Tarjeta de visita | Modern | Márgenes, tipografía pequeña, sangrado |
| 8 | Infografía de datos | Pro | Trazos, iconos, jerarquía tipográfica |
| 9 | Enciclopedia visual (12 fichas) | Pro | Rejilla de páginas, consistencia |
| 10 | UI kit de aplicación | Modern | Componentes repetidos, estilos de texto |
| 11 | Wireframe de landing | Modern | Bloques, alineación, snapping |
| 12 | Set de 24 iconos | Smart | Trazo coherente, export SVG individual |
| 13 | Ilustración con pinceles | Smart | 300+ trazos, fluidez y memoria |
| 14 | Retrato con máscaras | Pro | Clip entre dos Bézier (UX‑01) |
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

### 19.3. Lista de comprobación por encargo (20 puntos)

Cada uno de los 30 proyectos debe superar los veinte puntos; un solo fallo
convierte el encargo en defecto `VAL-nn`.

1. Crear documento con el formato exacto (mm/px, sangrado, orientación).
2. Crear y reordenar páginas/artboards; verificar pliegos y rejilla.
3. Capas: renombrar, agrupar, anidar, ocultar, bloquear.
4. Máscara de recorte y su persistencia al reabrir.
5. Trazo: grosor, perfil, extremos, uniones, guiones, puntas.
6. Relleno: sólido, degradado (lineal/radial) y patrón.
7. Texto: título, párrafo, texto en curva y estilos.
8. Transformar, rotar, escalar y voltear sin deformar el texto.
9. Alineación, distribución y snapping con guías.
10. Efectos: aplicar, desactivar, reordenar y eliminar.
11. Shader o script cuando el encargo lo requiera.
12. Vectorización cuando el encargo lo requiera.
13. Deshacer/rehacer de al menos 20 pasos seguidos.
14. Guardar, cerrar, reabrir: ida y vuelta sin pérdidas.
15. Exportar PNG, SVG y PDF; comparar con lo visto en pantalla.
16. Rendimiento: 60 FPS de referencia y sin bloqueos perceptibles.
17. Atajos: `X`, `Delete`, `Supr`, herramientas y `Escape`.
18. Tema claro y oscuro: legibilidad y contraste.
19. Coherencia entre Smart, Modern y Pro (misma acción, mismo resultado).
20. Cierre limpio: sin diálogos inesperados, sin errores en consola, sin autosave
    corrupto.

### 19.4. Registro y triaje de defectos

- Cada fallo se registra como `VAL-nn` con: encargo, modo, pasos, resultado
  esperado, resultado obtenido y captura.
- Severidad: **Alta** si impide terminar el encargo o corrompe el archivo;
  **Media** si obliga a una workaround; **Baja** si es cosmético.
- Los `VAL-nn` de severidad alta o media vuelven al bucle (§16) y se corrigen
  antes de continuar con el siguiente encargo; los bajos se acumulan y se
  resuelven en un cierre dedicado.
- Un encargo no se marca aprobado con defectos abiertos de severidad alta o media.

### 19.5. Automatización y materiales

- Cada encargo se guarda como fixture: `test/fixtures/proyectos/<nn>-<nombre>.vtc`.
- Prueba asociada: `test/e2e/proyecto_<nn>_e2e.gd`, que abre el fixture, aplica
  las acciones, exporta y compara contra referencia.
- Las capturas de referencia viven en `test/fixtures/refs/` y se actualizan solo
  con revisión explícita (un cambio visual no debe pasar inadvertido).
- La matriz de los 30 encargos se ejecuta en CI con `--headless` y, para las
  comprobaciones visuales, con captura por página.

### 19.6. Criterios de salida (Definition of Done)

- [ ] Fase A: 14/14 en verde.
- [ ] Fase B: 30/30 encargos aprobados en su modo principal.
- [ ] Repetición cruzada: los 30 ejecutados también en los otros dos modos sin
      divergencias de severidad alta o media.
- [ ] Cero defectos `VAL-nn` abiertos de severidad alta o media.
- [ ] Exportaciones deterministas: mismo archivo de entrada → mismo resultado.
- [ ] Sin errores en consola durante la matriz completa.
- [ ] Documentación actualizada: esta tabla y `ROADMAP.md`.

---

### 19.7. Progreso de la Fase B

| Encargo | Estado | Modos verificados | Defectos |
|---|---|---|---|
| 01 Libro 20 páginas | Pendiente | — | — |
| 02 Revista 8 páginas | Pendiente | — | — |
| 03 Cartel A1 | Pendiente | — | — |
| 04 Flyer redes | Pendiente | — | — |
| 05 Logo vectorial | Pendiente | — | — |
| 06 Isotipo anillo | Pendiente | — | — |
| 07 Tarjeta de visita | Pendiente | — | — |
| 08 Infografía | Pendiente | — | — |
| 09 Enciclopedia visual | Pendiente | — | — |
| 10 UI kit | Pendiente | — | — |
| 11 Wireframe landing | Pendiente | — | — |
| 12 Set 24 iconos | Pendiente | — | — |
| 13 Ilustración con pinceles | Pendiente | — | — |
| 14 Retrato con máscaras | Pendiente | — | — |
| 15 Mapa estilizado | Pendiente | — | — |
| 16 Diagrama técnico | Pendiente | — | — |
| 17 Portada de álbum | Pendiente | — | — |
| 18 Packaging texto en curva | Pendiente | — | — |
| 19 Menú de restaurante | Pendiente | — | — |
| 20 Invitación caligráfica | Pendiente | — | — |
| 21 Póster tipográfico | Pendiente | — | — |
| 22 Historieta 4 viñetas | Pendiente | — | — |
| 23 Tabla comparativa | Pendiente | — | — |
| 24 Certificado | Pendiente | — | — |
| 25 Manual de marca | Pendiente | — | — |
| 26 Presentación 10 slides | Pendiente | — | — |
| 27 Shader degradado animado | Pendiente | — | — |
| 28 Script avanzado | Pendiente | — | — |
| 29 Vectorizar logo | Pendiente | — | — |
| 30 Vectorizar foto | Pendiente | — | — |

---

*Documento de trabajo. Las versiones anteriores permanecen en el historial de git;
la de septiembre está archivada en `docs/archive/PENDIENTE-2026-09.md`.*
