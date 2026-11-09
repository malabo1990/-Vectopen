---
title: "Precisión de editor profesional: texto en trazado, nodos y zoom al 7400 %"
date: 2026-11-09
project: Vectopen
tags: [vectopen, godot, diseño vectorial, código abierto, desarrollo]
---

# Precisión de editor profesional: texto en trazado, nodos y zoom al 7400 %

*Diario de desarrollo de Vectopen · 9 de noviembre de 2026*

Un editor vectorial se juzga por los detalles. Puede tener cien funciones,
pero si un nodo se ve enorme al acercarte, si un clic coge el objeto
equivocado o si un trazo fino se convierte en una mancha gris, la sensación
es de herramienta de juguete. Esta semana nos hemos dedicado justo a eso:
a que Vectopen se comporte con la precisión que espera alguien que viene de
Illustrator o de Affinity Designer.

## Texto en trazado, como debe ser

Vectopen ya sabía poner un texto sobre una curva, pero lo hacía «doblando»
cada letra como si fuera de goma. En un valle, la parte de arriba de las
letras se apretaba; en una cresta, se abría. El resultado: palabras pegadas
al final y separadas al principio.

Ahora cada letra se coloca **rígida**, girada según la curva y apoyada en su
**línea base real**. Este último detalle importa más de lo que parece: el
motor de texto no nos decía dónde está la línea base, y usar el pie de la
caja hacía que una sola «p» levantara todo el texto del trazo. La solución
fue calcularla como la mediana del pie de las letras, de modo que los
descendentes bajan sin arrastrar al resto.

Encima de eso llegaron las herramientas que cualquier diseñador busca:

- **Tiradores en el lienzo**: ▶ donde empieza el texto, ◀ donde termina y ◆
  para deslizarlo por la curva, con deshacer en un solo paso.
- **Espaciado**, **inicio y final**, texto **encima, debajo o centrado** en
  el trazo, **invertir dirección** y **espejo**.
- Los **paneles de tipografía** funcionan también con el texto ya colocado:
  cambias la fuente, la negrita o el color y el trazo se rehace al momento.
- Y si mueves el texto, **su trazado va con él**.

## Nodos que no deforman

Dos detalles pequeños que delatan a un editor poco cuidado:

1. **Los nodos crecían con el zoom.** Los tamaños tenían un mínimo en
   unidades del dibujo; al acercarte mucho, ese mínimo se convertía en
   decenas de píxeles. Ahora todo se mide en píxeles de pantalla: nodos,
   tiradores, la línea roja del tramo y la marca azul tienen siempre el mismo
   tamaño, finos y discretos.
2. **Añadir un nodo cambiaba la curva.** El nodo nuevo nacía con unos
   tiradores inventados. Ahora el tramo se parte con el algoritmo de
   De Casteljau: las dos curvas resultantes son exactamente la original. En
   nuestras pruebas, la forma cambia menos de 0,15 píxeles.

Y algo que faltaba por completo: **deshacer en la edición de nodos**. Mover,
añadir, borrar, cambiar el tipo de nodo o dividir un trazado ya son pasos del
historial.

Los **trazos de pincel** también tienen nodos ahora. Un trazo dibujado a mano
son cientos de muestras; al hacer doble clic, Vectopen le ajusta una curva
Bézier con unos pocos nodos, como haría Illustrator. Al moverlos, el trazo
cambia de forma y conserva su presión: las puntas finas siguen siendo finas.

## Que el clic acierte

En muchos editores sencillos, hacer clic «dentro del recuadro» de un objeto
lo selecciona, aunque no hayas tocado su forma. En una curva en «C», un clic
en el hueco cogía la curva en vez del objeto de debajo. En una imagen con
fondo transparente, cualquier clic en lo transparente la seleccionaba.

Ahora el clic comprueba **la forma**: la línea o el relleno de una curva, lo
pintado de un trazo de pincel, el borde de una figura sin relleno y los
píxeles opacos de una imagen. La selección por arrastre (marquee) sigue la
misma regla. El recuadro, además, abraza exactamente lo que se ve, sin
márgenes fijos.

## Zoom al 7400 %

Acercarse mucho es la mejor lupa para encontrar errores. Con zoom extremo
aparecieron tres:

- **El recuadro se desplazaba.** Godot ajusta la posición de los controles de
  interfaz a unidades enteras. Nuestro recuadro vive dentro del lienzo, así
  que con zoom al 7400 % una unidad son 74 píxeles y la caja saltaba de
  sitio. Un giro de 0,0006° (invisible) basta para que Godot no la redondee.
- **Los bordes salían poligonales.** Una limpieza de puntos pensada para
  evitar bucles diminutos usaba una tolerancia fija que, en figuras
  pequeñas, se comía los lados de las curvas. Ahora nunca supera el 2 % del
  tamaño de la figura.
- **Los trazos finos no adelgazaban.** Por debajo de una unidad se dibujaban
  a una unidad con transparencia, y con zoom alto eso es una banda ancha y
  gris. El mínimo pasa a ser **un píxel de pantalla**, y los campos de grosor
  llegan ahora a **0,005**, con un paso que se adapta al valor.

## Pensando en la tableta

Vectopen se usa mucho con lápiz. Cambiar el tamaño de la interfaz solo con
atajos de teclado no sirve en una tableta sin teclado, así que la pestaña
**Configuración ▸ Ventana** se ha rehecho con botones grandes: − y + para el
tamaño de la interfaz, modo de ventana y tamaños de ventana a un toque.

## Cómo lo comprobamos

Cada fallo de esta lista empezó con una prueba que lo reproducía y terminó
con esa prueba en verde. No son pruebas abstractas: abren Vectopen en una
pantalla de tableta, mueven el ratón como lo haría una persona, hacen
capturas y miden píxeles. Por ejemplo, la prueba del zoom extremo busca los
bordes del recuadro en la imagen y comprueba que cubre el trazo; quitando el
arreglo, la prueba falla con 22 píxeles de desfase. Son nueve pruebas visuales
nuevas, que se suman a las más de 850 de la suite.

## Lo que viene

Seguimos con el motor de trazos (VGSE), la memoria por figura para documentos
de decenas de miles de elementos, y un rediseño del menú contextual y del
inspector del modo Smart, más compacto e inteligente.

Vectopen es software libre (MIT), hecho con Godot. Si lo pruebas y encuentras
algo que no se comporta como esperas, cuéntanoslo: así es como han salido
todas las mejoras de esta semana.
