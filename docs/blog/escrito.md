---
title: "Vectopen 0.2.3-beta: pincel vectorial nuevo, texto en trazado, edición precisa y documentos de 10 000 elementos"
date: 2026-11-09
project: Vectopen
tags: [vectopen, godot, diseño vectorial, código abierto, versión 0.2.3-beta]
---

# Vectopen 0.2.3-beta: pincel vectorial nuevo, texto en trazado, edición precisa y documentos de 10 000 elementos

*Diario de desarrollo de Vectopen · 9 de noviembre de 2026 ·
[leer en la web](https://malabo1990.github.io/vectopen-web/blog/post.html?p=2026-11-vectopen-0-2-3-beta)*

La [0.2.2-beta](https://malabo1990.github.io/vectopen-web/blog/post.html?p=2026-11-vectopen-0-2-2-beta) salió el 3 de
noviembre. En los seis días siguientes han entrado **64 cambios**,
casi todos alrededor de tres ideas: un **pincel vectorial** de verdad, un
**texto en trazado** como el de Illustrator o Affinity y la **precisión y
velocidad** que se esperan de un editor profesional, también con documentos
enormes. El resultado es **0.2.3-beta**.

**[Descargar 0.2.3-beta &rarr;](https://github.com/malabo1990/-Vectopen/releases/tag/v0.2.3-beta)**
&nbsp;Windows (.zip) · macOS universal (.dmg / .zip) · Linux (.deb, .rpm, .tar.gz) · Android (.apk, vista previa)

[![Vectopen en 30 segundos (vídeo)](https://malabo1990.github.io/vectopen-web/media/video/vectopen-promo-poster.webp)](https://malabo1990.github.io/vectopen-web/media/video/vectopen-promo-30s.mp4)

*▶ Vídeo de 30 segundos: [verlo](https://malabo1990.github.io/vectopen-web/media/video/vectopen-promo-30s.mp4)*

Quien ya tenga la 0.2.2 instalada verá el aviso de versión nueva en la
ventana del logo y podrá instalarla con un clic.

## 1. Un motor de pincel nuevo (VGSE)

El pincel se ha rehecho por fases con un motor propio, el *Vectopen Geometric
Stroke Engine*. Cada trazo sigue siendo vectorial: se puede editar, mover,
escalar y exportar sin perder calidad.

- **Lápiz como el de Krita**, con durezas de 2H a 8B, grano del papel y sin
  cuñas en los giros cerrados. La presión del lápiz de la tableta cambia el
  grosor y la oscuridad.
- **Rotulador, aerógrafo por sellos y caligráfico**, todos con antialias y sin
  manchas donde el trazo se cruza consigo mismo.
- **El trazo va exactamente donde pones el lápiz**, también con mucho zoom, y
  no cambia al soltar. El grosor es tuyo: cambiar de estilo ya no lo altera.

![Las durezas del lápiz, de 2H a 8B](https://malabo1990.github.io/vectopen-web/media/shots/023_lapiz_durezas.webp)

![Garabatos rápidos con el lápiz: sin cuñas ni pinchos](https://malabo1990.github.io/vectopen-web/media/shots/023_lapiz_garabatos.webp)

![El estilo caligráfico](https://malabo1990.github.io/vectopen-web/media/shots/023_caligrafico.webp)

- **Pincel de figuras y de patrón.** Estampa figuras a lo largo del trazo o
  las dobla siguiendo la curva. Con «Selección» se usan como pincel las
  figuras, grupos o curvas que tengas seleccionadas (por ejemplo, un polígono
  propio).
- **Texturas dentro del trazo** (también desde una imagen tuya), **variación
  de color** a lo largo del trazo y **efectos geométricos**: ondulado, zigzag
  y rugoso.
- **«Mis pinceles»**: guarda tus ajustes favoritos y vuelve a ellos.
- **Editar los nodos de un trazo de pincel** con doble clic: se convierte en
  una curva con pocos nodos y conserva la presión.
- La malla del trazo se calcula en Rust: **hasta 28 veces más rápida**.

![Pincel de figuras: estrellas, círculos y figuras propias a lo largo del trazo](https://malabo1990.github.io/vectopen-web/media/shots/023_pincel_figuras.webp)

![Un trazo de pincel editado por sus nodos](https://malabo1990.github.io/vectopen-web/media/shots/023_pincel_nodos.webp)

## 2. Texto en trazado

Clic derecho sobre un texto y una curva ▸ **«Texto en trazado»**, en los tres
modos (Smart, Modern y Pro). El texto queda enlazado a su trazado: si mueves o
editas la curva, el texto la sigue.

- **Letras rígidas apoyadas en su línea base real**, como en Illustrator o
  Affinity: no se deforman con la curva y quedan igual de separadas al
  principio y al final.
- **Tiradores en el lienzo**: ▶ marca dónde empieza, ◀ dónde termina y ◆
  desliza el texto a lo largo de la curva.
- **Encima, debajo o centrado**, **invertir la dirección** y **espejo**.
- Todos los paneles de texto (fuente, peso, tamaño, color, espaciado, letras
  avanzadas) siguen funcionando con el texto ya colocado.

![Etiqueta de café: texto encima del círculo y, debajo, invertido](https://malabo1990.github.io/vectopen-web/media/shots/023_etiqueta_cafe.webp)

![Tiradores de inicio, final y desplazamiento](https://malabo1990.github.io/vectopen-web/media/shots/023_texto_tiradores.webp)

![El mismo texto por debajo de la curva](https://malabo1990.github.io/vectopen-web/media/shots/023_texto_debajo.webp)

## 3. Edición precisa, como en un editor profesional

- **Nodos y tiradores del mismo tamaño a cualquier zoom**, con línea roja
  fina y marcas azules cortas, al estilo de Affinity.
- **Historial completo al editar nodos**: cada movimiento se deshace con
  Ctrl+Z.
- **Añadir un nodo ya no deforma la curva** (se divide con el método de De
  Casteljau).
- **Rellenos correctos en contornos que se cruzan** (regla «no cero»), sin
  parpadeos ni errores en el depurador.
- **Selección por la forma real**, no por el recuadro ni por la transparencia
  de las imágenes: curvas, trazos finos, figuras sin relleno. El recuadro de
  selección es exacto también al 7400 % de zoom, y arrastrar funciona siempre.
- **Zoom extremo, hasta unos 190 000 %**: bordes lisos, trazos finos de verdad
  (no transparentes), grosores desde **0,005**, decimales en todos los campos
  y tiradores nítidos. Mayús + arrastrar cambia el grosor en cualquier figura.

![Nodos del mismo tamaño con el zoom al 2000 %](https://malabo1990.github.io/vectopen-web/media/shots/023_nodos_zoom.webp)

![Relleno correcto de un contorno que se cruza consigo mismo](https://malabo1990.github.io/vectopen-web/media/shots/023_relleno_cruzado.webp)

![Figuras y trazos al 6000 %: bordes lisos](https://malabo1990.github.io/vectopen-web/media/shots/023_zoom_6000.webp)

## 4. Rendimiento: 10 000 elementos fluidos, y vamos a por 50 000

Para medirlo de verdad montamos un «muro de marca» con figuras, curvas,
textos, trazos de pincel, pinceles de figuras, máscaras y textos en trazado,
con 3 000, 10 000 y 50 000 elementos. Con 10 000 elementos mezclados:

| | 0.2.2-beta | 0.2.3-beta |
|---|---|---|
| Abrir el documento | 25 s | 2,4 s |
| Todo a la vista | 21 fps | 45–53 fps |
| Arrastrar la selección completa | se bloqueaba (40 s por paso) | 38 ms por paso |
| Resaltado al pasar el ratón | 50 ms | 0,06 ms |
| Crear por script | 85 s | 11,6 s |
| Panel Capas con miles de capas | se congelaba | por tandas, fluido |

![El muro de 10 000 elementos exportado](https://malabo1990.github.io/vectopen-web/media/shots/023_muro_10000.webp)

Con **50 000 elementos** en un PC modesto Vectopen ya funciona (guarda en
2,5 s, exporta SVG en 4,3 s), pero todavía va lento y usa unos 3 GB. **Ese es
ahora el objetivo principal**: rendimiento muy alto con 50 000 elementos, con
algoritmos nuevos para dibujar, guardar en memoria y seleccionar.

## 5. Menos memoria

- Al arrancar, los paneles de los modos que no usas (el inspector de Modern,
  el lateral de Pro) y el panel de teclado y ratón **se crean al abrirlos**:
  la mitad de elementos de interfaz al empezar. En el ordenador, de 792 a
  702 MB; en Android, de 374 a 279 MB.
- El panel Capas crea sus filas **por tandas de 200** también al ir añadiendo
  figuras: antes cada figura añadía una fila (~10 KB) aunque no se viera.
- Probamos el renderizador OpenGL en el escritorio: ahorraba 170 MB más, pero
  con 10 000 elementos bajaba de 49 a 20 fps. Se queda Vulkan.

## 6. Cinco campañas publicitarias como pruebas

Además de las pruebas habituales (ya son más de 860 pruebas unitarias y unas
130 que manejan la interfaz como una persona), esta versión se ha probado con
**cinco campañas completas, como las haría una agencia**. Cada una crea sus
mesas de trabajo con Bézier, polígonos, máscaras, pinceles, pinceles de
figuras hechos con una figura seleccionada y texto en trazado; la organiza
en capas y grupos; la exporta a SVG, PDF, EPS, PNG, JPEG, WEBP y VOP; la
vuelve a importar y comprueba que no se pierde nada al guardar y reabrir.

![Campaña 1: cartel de festival](https://malabo1990.github.io/vectopen-web/media/shots/023_cartel_festival.webp)

![Campaña 2: zapatilla para Instagram](https://malabo1990.github.io/vectopen-web/media/shots/023_zapatilla_ig.webp)

![Campaña 4: valla de una promoción inmobiliaria, con unas 1000 figuras](https://malabo1990.github.io/vectopen-web/media/shots/023_valla_bahia.webp)

![El festival reabierto en Vectopen, con sus tres mesas](https://malabo1990.github.io/vectopen-web/media/shots/023_festival_reabierto.webp)

Las campañas destaparon trece fallos, todos corregidos. Entre ellos: SVG, PDF
y EPS salían **sin los trazos de pincel**, arrastrar una selección de 10 000
elementos tardaba 40 s por paso y exportar a PNG una mesa enorme fallaba (ahora
reduce la escala lo justo y avisa).

## 7. Exportar e importar

- **SVG, PDF y EPS incluyen los trazos de pincel**, los pinceles de figuras y
  el texto en trazado con su forma real.
- Abrir archivos con contornos importados muy detallados es **hasta 40 veces
  más rápido**, y lo exportado ya no lleva puntos repetidos.
- PNG, JPEG y WEBP de mesas mayores de 16 384 px reducen la escala y avisan.

## 8. Interfaz

- **Tamaño de la interfaz** automático para monitores 4K, tabletas y
  pantallas pequeñas, y manual en **Configuración ▸ Ventana** con botones
  grandes, pensados para usar la tableta sin teclado (también Ctrl+Alt+= / −).
- **Diálogo «Cambios sin guardar»** sobrio y accesible.
- **Panel Teclado y ratón** con un teclado simulado que muestra qué teclas
  están libres, asignadas o en conflicto.
- Abrir archivos con doble clic, guardado automático y 1000 pasos de deshacer.

![Configuración ▸ Ventana, para usar sin teclado](https://malabo1990.github.io/vectopen-web/media/shots/023_ajustes_tableta.webp)

![Diálogo de cambios sin guardar, en tema oscuro](https://malabo1990.github.io/vectopen-web/media/shots/023_dialogo_salir.webp)

## 9. Plataformas

- **Windows 10 / 11**, **Linux** (.deb, .rpm, .tar.gz) y **macOS universal**.
  En Mac Intel funciona ahora **desde macOS 10.13** (antes 10.15); en Apple
  Silicon, desde macOS 11. Más antiguo no es posible: el propio Godot 4.7 pide
  10.13.
- **Android (vista previa experimental).** Vectopen arranca y funciona en
  Android, con la interfaz a un tamaño legible en pantallas densas. **La
  interfaz todavía no está diseñada para tabletas ni para el tacto**: es para
  quien quiera curiosear. El diseño para Android y tabletas llegará más
  adelante.
- iPhone / iPad: de momento no, porque exige compilar en un Mac.

![Vectopen en Android (vista previa)](https://malabo1990.github.io/vectopen-web/media/shots/023_android.webp)

## 10. Lo que viene

1. **Rendimiento ultra alto con 50 000 elementos**, con algoritmos nuevos.
2. Interfaz para **tabletas y Android**.
3. **Vectopen Web**: una versión que funcione en el navegador, sin instalar
   nada.
4. Un menú contextual y un inspector nuevos en Smart, más compactos.
5. Menos memoria por texto (ahora unos 35 KB cada uno).

## Apoya Vectopen

Vectopen lo hace una sola persona, sin empresa detrás, sin cuentas, sin
telemetría y sin versión de pago. **Las donaciones me permiten dedicarle más
horas** y llegar antes a lo que viene: **Vectopen Web** en el navegador, el
rendimiento con 50 000 elementos y la interfaz para tabletas.

**[Apoyar en GitHub Sponsors &rarr;](https://github.com/sponsors/malabo1990)**
&nbsp;(mensual o puntual)

Si no puedes donar, ayuda igual poner una estrella al
[repositorio](https://github.com/malabo1990/-Vectopen), probar la beta y
contar lo que falle: buena parte de esta versión salió de esos avisos.

## Todos los cambios, uno por uno

Para quien quiera leer el código: la comparación completa entre versiones
está en
**[v0.2.2-beta…v0.2.3-beta](https://github.com/malabo1990/-Vectopen/compare/v0.2.2-beta...v0.2.3-beta)**,
y aquí tienes cada cambio con su enlace:

**3 de noviembre** (13 cambios)

- [`ed44682`](https://github.com/malabo1990/-Vectopen/commit/ed44682) Ventana del logo: X (@malabo_6) en Comunidad, botones en cuadrícula 2 × 2
- [`c2ea826`](https://github.com/malabo1990/-Vectopen/commit/c2ea826) Smart: sin iconos Shader/Script/Vectorizar/Complementos repetidos en la barra de abajo (ya están en la ventana Efectos)
- [`c905ecc`](https://github.com/malabo1990/-Vectopen/commit/c905ecc) Duplicar textos y párrafos (Alt + arrastrar, Ctrl+D, pegar): la copia se ve igual; Alt + arrastrar es un solo paso de deshacer
- [`014f86f`](https://github.com/malabo1990/-Vectopen/commit/014f86f) PENDIENTE: tanda del usuario USR-01…06
- [`d886c0e`](https://github.com/malabo1990/-Vectopen/commit/d886c0e) Panel Teclado y ratón: pestañas, teclado simulado y gestos del ratón (USR-03/04)
- [`c996e1b`](https://github.com/malabo1990/-Vectopen/commit/c996e1b) Pincel: borde con antialias, opacidad sin manchas y vista previa de calidad (USR-05)
- [`26c4a03`](https://github.com/malabo1990/-Vectopen/commit/26c4a03) VGSE fase 1: convertir trazo en contorno + plan por fases (USR-06)
- [`bdaf97c`](https://github.com/malabo1990/-Vectopen/commit/bdaf97c) Abrir con doble clic, guardado automático, aviso al salir y 1000 pasos de deshacer (USR-07/10/11/12)
- [`4baf9fe`](https://github.com/malabo1990/-Vectopen/commit/4baf9fe) Pincel: lápiz, rotulador, aerógrafo y caligráfico con el render de calidad (USR-08)
- [`823c30a`](https://github.com/malabo1990/-Vectopen/commit/823c30a) Panel Pincel compacto, sin deslizadores y siempre dentro de la ventana (USR-09)
- [`823d1e7`](https://github.com/malabo1990/-Vectopen/commit/823d1e7) Menú contextual: el botón Tema ya no congela; trazos sin rayos a mucho zoom
- [`7e862c5`](https://github.com/malabo1990/-Vectopen/commit/7e862c5) Aerógrafo: inicio y final suaves, presión = flujo; trazo 6× más rápido de dibujar
- [`6e26eca`](https://github.com/malabo1990/-Vectopen/commit/6e26eca) Pincel con lápiz real: sin pinchos ni aletas; aerógrafo por sellos; el estilo se guarda

**8 de noviembre** (16 cambios)

- [`edd6bd4`](https://github.com/malabo1990/-Vectopen/commit/edd6bd4) Lápiz con durezas (2H…8B) y el trazo ya no cambia al soltar
- [`98aeae9`](https://github.com/malabo1990/-Vectopen/commit/98aeae9) Selector de color en tiempo real: 60 fps al arrastrar, un solo deshacer
- [`83476f5`](https://github.com/malabo1990/-Vectopen/commit/83476f5) VGSE fase 1: la presión se reparte sobre el trazado ajustado
- [`7034c4b`](https://github.com/malabo1990/-Vectopen/commit/7034c4b) VGSE fase 1: geometría del trazo en caché; la pintura solo repinta
- [`60dc641`](https://github.com/malabo1990/-Vectopen/commit/60dc641) Lápiz más natural (como Krita): borde que se deshace en grano
- [`bade73c`](https://github.com/malabo1990/-Vectopen/commit/bade73c) Lápiz: el centro deja ver el grano del papel aunque se apriete
- [`d4502dc`](https://github.com/malabo1990/-Vectopen/commit/d4502dc) Lápiz como el de Krita: sólido, borde fino, sin cuñas en giros cerrados
- [`4b50933`](https://github.com/malabo1990/-Vectopen/commit/4b50933) Pincel: el trazo va exactamente donde se pone el lápiz, también con zoom
- [`1400595`](https://github.com/malabo1990/-Vectopen/commit/1400595) Prueba e2e: todos los estilos del pincel con zoom 8× (curva, zigzag, garabato)
- [`127f7ba`](https://github.com/malabo1990/-Vectopen/commit/127f7ba) Pincel con zoom extremo (~5000 %): aerógrafo continuo, grano fino, muestras por px
- [`2de93f9`](https://github.com/malabo1990/-Vectopen/commit/2de93f9) Malla del trazo de pincel en Rust (vectopen_io): 28× más rápida
- [`e57cfbd`](https://github.com/malabo1990/-Vectopen/commit/e57cfbd) Pincel: el grosor es del usuario; cambiar de estilo ya no lo cambia
- [`3df6e0e`](https://github.com/malabo1990/-Vectopen/commit/3df6e0e) test/run_e2e.sh: pruebas con ventana sin tocar los ajustes del usuario
- [`11dd924`](https://github.com/malabo1990/-Vectopen/commit/11dd924) VGSE fase 2: pincel de OBJETO (estampa figuras a lo largo del trazo)
- [`8634389`](https://github.com/malabo1990/-Vectopen/commit/8634389) VGSE fase 2: pincel de PATRÓN (se dobla con la curva) y trazo → figuras
- [`8b85c97`](https://github.com/malabo1990/-Vectopen/commit/8b85c97) PENDIENTE: estado de la fase 2 del VGSE

**9 de noviembre** (35 cambios)

- [`52caa27`](https://github.com/malabo1990/-Vectopen/commit/52caa27) Pincel de objeto: «Selección» funciona con el flujo real y con todo objeto
- [`287ad17`](https://github.com/malabo1990/-Vectopen/commit/287ad17) Pincel de objeto: reponer _normalize_all (se borró al reescribir «Selección»)
- [`ff2169f`](https://github.com/malabo1990/-Vectopen/commit/ff2169f) Panel Pincel más claro: secciones en tarjetas con título
- [`fe83fe4`](https://github.com/malabo1990/-Vectopen/commit/fe83fe4) VGSE fase 3: texto como pincel y TEXTO EN TRAZADO enlazado
- [`d93e786`](https://github.com/malabo1990/-Vectopen/commit/d93e786) Diálogo «Cambios sin guardar» con el estilo de la app, sobrio y accesible
- [`133477a`](https://github.com/malabo1990/-Vectopen/commit/133477a) Rendimiento: el panel de Capas ya no congela la app con miles de capas
- [`e6494af`](https://github.com/malabo1990/-Vectopen/commit/e6494af) Benchmark: recuento igual antes de guardar y tras cargar (sin pérdida de datos)
- [`9a13c63`](https://github.com/malabo1990/-Vectopen/commit/9a13c63) Tamaño de la interfaz: automático para 4K y pantallas pequeñas, Ajustes y atajos
- [`bbde60a`](https://github.com/malabo1990/-Vectopen/commit/bbde60a) Memoria: el editor en línea de cada texto se crea al editar, no al cargar
- [`de4ec25`](https://github.com/malabo1990/-Vectopen/commit/de4ec25) Rendimiento al dibujar: 10 000 elementos visibles de 21 a 52 fps
- [`02cad19`](https://github.com/malabo1990/-Vectopen/commit/02cad19) Rendimiento: el inspector ya no lee miles de objetos al seleccionar
- [`9ce6985`](https://github.com/malabo1990/-Vectopen/commit/9ce6985) Texto en trazado: alinear, desplazar y dar la vuelta desde el inspector
- [`58e0642`](https://github.com/malabo1990/-Vectopen/commit/58e0642) VGSE fase 4: texturas dentro de los trazos de pincel
- [`e90204c`](https://github.com/malabo1990/-Vectopen/commit/e90204c) VGSE fase 5: efectos geométricos en trazos de pincel (ondulado, zigzag, rugoso)
- [`775abd0`](https://github.com/malabo1990/-Vectopen/commit/775abd0) VGSE fase 6: benchmark de trazos y aerógrafo en Rust (51 → 17 ms con 10 000)
- [`e239f15`](https://github.com/malabo1990/-Vectopen/commit/e239f15) VGSE fase 6: «Mis pinceles» y prueba de compatibilidad de trazos antiguos
- [`d9cd9ad`](https://github.com/malabo1990/-Vectopen/commit/d9cd9ad) Lápiz más rápido: opacidad por vértice en Rust y en la caché de geometría
- [`610a396`](https://github.com/malabo1990/-Vectopen/commit/610a396) VGSE fase 4: variación de color a lo largo del trazo de pincel
- [`e9a8f7e`](https://github.com/malabo1990/-Vectopen/commit/e9a8f7e) VGSE fase 4: textura del trazo desde una imagen del usuario
- [`7f38a03`](https://github.com/malabo1990/-Vectopen/commit/7f38a03) Rendimiento: mover miles de figuras seleccionadas sin atascos
- [`4d99afb`](https://github.com/malabo1990/-Vectopen/commit/4d99afb) PENDIENTE: estado de la memoria por figura tras la tanda nocturna
- [`84a2650`](https://github.com/malabo1990/-Vectopen/commit/84a2650) Texto en trazado: letras rígidas, tiradores y paneles de texto
- [`3c92d44`](https://github.com/malabo1990/-Vectopen/commit/3c92d44) Configuración ▸ Ventana pensada para tableta (sin teclado)
- [`f488564`](https://github.com/malabo1990/-Vectopen/commit/f488564) Nodos: tamaño fijo con zoom, historial, nodo nuevo sin deformar y relleno
- [`8bf358f`](https://github.com/malabo1990/-Vectopen/commit/8bf358f) Selección precisa y arrastre fiable
- [`f68e88f`](https://github.com/malabo1990/-Vectopen/commit/f68e88f) Zoom extremo: bordes lisos, trazos finos de verdad y grosor hasta 0,005
- [`bd48388`](https://github.com/malabo1990/-Vectopen/commit/bd48388) Docs: guía de texto en trazado y edición precisa, artículo del blog
- [`673e374`](https://github.com/malabo1990/-Vectopen/commit/673e374) Nodos en trazos de pincel y zoom extremo en la interfaz
- [`306bf1a`](https://github.com/malabo1990/-Vectopen/commit/306bf1a) Campañas 31–33 y tres fallos que han destapado
- [`6409cb6`](https://github.com/malabo1990/-Vectopen/commit/6409cb6) Rendimiento con 10 000 elementos: arrastre, ratón, crear y abrir
- [`a02cd72`](https://github.com/malabo1990/-Vectopen/commit/a02cd72) Exportar raster enorme ajusta la escala; pool de recuadros sin referencias muertas
- [`df3eb7e`](https://github.com/malabo1990/-Vectopen/commit/df3eb7e) Versión 0.2.3-beta
- [`fb0fce5`](https://github.com/malabo1990/-Vectopen/commit/fb0fce5) Android, macOS 10.13 y menos memoria al arrancar
- [`3c8945b`](https://github.com/malabo1990/-Vectopen/commit/3c8945b) Librerías nativas para Windows y macOS desde Linux (rust/build_cross.sh)
- [`c3510a8`](https://github.com/malabo1990/-Vectopen/commit/c3510a8) Aviso de versión nueva en Android (APK); notas de la 0.2.3-beta; la release avisa a la web


Gracias por probar Vectopen. Si algo falla, cuéntalo en
[GitHub](https://github.com/malabo1990/-Vectopen/issues),
[Reddit](https://www.reddit.com/r/Vectopen_editor/) o
[Telegram](https://t.me/vectopen).
