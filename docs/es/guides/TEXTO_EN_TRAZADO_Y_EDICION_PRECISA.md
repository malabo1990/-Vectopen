# Texto en trazado y edición precisa

Guía de uso de las mejoras de noviembre de 2026: texto en trazado al estilo
Illustrator / Affinity, edición de nodos, selección precisa, trabajo con
zoom extremo y tamaño de la interfaz sin teclado.

---

## 1. Texto en trazado

### Crear

1. Escribe un texto (herramienta Texto).
2. Dibuja el camino: un trazo de pincel, una curva Bézier o una figura.
3. Con **Mover**, selecciona los dos (clic en uno y **Mayús + clic** en el otro).
4. **Clic derecho ▸ «Texto en trazado»** (Smart, Modern y Pro).

El texto queda enlazado: si editas el texto o cambias la curva, se recoloca
solo. Para deshacerlo: **clic derecho ▸ «Separar texto del trazado»**.

### Cómo se colocan las letras

Cada letra es **rígida** (no se dobla con la curva) y se apoya en la curva por
su **línea base real**: una «p» o una «g» bajan de la línea sin levantar el
resto del texto. En curvas muy cerradas, las letras del lado interior pueden
tocarse, igual que en Illustrator: se corrige con **Espaciado** o suavizando
la curva.

### Ajustes (inspector de Modern y Pro)

| Ajuste | Qué hace |
|---|---|
| Texto | Cambia el contenido sin separar el texto de la curva |
| Tamaño de letra | Tamaño del texto de origen |
| Espaciado | Aire extra entre letras (en % del alto del texto) |
| En el trazado | Alineación: inicio, centro o final del tramo |
| Desplazamiento | Mueve el texto a lo largo de la curva |
| Empieza en / Termina en | Tramo de la curva que ocupa el texto (0–100 %) |
| Posición | Encima del trazo (apoyado), debajo (colgando) o centrado |
| Invertir dirección | El texto pasa al otro lado y se lee en sentido contrario |
| Espejo | Refleja las letras |

Los **paneles de tipografía** (fuente, negrita, cursiva, tamaño, color, letras
avanzadas) también funcionan con el texto en trazado seleccionado: editan el
texto de origen y el trazo se rehace.

### Tiradores en el lienzo

Con el texto en trazado seleccionado (herramienta Mover):

- **▶** marca dónde empieza el tramo y **◀** dónde termina: arrástralos por la curva.
- **◆** desliza el texto entero por la curva.

Todo se deshace con **Ctrl+Z**. Arrastrar el texto en sí lo mueve **junto con
su trazado**.

---

## 2. Edición de nodos

- Nodos y tiradores se ven **del mismo tamaño a cualquier zoom**.
- **Doble clic** o **clic** en un tramo añade un nodo **sin cambiar la forma**
  (la curva se parte matemáticamente, como en Illustrator).
- Todo gesto se deshace y rehace: mover nodos y tiradores, **G** (mover con
  teclado), añadir, borrar, tipo de nodo, cerrar/abrir y dividir.

## 3. Relleno de contornos que se cruzan

Un contorno cerrado que se cruza consigo mismo rellena **todas** sus zonas
(regla «no cero», la de Illustrator y Affinity). Los lazos dentro de otros
siguen siendo huecos.

## 4. Selección precisa

- El **recuadro** abraza lo que se ve (contorno real del trazo de pincel, medio
  grosor de las curvas), también con zoom de miles de por ciento.
- Un **clic** solo coge lo que tocas de verdad: la línea o el relleno de una
  curva, lo pintado de un trazo, el **borde** de una figura sin relleno y lo
  **opaco** de una imagen. Margen de 4 px de pantalla.
- Un clic en vacío no selecciona nada; el **marquee** coge lo que toca con su forma.
- Puedes **arrastrar** un objeto nada más pulsarlo, o un objeto ya
  seleccionado desde cualquier punto de su recuadro.

## 5. Zoom extremo (más de 3000 %)

- Las curvas y figuras pequeñas con borde grueso se ven **lisas**.
- El grosor mínimo visible es **1 píxel de pantalla**: un trazo de 0,1 se ve
  como una línea fina y opaca, no como una banda ancha transparente.
- Los campos de **grosor** llegan a **0,005**. La rueda y el arrastre usan un
  paso proporcional al valor (≈ 10 % por paso), y **Mayús + arrastrar** sobre
  el recuadro cambia el grosor un 1,5 % por píxel, igual a cualquier zoom.

## 6. Tamaño de la interfaz sin teclado (tableta)

**⚙ Configuración ▸ Ventana**:

- **Tamaño de la interfaz**: botones **−** y **+**, lista (Automático,
  80–200 %) y **Auto**. Con teclado: Ctrl+Alt+= / Ctrl+Alt+- / Ctrl+Alt+0.
- **Modo de ventana**: Ventana · Pantalla completa · Sin bordes.
- **Tamaño de ventana**: 1280×720 · 1600×900 · 1920×1080 · Escritorio.
- **Maximizar al iniciar**.

---

Pruebas que lo vigilan: `text_on_path_e2e`, `text_path_ui_e2e`,
`node_handles_zoom_e2e`, `node_undo_e2e`, `fill_cross_e2e`, `fill_drag_e2e`,
`select_precision_e2e`, `drag_move_e2e`, `zoom_quality_e2e`,
`settings_ui_e2e` y la suite unitaria.
