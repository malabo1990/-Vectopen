# Text on path and precise editing

User guide for the November 2026 improvements: Illustrator / Affinity-style
text on path, node editing, precise selection, extreme zoom and keyboard-free
interface sizing.

---

## 1. Text on path

### Create

1. Type a text (Text tool).
2. Draw the path: a brush stroke, a Bézier curve or a shape.
3. With **Move**, select both (click one, **Shift + click** the other).
4. **Right click ▸ "Text on path"** (Smart, Modern and Pro).

The text stays linked: edit the text or reshape the curve and it re-flows.
To undo it: **right click ▸ "Release text from path"**.

### How letters are placed

Each letter is **rigid** (it does not bend with the curve) and sits on the
curve by its **real baseline**: a "p" or a "g" go below the line without
lifting the rest of the text. On very tight curves letters on the inner side
may touch, as in Illustrator: increase **Spacing** or smooth the curve.

### Settings (Modern and Pro inspector)

| Setting | What it does |
|---|---|
| Text | Changes the content without releasing it from the curve |
| Font size | Size of the source text |
| Spacing | Extra room between letters (% of text height) |
| On the path | Alignment: start, center or end of the range |
| Offset | Moves the text along the curve |
| Starts at / Ends at | Part of the curve the text uses (0–100 %) |
| Position | Above the path (sitting), below (hanging) or centered |
| Reverse direction | Text flips to the other side and reads the other way |
| Mirror | Mirrors the letters |

The **typography panels** (font, bold, italic, size, color, advanced letters)
also work with a text on path selected: they edit the source text and the
stroke is rebuilt.

### On-canvas handles

With the text on path selected (Move tool):

- **▶** marks where the range starts and **◀** where it ends: drag them along the curve.
- **◆** slides the whole text along the curve.

Everything undoes with **Ctrl+Z**. Dragging the text itself moves it
**together with its path**.

---

## 2. Node editing

- Nodes and handles keep **the same on-screen size at any zoom**.
- **Double click** or **click** on a segment adds a node **without changing
  the shape** (the curve is split mathematically, as in Illustrator).
- Every gesture undoes and redoes: moving nodes and handles, **G** (keyboard
  move), adding, deleting, node type, close/open and split.

## 3. Filling self-intersecting outlines

A closed outline that crosses itself fills **all** of its regions (non-zero
rule, as in Illustrator and Affinity). Loops inside other loops stay holes.

## 4. Precise selection

- The **bounding box** hugs what you see (real brush-stroke outline, half the
  curve stroke width), even at thousands of percent of zoom.
- A **click** only grabs what you really touch: a curve's line or fill, the
  painted part of a stroke, the **edge** of an unfilled shape and the
  **opaque** pixels of an image. 4 screen-pixel tolerance.
- Clicking on empty space selects nothing; the **marquee** grabs what it
  touches with its shape.
- You can **drag** an object right after pressing on it, or an already
  selected object from anywhere inside its box.

## 5. Extreme zoom (over 3000 %)

- Small curves and shapes with thick strokes look **smooth**.
- The minimum visible stroke width is **1 screen pixel**: a 0.1 stroke shows
  as a thin opaque line, not as a wide transparent band.
- **Stroke width** fields go down to **0.005**. Wheel and drag use a step
  proportional to the value (≈ 10 % per step), and **Shift + drag** on the box
  changes the width by 1.5 % per pixel, the same at any zoom.

## 6. Interface size without a keyboard (tablet)

**⚙ Settings ▸ Window**:

- **Interface size**: **−** and **+** buttons, list (Automatic, 80–200 %) and
  **Auto**. With a keyboard: Ctrl+Alt+= / Ctrl+Alt+- / Ctrl+Alt+0.
- **Window mode**: Window · Full screen · Borderless.
- **Window size**: 1280×720 · 1600×900 · 1920×1080 · Desktop.
- **Maximize on start**.

---

Guarding tests: `text_on_path_e2e`, `text_path_ui_e2e`,
`node_handles_zoom_e2e`, `node_undo_e2e`, `fill_cross_e2e`, `fill_drag_e2e`,
`select_precision_e2e`, `drag_move_e2e`, `zoom_quality_e2e`,
`settings_ui_e2e` and the unit suite.
