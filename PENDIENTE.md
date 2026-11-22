# PENDIENTE — Lo que queda por hacer

**Proyecto:** Vectopen (Godot 4.7, GDScript)
**Fecha:** 2026-11-22 · versión publicada: **0.2.3-beta** · preparada sin
publicar: **0.2.4-beta** (etiqueta `v0.2.4-beta` subida; release cancelada:
no se publica sin permiso del usuario)

**Solo trabajo abierto.** Lo terminado se QUITA de este documento (queda en
git: `git log -p PENDIENTE.md`). Versiones completas anteriores en
`docs/archive/`.

---

## 0. Modo de trabajo (`/loop`)

Un punto por iteración:
`reproducir → prueba que falla → corregir → prueba en verde → suite unitaria → commit`.

- Pruebas e2e en la Huion (`--screen 1`) con ajustes de fábrica; suite
  unitaria (`bash test/run_unit.sh`) en verde antes de cada commit.
- Al cerrar algo, **se quita de este documento**.
- 2026-11-22: el usuario pide hacerlo TODO («hazlo todos»), probarlo él y
  después publicar la 0.2.4-beta. Las decisiones pendientes se tomaron con
  la recomendación de Claude (anotadas como **Decidido**); **[usuario]** =
  solo lo puede hacer el usuario. No publicar hasta que el usuario lo pruebe.

---

## 0 ter. VGSE — motor de trazos (lo que falta)

Documento: `docs/roadmap/VGSE-informe-conceptual-y-propuesta-tecnica.md`.

| Fase | Punto | Estado |
|---|---|---|
| 2 | Pincel de patrón: la pieza de esquina va en la tesela que empieza en el giro; centrarla exactamente en la esquina (recolocando las teselas, como Illustrator) y editar las piezas de un trazo ya dibujado desde el inspector | Pendiente (mejora) |

---

## 0 quater. Rendimiento con muchos elementos

Referencia (`scene_benchmark_e2e`, `E2E_ENV="BENCH_N=… BENCH_MODE=high|low"`):
50 000 elementos en modo débil → crear 15 s, cargar 12 s, 9,6 fps, 1,5 GB.

| ID | Punto | Estado |
|---|---|---|
| — | Memoria ~31 KB por elemento (figuras ~22 KB, trazos ~24 KB): bajarla exige rehacer la estructura de VectorShape | **Decidido**: mejoras sin rehacer VectorShape (cachés, metas, nodos auxiliares por demanda) |
| — | Dibujar con todo a la vista (50 000) y zoom: nivel de detalle / caché al alejar. Quedan ~1,8 llamadas de dibujo por elemento | En curso |
| — | CullManager: «dormir» páginas lejanas (`stream_artboards`). Apagado: nunca funcionó; probar con documentos de muchas páginas antes de activarlo | Pendiente |
| — | Seleccionar todo con 50 000 (5 s) y mover la selección (184 ms por paso) | En curso |
| VAL-39 | 50 000 elementos en modo débil: hasta 3 GB y 5,6 fps con todo a la vista (7 500 trazos incluidos) | Abierto (depende de la decisión de memoria) |
| MEM-06 | Texto: ~35 KB por texto (nodo + Label oculto + texto nativo); el Label oculto lo usan 85 sitios | Abierto |

---

## 0 septies. Plataformas

| ID | Tarea | Estado |
|---|---|---|
| PLAT-05 | Subir la clave permanente de Android como secretos de GitHub (`ANDROID_KEYSTORE_BASE64/USER/PASSWORD`; está en `~/.local/share/vectopen-release/`) | **Decidido**: subirla (sin mostrar valores) |
| PLAT-06 | Librerías nativas en Android (falta el NDK; mientras, texto e importadores por GDScript) | Pendiente |
| PLAT-08 | Interfaz para Android y tabletas (la APK es una vista previa) | **[usuario]** la diseña el usuario |

## 0 octies. Tanda del usuario (2026-11-13/21)

USR-35…39 hechos (2026-11-22). Lo que sigue es el informe de propuestas que
aportó el usuario (backlog de producto).

### Informe técnico de propuestas de mejora (2026-11-21)

Informe aportado por el usuario. Se guarda como backlog de producto; el
texto original termina a media frase («La incorporación») y se cierra abajo
con una línea de resumen. (Su §6 era USR-38: hecho, quitado.)

