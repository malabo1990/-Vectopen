# Alchemy — Referencia para Vectopen

> Alchemy es un programa experimental de dibujo creado por Karl D.D. Willis y Jacob Hina en Tokio, Japón, con el apoyo del Exploratory Software Project de IPA (Japón). Desarrollado entre ~2008-2010. Código fuente en: https://github.com/karldd/Alchemy

## Filosofía

Alchemy se enfoca en el **proceso** de dibujar, no en el resultado final. Su canvas tiene intencionalmente funcionalidad reducida: sin undo, sin selección, sin edición. La interacción se centra en generar una gran cantidad de formas (buenas, malas, extrañas y hermosas) como punto de partida para luego desarrollar la obra en otras herramientas.

## Stack Tecnológico

| Aspecto | Detalle |
|---------|---------|
| Lenguaje | Java |
| API gráfica | Java 2D |
| Plugin framework | Java Plugin Framework (JPF) |
| Tablets | JPen |
| Export PDF | iText |
| Vista PDF | PDF Renderer |
| Export SVG | Batik |
| Input de audio | Beads (Sound Library) |
| Repositorio | GitHub: karldd/Alchemy |

## Arquitectura Modular

Alchemy está construido con un sistema de **módulos** intercambiables que se cargan en tiempo de ejecución vía JPF. Hay dos tipos:

### Create Modules
Generan formas en el canvas. Responden a input del mouse/pen (mouseMoved, mousePressed, mouseDragged, mouseReleased).

Ejemplos de módulos Create incluidos:
- **Shapes** — dibujo libre básico
- **Trace Shapes** — genera formas basadas en追溯 (tracing) de imágenes
- **Random Shapes** — formas aleatorias como punto de partida

### Affect Modules
Modifican/transforman las formas creadas por los Create modules. Se ejecutan después de que el Create module ha hecho su trabajo.

Ejemplos de módulos Affect incluidos:
- **Mirror** — dibujo simétrico con espejo en tiempo real
- **Randomize** — distorsiona y desordena formas

## Características Clave

### Interacción
- **Voice control** — usar la voz (micrófono) para controlar el ancho de línea o la forma
- **Blind drawing** — apagar el display del canvas y explorar formas en la "oscuridad"
- **Mirror draw** — dibujo simétrico en tiempo real
- **Random shapes** — generar formas aleatorias (inspiración para personajes, naves, etc.)

### Flujo de Trabajo
- **Session recording** — guarda automáticamente el canvas a PDF en intervalos configurables
- **Auto-clear** — limpia el canvas automáticamente cada cierto tiempo, forzando a empezar de nuevo
- **Switch canvas** — abre automáticamente el sketch en una aplicación de dibujo convencional (bitmap o vector)
- **Minimal UI** — toolbar simple que desaparece mágicamente, modo fullscreen

### Pipeline típico
1. Sketch en Alchemy (forma libre, aleatoria, experimental)
2. Exportar a SVG o bitmap
3. Abrir en Photoshop/Painter/etc. para desarrollar la ilustración final

## API para Módulos

Clases principales del core:
- **AlcCanvas** — el canvas principal
- **AlcModule** — clase base para todos los módulos
- **AlcShape** — las formas dibujadas

Eventos del ciclo de vida del módulo:
- `setup()` — al activar el módulo
- `cleared()` — cuando el canvas se limpia
- `reselect()` — cuando se vuelve a seleccionar el módulo

Input:
- `mouseMoved()`, `mousePressed()`, `mouseDragged()`, `mouseReleased()`

API del canvas:
- `canvas.hasCreateShapes()` — verifica si hay formas disponibles
- `canvas.getCurrentCreateShape()` — obtiene la forma activa
- `canvas.getCurrentCreateShape().curveTo(p)` — añadir curva
- `canvas.getCurrentCreateShape().lineTo(p)` — añadir línea recta
- `canvas.getCurrentCreateShape().setLineWidth(w)` — cambiar grosor
- `canvas.redraw()` — redibujar

## Lo Relevante para Vectopen

| Concepto Alchemy | Aplicación en Vectopen |
|-----------------|------------------------|
| Create/Affect modules | El sistema de herramientas de Vectopen (ToolBase, ToolManager) podría adoptar una separación similar entre herramientas de creación y herramientas de transformación/efectos |
| Mirror draw | Implementar como herramienta o modo que refleje simétricamente los trazos |
| Voice control | Integrar con micrófono para controlar parámetros (grosor, color, opacidad) |
| Random shapes / Generative | Herramientas que generen variaciones aleatorias de formas existentes |
| Blind drawing | Modo que oculte temporalmente el canvas para dibujar "a ciegas" |
| Session recording | Auto-guardado del canvas a intervalos (video timelapse o PNG sequence) |
| Auto-clear | Temporizador que limpie el canvas automáticamente para ejercicios de sketching rápido |
| Minimal UI / Fullscreen | Modo de enfoque sin distracciones (ocultar paneles, toolbar) |
| SVG export pipeline | Vectopen ya exporta SVG, pero podría mejorar el pipeline de ida y vuelta con otras herramientas |
| Procesos generativos | Algoritmos que alteren/distorsionen vectores existentes (similar a Affect modules) |
| API de módulos | Inspiración para un sistema de plugins/módulos en Vectopen |

## Referencias

- Sitio oficial: https://al.chemy.org/
- GitHub: https://github.com/karldd/Alchemy
- Javadocs: http://docs.al.chemy.org/
- Manual FLOSS (caído): http://en.flossmanuals.net/Alchemy/
- Foro de sketches: https://al.chemy.org/forum/sketches/
- Video: Andrew Jones live visuals con Alchemy
- Video: Alchemy > ZBrush (alpha masks)
