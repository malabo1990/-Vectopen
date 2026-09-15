# Vectopen Professional UI — Concepto, Mecánica y Studio (Affinity & InDesign Style)

> 2026-09-15 · Especificación de arquitectura, diseño de interacción y componentes para el modo Profesional.  
> Referencia conceptual: **Affinity Designer / Publisher** e **InDesign**, adaptados a la identidad y motor reactivo de **Vectopen**.

---

# PARTE I — Filosofía Profesional y Affinity Studio

## 1. Objetivo

El modo **Professional** de Vectopen debe sentirse como una mesa de trabajo profesional de diseño vectorial y maquetación, no como una versión ampliada del Modern UI.

La filosofía es:

> **Más información visible, más precisión, menos ocultación y acceso directo a las propiedades avanzadas.**

El usuario profesional debe poder modificar un objeto sin tener que abrir continuamente submenús.

---

## 2. Estructura General del Studio

```text
┌──────────────────────────────────────────────────────────────┐
│ Top Bar / Menú Principal                                     │
├──────┬───────────────────────────────────────────────┬───────┤
│      │                                               │       │
│ Tool │                    CANVAS                     │ Studio│
│ Bar  │                                               │ Right │
│      │                                               │       │
│      │                                               │       │
│      │                                               ├───────┤
│      │                                               │ Layers│
│      │                                               ├───────┤
│      │                                               │Transform
│      │                                               ├───────┤
│      │                                               │ Colour│
│      │                                               ├───────┤
│      │                                               │Stroke │
│      │                                               ├───────┤
│      │                                               │Public.│
│      │                                               └───────┘
└──────┴───────────────────────────────────────────────┴───────┘
```

La característica principal es que **el lado derecho funciona como Studio (320 px)**, compuesto por paneles especializados apilables, plegables y con pestañas directas.

---

## 3. Características de ProStudio

El panel profesional de Vectopen permite:

* **Contenedor Studio lateral derecho fijo (320 px)** con tema oscuro profesional (`#1f1f21`, borde `#383840`).
* **Secciones colapsables individuales (Accordion)** con toggle rápido `▼` / `▶`.
* **Sincronización bidireccional inmediata** con `InspectorCore`, `ColorCore` y `MoveTool`.
* **Integración con AdaptiveUIManager**: activación limpia al seleccionar el modo Profesional, ocultando los controles simplificados de Modern y Smart UI.

---

## 4. Módulos Principales del Studio Profesional

### A. Colour (Color y Muestras)
Inspirado en Affinity Designer:
- Swatches entrelazados en la esquina superior: Selector simultáneo de Relleno frontal (Fill) y Trazo secundario (Stroke).
- Conmutador de espacio de color: **RGB** (0-255) y **HSL** (360° / 100%).
- Sliders continuos acompañados de SpinBoxes numéricos de precisión para cada canal.
- Entrada directa en formato Hexadecimal (`#RRGGBB`).
- Slider dedicado de Opacidad porcentual (0 % - 100 %).
- Cuadrícula de **Muestras Rápidas (Swatches)** con colores esenciales y acceso a la paleta de documento.

### B. Stroke (Trazo)
Control exhaustivo de trazo vectorial:
- Anchura: SpinBox numérico de paso fino con soporte de 0.5 px y sufijo dinámico.
- Estilo: Botones de chip directo para línea **Sólida** o **Guiones (Dashed)** con control independiente de largo de trazo y separación de espacio.
- Remates (Cap): **Plano (Butt)**, **Redondeado (Round)**, **Cuadrado (Square)**.
- Alineación (Align): **Centro**, **Interior**, **Exterior**.
- Checkbox de comportamiento: **"Escalar trazo con objeto"** al transformar.

### C. Transform (Transformar)
- **Matriz de Origen 3×3**: Selector interactivo de 9 puntos de anclaje para establecer el punto de referencia de transformaciones y escalado.
- Coordenadas **X** e **Y** con control numérico.
- Dimensiones **Ancho (W)** y **Alto (H)** con botón de bloqueo de proporción (🔗).
- **Rotación (R)** angular con rango de -360° a +360° y símbolo de grados (°).
- **Inclinación / Shear (S)** angular con rango de -89° a +89°.

### D. Layers & Fusión (Capas y Fusión)
- Desplegable de Modos de Fusión: Normal, Multiplicar, Trama, Superponer, Oscurecer, Aclarar, Diferencia.
- Slider numérico de opacidad de capa/objeto.
- Acciones de visibilidad (`👁 Visible`) y bloqueo (`🔒 Bloquear`).
- Reordenación directa de profundidad Z: Traer al frente (`⤒`), Avanzar (`↑`), Retroceder (`↓`), Enviar al fondo (`⤓`).

---

# PARTE II — Dimensión Editorial y Publicitaria (InDesign)

## 1. Módulo de Publicación y Pliegos (Publication Studio)

Vectopen incluye en su Studio Profesional controles para maquetación, publicidad e imprenta:

- **Navegación de Páginas y Pliegos**: Selector de páginas con botones anterior/siguiente (`◀ Página 1 (Pliego Simple) ▶`).
- **Control de Sangrado (Bleed)**: Campo numérico en milímetros (ej. 3.0 mm) con botón toggle para mostrar u ocultar las guías de sangrado y corte en el lienzo.
- **Márgenes Editoriales**: Configuración visual directa de los 4 márgenes de página:
  - Margen Superior (**T**)
  - Margen Inferior (**B**)
  - Margen Izquierdo / Interior (**L**)
  - Margen Derecho / Exterior (**R**)

---

## 2. Comparativa entre los Tres Modos de Vectopen

| Característica | Smart UI | Modern UI (Figma UI3) | Professional UI (Affinity + InDesign) |
| :--- | :--- | :--- | :--- |
| **Enfoque** | Rápido, contextual, inmersivo | Equilibrado, limpio, centrado en selección | Alta densidad, modular y técnico |
| **Inspector** | Oculto / Tarjeta en ratón | Docked Inspector fijo (268 px) | Studio modular ampliado (320 px) |
| **Color** | Popover flotante multi-pestaña | Popover acoplado a la muestra del inspector | Panel Studio con swatches entrelazados y canales |
| **Trazo** | Mini-panel contextual | Fila de trazo compacta con alineación | Panel de trazo completo (remates, uniones, dash) |
| **Menú Contextual**| Tarjeta inteligente multi-tab | Menú vertical elegante Figma/Penpot | Menú extendido con opciones avanzadas de nodo |
| **Publicación** | Bloques predefinidos de diseño | Exportación integrada en inspector | Módulo de Publicación con Páginas, Bleed y Márgenes |
