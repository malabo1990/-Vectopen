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
- Los puntos marcados **[decisión]** esperan al usuario: no se empiezan.

---

## 0 ter. VGSE — motor de trazos (lo que falta)

Documento: `docs/roadmap/VGSE-informe-conceptual-y-propuesta-tecnica.md`.

| Fase | Punto | Estado |
|---|---|---|
| 2 | Pincel de patrón con piezas distintas de inicio / esquina / final (como Illustrator) | Pendiente |
| 6 | Trazos de 100 000 muestras al dibujar: rehacer solo la cola (incremental). Hoy: 79 ms (pluma) / 160 ms (lápiz) por trazo completo | Pendiente |

---

## 0 quater. Rendimiento con muchos elementos

Referencia (`scene_benchmark_e2e`, `E2E_ENV="BENCH_N=… BENCH_MODE=high|low"`):
50 000 elementos en modo débil → crear 15 s, cargar 12 s, 9,6 fps, 1,5 GB.

| ID | Punto | Estado |
|---|---|---|
| — | Memoria ~31 KB por elemento (figuras ~22 KB, trazos ~24 KB): bajarla exige rehacer la estructura de VectorShape | **[decisión]** ¿merece la pena? |
| — | Dibujar con todo a la vista (50 000) y zoom: nivel de detalle / caché al alejar. Quedan ~1,8 llamadas de dibujo por elemento | En curso |
| — | CullManager: «dormir» páginas lejanas (`stream_artboards`). Apagado: nunca funcionó; probar con documentos de muchas páginas antes de activarlo | Pendiente |
| — | Seleccionar todo con 50 000 (5 s) y mover la selección (184 ms por paso) | En curso |
| VAL-39 | 50 000 elementos en modo débil: hasta 3 GB y 5,6 fps con todo a la vista (7 500 trazos incluidos) | Abierto (depende de la decisión de memoria) |
| MEM-06 | Texto: ~35 KB por texto (nodo + Label oculto + texto nativo); el Label oculto lo usan 85 sitios | Abierto |

---

## 0 septies. Plataformas

| ID | Tarea | Estado |
|---|---|---|
| PLAT-05 | Subir la clave permanente de Android como secretos de GitHub (`ANDROID_KEYSTORE_BASE64/USER/PASSWORD`; está en `~/.local/share/vectopen-release/`) | **[decisión]** |
| PLAT-06 | Librerías nativas en Android (falta el NDK; mientras, texto e importadores por GDScript) | Pendiente |
| PLAT-08 | Interfaz para Android y tabletas (la APK es una vista previa) | **[decisión]** la diseña el usuario |

## 0 octies. Tanda del usuario (2026-11-13/21) — sin empezar

Ninguna de estas peticiones está diseñada ni implementada: son el encargo
tal cual lo pidió el usuario, para abrirlas una por iteración (§0).

| ID | Petición | Estado |
|---|---|---|
| USR-35 | Notificaciones de errores y bugs dentro de la app, con botón «Enviar a técnico» y reporte determinante (traza, `archivo:línea`, versión, SO, cola del log) | Pendiente |
| USR-36 | Diálogo de Contacto con área de texto multilínea para escribir al técnico: motivo (bug/error/sugerencia), email opcional, abrible desde Ayuda y desde la notificación de error | Pendiente |
| USR-37 | Action/servicio que RECIBA los reportes de bug (contrato de datos, almacenamiento y reintento, privacidad) | Pendiente |

Notas de arranque:

- USR-35/USR-36/USR-37 dependen de una decisión que el usuario aún no ha
  tomado: transporte del reporte (issue pre-rellenado en GitHub, `mailto:`
  o endpoint propio con backend). Sin eso solo se pueden hacer la captura y
  el formulario local. `reports/` de la raíz es la salida de gdUnit4, no un
  buzón: los reportes irían a `user://bug_reports/`.
- USR-35: incluir también el manejador de fallos del build de release, no
  solo los `push_error` de depuración.

### Informe técnico de propuestas de mejora (2026-11-21)

Informe aportado por el usuario. Se guarda como backlog de producto; el
texto original termina a media frase («La incorporación») y se cierra abajo
con una línea de resumen. (Su §6 era USR-38: hecho, quitado.)

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

> Relacionado: el core Bézier de
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

#### 7. Conclusión y visión técnica

Estas propuestas buscan ampliar Vectopen más allá de las funcionalidades de
un editor vectorial tradicional.

La incorporación de estas capacidades (esquinas avanzadas, iluminación 2D,
Blend, layout automático, maquetación multipágina y selección por
profundidad) acercaría a Vectopen a un estudio de diseño completo en una
sola app, sin perder el control preciso del objeto ni la salida a imprenta.

> **Prioridad sugerida** (no acordada): 1) esquinas avanzadas, 2) layout,
> 3) Blend, 4) iluminación 2D, 5) maquetación editorial. Cada bloque grande merece su propio documento de
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

---

## 3. Publicación y actualizaciones

- [ ] **[decisión]** Mac Intel: el vectorizador IA no existe (ONNX Runtime no
	  tiene binarios para `x86_64-apple-darwin`): compilarlo desde fuente o
	  avisarlo en la app.
- [ ] **[decisión]** Windows: el paquete es un `.zip`; el botón de actualizar
	  solo lo abre. Un instalador (`.exe`/`.msi`) permitiría actualizar de verdad.
- [ ] **[decisión]** Firmar los binarios de Windows y macOS (avisos de
	  «desarrollador desconocido»; hace falta certificado).

---

## 4. Defectos y pruebas abiertos

| ID | Fallo | Estado |
|---|---|---|
| VAL-66 | Foto vectorizada (1 650 trazados, ~75 000 nodos): 13 s en dibujarse al abrirla. ~15 formas con huecos «pellizcados» cuestan ~0,5 s cada una (la triangulación de Godot falla y se rehace con todos los puntos): otro triangulador (nativo en Rust) o teselar con tolerancia | Abierto |
| VAL-43 | Máscaras anidadas: Godot ignora el recorte interior (`clip_children` no se anida). Hoy `make_mask` lo rechaza; el panel Capas aún permite crearlas. Solución real = recorte geométrico propio | **[decisión]** |
| VAL-56 | Tablas v2: herramienta de tabla con tiradores para redimensionar columnas en el lienzo y panel propio (la v1 está hecha) | Pendiente |
| — | Avisos «leaked at exit» al cerrar las pruebas con `quit()`; comprobar que la app instalada cierra limpia | Abierto |

---

## 5. Criterios de cierre

Los 30 encargos de la Fase B están aprobados (pruebas
`test/e2e/proyecto_NN_e2e.gd`, kit `test/e2e/lib/campaign_kit.gd`). Los
defectos nuevos siguen la numeración desde **VAL-68**. Lista de comprobación
de cada encargo: `docs/archive/PENDIENTE-2026-11-21.md` (§5.2).

- [ ] Cero `VAL-nn` abiertos de severidad alta o media.
- [ ] Suite completa (unitaria + e2e) en verde y sin errores en consola.