**Área:** Geometría vectorial, herramientas de composición, maquetación
profesional y experiencia de usuario (UI/UX).

**Objetivo:** Ampliar las capacidades de Vectopen para convertirlo en una
herramienta de diseño vectorial y composición visual más flexible,
eficiente y adecuada para proyectos profesionales.

#### 2. Iluminación 2D — lo que falta

Hecho (2026-11-22): herramienta **Luz** ☀ en la barra de herramientas
(Smart / Pro: columna; Modern: barra inferior) con su panel
**Iluminación**: tipos puntual, foco, direccional y ambiente (registro
`VectorLight.TYPE_INFO`, preparado para más tipos), color, intensidad,
alcance, dirección, apertura del foco, borde, mezcla y **sombra** (activada
por defecto, color y suavidad); clic = colocar, arrastrar = alcance y
dirección; con una luz seleccionada el panel la edita (deshacer). Cada
figura: «Proyecta sombra». .vtp, PNG / JPEG / WEBP; API `add_light`
(`lights_e2e` 14/0, `light_tool_e2e` 30/0). Falta (después, a petición del
usuario):

- Luz y sombras en SVG / PDF.
- Limitar una luz a su página (hoy alumbra también lo que está cerca fuera).
- Tipos avanzados: luz de área / línea, luz con textura (gobo), luz normal
  map / relieve, sombras de longitud limitada.

#### 3. Fusión (Blend) — lo que falta

Hecho (2026-11-22): `script_gdscript/shapes/blend.gd` — clic derecho ▸
«Crear fusión (Blend)» con dos figuras (o tres, si una es un trazado abierto
= guía) en Smart, Modern y Pro; forma, color de relleno y trazo, grosor y
opacidad interpolados; pasos fijos o por distancia; a lo largo de la guía,
orientados o no; no destructiva (se rehace sola al cambiar A, B o la guía);
ajustes en el inspector con deshacer; «Expandir fusión»; .vtp; API
`make_blend` / `blend_set` / `expand_blend` (`Blend_test` 7/0, `blend_e2e`
13/0). Falta:

- Fusión de MÁS de dos objetos (A → B → C) y de grupos / objetos complejos
  (hoy: dos figuras sueltas; los grupos se interpolan como su contorno no).
- Interpolar también escala / rotación de forma explícita (hoy van dentro de
  la forma) y degradados.
- Herramienta propia de fusión (clic en A y en B en el lienzo).

#### 4. Contenedores (Auto Layout) — lo que falta

Hecho (2026-11-22): `script_gdscript/shapes/auto_layout.gd` — clic derecho ▸
«Convertir en contenedor (Auto Layout)» (selección, grupo o un rectángulo
solo, que pasa a ser el fondo) / «Quitar contenedor»; modos fila (HBox),
columna (VBox), rejilla y fila que salta de línea (content flow);
separación, margen interior, alineación principal (inicio / centro / final /
repartir) y cruzada, columnas, ancho de línea, tamaño automático (el fondo
se ajusta); se recoloca solo al cambiar o mover un hijo; inspector con
deshacer; .vtp; API `make_layout` / `release_layout` (`AutoLayout_test`
7/0, `auto_layout_e2e` 12/0). Falta:

- Margen EXTERIOR por hijo, tamaños mínimo / máximo y «rellenar» (un hijo
  que ocupa el espacio sobrante).
- Ocultar en el inspector las filas que no aplican al modo (columnas solo en
  rejilla, ancho de línea solo en salto de línea).
- Tiradores en el lienzo para el margen y la separación (como Figma).

#### 5. Maquetación editorial — lo que falta

Hecho (2026-11-22): **páginas maestras** (`master_pages.gd`): Páginas ▸
«PÁGINA MAESTRA» (marcar la página como maestra · «Usar maestra» en la
página activa o en todas); lo de la maestra sale debajo del contenido de las
páginas que la usan, no se puede tocar en ellas, los {pág} / {total} dan el
número de cada página (las maestras no cuentan), se guarda, PNG / SVG; API
`set_master_page` / `use_master` (`master_pages_e2e` 15/0). Falta:

- **Combinación de datos** (catálogos): plantilla con {campo} + CSV → una
  ficha por fila, en rejilla y en páginas nuevas.
