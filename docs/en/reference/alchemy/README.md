# Alchemy — Reference for Vectopen

> Alchemy is an experimental drawing program created by Karl D.D. Willis and Jacob Hina in Tokyo, Japan, with support from the IPA Exploratory Software Project (Japan). Developed between ~2008-2010. Source code at: https://github.com/karldd/Alchemy

## Philosophy

Alchemy focuses on the **process** of drawing, not the final result. Its canvas intentionally has reduced functionality: no undo, no selection, no editing. The interaction revolves around generating a large quantity of shapes (good, bad, strange, and beautiful) as a starting point to later develop the artwork in other tools.

## Technology Stack

| Aspect | Detail |
|--------|--------|
| Language | Java |
| Graphics API | Java 2D |
| Plugin Framework | Java Plugin Framework (JPF) |
| Tablets | JPen |
| PDF Export | iText |
| PDF Viewer | PDF Renderer |
| SVG Export | Batik |
| Audio Input | Beads (Sound Library) |
| Repository | GitHub: karldd/Alchemy |

## Modular Architecture

Alchemy is built with an interchangeable **module** system that loads at runtime via JPF. There are two types:

### Create Modules
Generate shapes on the canvas. They respond to mouse/pen input (mouseMoved, mousePressed, mouseDragged, mouseReleased).

Included Create module examples:
- **Shapes** — basic free drawing
- **Trace Shapes** — generates shapes based on image tracing
- **Random Shapes** — random shapes as a starting point

### Affect Modules
Modify/transform shapes created by Create modules. They run after the Create module has done its work.

Included Affect module examples:
- **Mirror** — real-time symmetric mirror drawing
- **Randomize** — distorts and scrambles shapes

## Key Features

### Interaction
- **Voice control** — use voice (microphone) to control line width or shape
- **Blind drawing** — turn off the canvas display and explore shapes in the "darkness"
- **Mirror draw** — real-time symmetric drawing
- **Random shapes** — generate random shapes (inspiration for characters, ships, etc.)

### Workflow
- **Session recording** — automatically saves the canvas to PDF at configurable intervals
- **Auto-clear** — clears the canvas automatically after a set time, forcing a fresh start
- **Switch canvas** — automatically opens the sketch in a conventional drawing application (bitmap or vector)
- **Minimal UI** — simple toolbar that magically disappears, fullscreen mode

### Typical Pipeline
1. Sketch in Alchemy (free-form, random, experimental)
2. Export to SVG or bitmap
3. Open in Photoshop/Painter/etc. to develop the final illustration

## Module API

Core classes:
- **AlcCanvas** — the main canvas
- **AlcModule** — base class for all modules
- **AlcShape** — the drawn shapes

Module lifecycle events:
- `setup()` — when the module is activated
- `cleared()` — when the canvas is cleared
- `reselect()` — when the module is reselected

Input:
- `mouseMoved()`, `mousePressed()`, `mouseDragged()`, `mouseReleased()`

Canvas API:
- `canvas.hasCreateShapes()` — checks if shapes are available
- `canvas.getCurrentCreateShape()` — gets the active shape
- `canvas.getCurrentCreateShape().curveTo(p)` — add curve
- `canvas.getCurrentCreateShape().lineTo(p)` — add straight line
- `canvas.getCurrentCreateShape().setLineWidth(w)` — change width
- `canvas.redraw()` — redraw

## Relevance to Vectopen

| Alchemy Concept | Application in Vectopen |
|----------------|------------------------|
| Create/Affect modules | Vectopen's tool system (ToolBase, ToolManager) could adopt a similar separation between creation tools and transformation/effect tools |
| Mirror draw | Implement as a tool or mode that symmetrically mirrors strokes |
| Voice control | Integrate with microphone to control parameters (width, color, opacity) |
| Random shapes / Generative | Tools that generate random variations of existing shapes |
| Blind drawing | Mode that temporarily hides the canvas for "blind" drawing |
| Session recording | Auto-save canvas at intervals (timelapse video or PNG sequence) |
| Auto-clear | Timer to automatically clear the canvas for quick sketching exercises |
| Minimal UI / Fullscreen | Focus mode without distractions (hide panels, toolbar) |
| SVG export pipeline | Vectopen already exports SVG, but could improve round-trip pipeline with other tools |
| Generative processes | Algorithms that alter/distort existing vectors (similar to Affect modules) |
| Module API | Inspiration for a plugin/module system in Vectopen |

## References

- Official site: https://al.chemy.org/
- GitHub: https://github.com/karldd/Alchemy
- Javadocs: http://docs.al.chemy.org/
- FLOSS Manual (offline): http://en.flossmanuals.net/Alchemy/
- Sketches forum: https://al.chemy.org/forum/sketches/
- Video: Andrew Jones live visuals with Alchemy
- Video: Alchemy > ZBrush (alpha masks)