- **Índice automático** (nombres de página + número).
- Excluir las maestras de «PDF de todas las páginas» y marcarlas en el lienzo.

#### 7. Conclusión y visión técnica

Estas propuestas buscan ampliar Vectopen más allá de las funcionalidades de
un editor vectorial tradicional.

La incorporación de estas capacidades (esquinas avanzadas, iluminación 2D,
Blend, layout automático, maquetación multipágina y selección por
profundidad) acercaría a Vectopen a un estudio de diseño completo en una
sola app, sin perder el control preciso del objeto ni la salida a imprenta.

> **Prioridad sugerida** (no acordada): 1) layout, 2) iluminación 2D,
> 3) maquetación editorial (§1 esquinas hecho; Blend: primera versión). Cada bloque grande merece su propio documento de
> diseño en `docs/roadmap/` antes de codear.

## 0 nonies. VTP Preview — visor de documentos (2026-11-21) — propuesta

> **Fase 1 hecha (2026-11-22)**: `script_gdscript/ui/vtp_preview.gd` — ventana
> de solo lectura (Ctrl+Mayús+P, reasignable en «Teclado y ratón»; API
> `preview_document`): mismo lector que el editor en un SubViewport propio
> (el editor no ve sus páginas), modo seguro del serializador
> (`canvas_serializer.safe_mode`: sin `shader_code`, sin rutas fuera de
> `res://`), zoom con rueda / ± / teclas, desplazar arrastrando, ajustar
> página / todo, páginas ◀ ▶ (también RePág/AvPág), fondo claro / oscuro /
> cuadros, panel de información ocultable, aviso con archivos dañados
> (`vtp_preview_e2e` 14/0). **Fase 2 hecha**: explorador en la misma ventana
> (carpeta, lista de documentos con fecha y tamaño, del más reciente al más
> antiguo, filtro por nombre, un clic abre la vista previa; recuerda la
> carpeta) (`vtp_preview_e2e` 19/0). **Fase 3 hecha**: miniaturas de la
> primera página en segundo plano (una cada vez, modo seguro), en caché
> `user://thumbnails/` con clave ruta + fecha + tamaño (si el documento
> cambia, la antigua deja de usarse; tope de 400, se borran las más
> antiguas). **Fase 4 hecha**: árbol de capas de la página y datos del objeto
> (clic en el lienzo o en el árbol: tipo, posición respecto a la página,
> tamaño, relleno, trazo, grosor, opacidad) (`vtp_preview_e2e` 27/0).
> **Queda** la separación «modelo de documento / nodos» del lector (criterio
> 9: núcleo común editor / visor / futuro runtime web): decisión
> arquitectónica de fondo, conviene acordarla antes.

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

---

## 3. Publicación y actualizaciones

- [ ] **Decidido: avisarlo en la app** · Mac Intel: el vectorizador IA no existe (ONNX Runtime no
	  tiene binarios para `x86_64-apple-darwin`): compilarlo desde fuente o
	  avisarlo en la app.
- [ ] **Decidido: instalador NSIS** · Windows: el paquete es un `.zip`; el botón de actualizar
	  solo lo abre. Un instalador (`.exe`/`.msi`) permitiría actualizar de verdad.
- [ ] **[usuario]** (hace falta comprar un certificado) Firmar los binarios de Windows y macOS (avisos de
	  «desarrollador desconocido»; hace falta certificado).

---

## 4. Defectos y pruebas abiertos

| ID | Fallo | Estado |
|---|---|---|
| — | Cierre: queda 1 objeto «leaked at exit» (un `RefCounted` con referencia 0, sin clase visible con `--verbose`). Antes 108 objetos + texturas + textos; diagnóstico con `test/run_e2e.sh clean_exit_e2e` (mismo camino que la X de la ventana) | Abierto (menor) |

---

## 5. Criterios de cierre

Los 30 encargos de la Fase B están aprobados (pruebas
`test/e2e/proyecto_NN_e2e.gd`, kit `test/e2e/lib/campaign_kit.gd`). Los
defectos nuevos siguen la numeración desde **VAL-68**. Lista de comprobación
de cada encargo: `docs/archive/PENDIENTE-2026-11-21.md` (§5.2).

- [ ] Cero `VAL-nn` abiertos de severidad alta o media.
- [ ] Suite completa (unitaria + e2e) en verde y sin errores en consola.
