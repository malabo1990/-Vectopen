# Vectopen — Open-Source Vector Graphics Editor

![Vectopen Logo](icon/logo/logo_vectopen.svg)

**Vectopen** is an open-source vector graphics editor built with **Godot Engine 4.7**. It is designed for designers, developers, and creatives who need a lightweight, cross-platform alternative to proprietary tools like Adobe Illustrator or Affinity Designer.

## Features

- 🎨 **Full Vector Editing** — Shapes, bezier curves, boolean operations, and path editing
- 🖱️ **Multi-Tool System** — Selection, move, pen, bezier, brush, text, and shape tools (rectangle, ellipse, polygon, star, triangle, water drop)
- 📐 **Precision Tools** — Smart guides, grid snapping, rulers, and measurement overlays
- 🎭 **Layer System** — Layer tree with drag-and-drop, visibility toggles, and reordering
- ✨ **Effects Pipeline** — Drop shadow, inner shadow, glow, blur, color overlay, gradient overlay, outline, 3D effect
- 🌓 **Theme Support** — Dark and light themes with live switching
- 🌍 **Internationalization** — 11 languages (EN, ES, DE, FR, PT, RU, JA, ZH, HI, AR, and more)
- 🖨️ **Export** — Export to SVG, PNG, Godot `.tscn` format (via plugins)
- ⚡ **Performance** — Object pooling, smart caching, and GPU-based rendering pipeline
- 📦 **Plugin System** — Extend functionality via Godot editor plugins
- 🔄 **Undo/Redo** — Full history stack with multi-level undo support
- 💾 **Save/Load** — JSON-based `.vectopen` project format with auto-save and backup recovery

## Platforms

| Platform | Status |
|----------|--------|
| Windows | ✅ Supported (CI builds) |
| Linux | ✅ Supported (CI builds) |
| macOS | ✅ Supported (CI builds) |
| Web (HTML5) | ✅ Export preset configured |

## Screenshots

> *(Coming soon — see the [Telegram community](https://t.me/vectopen) for previews)*

## Getting Started

### Prerequisites

- [Godot Engine 4.7+](https://godotengine.org/download/) (GL Compatibility renderer)

### Run from Source

```bash
# Clone the repository
git clone https://github.com/malabo1990/-Vectopen.git
cd -Vectopen

# Open in Godot Editor
godot --path . --editor
```

The main scene is `res://scenes/canvas/canvas.tscn`.

### Build an Executable

```bash
# Export preset configured for Windows:
godot --headless --export-debug "Windows" ./build/vectopen.exe
```

See `export_presets.cfg` for all available presets (Windows, Linux, macOS, Web).

## Project Structure

```
autoloads/          # Global singletons (GlobalEvents, DataRepository, ToolManager, etc.)
scenes/             # Godot scenes organized by subsystem
  canvas/           # Drawing canvas, artboard, bounding box, shape manager
  ui/               # Main editor UI, panels, dialogs, effects
scripts/            # Legacy script directory (canvas, UI, tools)
script_gdscript/    # Primary script directory
  core/             # Core math (DVec2 double-precision vector)
  data/             # Data resource manager and curve editor
  shapes/           # Vector shape implementations (Circle, Rectangle, Polygon, Path)
  system/           # Core systems (Performance, Theme, Import/Export, Effects)
  tools/            # All editing tools (MoveTool, PenTool, Beziertool, etc.)
  ui/               # UI component scripts
  utils/            # Utility scripts (cursor, ruler, tooltips, calculator)
tools/              # Tool wrapper scenes (select, move, pen, bezier, brush, etc.)
shader/             # GLSL shaders (SDF circle, smart cursor)
addons/             # Godot editor addons
  gdUnit4/          # Unit testing framework
  godot_mcp/        # MCP server for AI-assisted development
resources/          # Custom Godot Resource definitions
  data/             # VectopenProject, VectopenLayer, VectopenShape, VectopenArtboard
  themes/           # Dark and light theme resources
translations/       # i18n translation files (11 languages)
test/               # gdUnit4 test suites
icon/               # Application icons and UI icon library
docs/en/            # English documentation
  guides/           #   How-to guides (MCP, rendering, errors, save systems)
  reports/          #   Technical reports and reviews
  reference/        #   External references
docs/es/            # Spanish documentation
  guides/           #   Guías prácticas
  reports/          #   Informes técnicos
  reference/        #   Referencias externas
```

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Engine | Godot 4.7 (GL Compatibility) |
| Language | GDScript |
| Testing | gdUnit4 (unit tests) |
| CI/CD | Manual (GitHub Actions workflow planned) |
| MCP | godot-ai (AI-assisted development) |
| Format | `.vectopen` (JSON-based project files) |

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

- 🐛 **Report bugs** — Open a [GitHub Issue](https://github.com/malabo1990/-Vectopen/issues)
- 💡 **Suggest features** — Start a discussion or open a feature request
- 🔧 **Submit PRs** — Fork the repo, create a branch, and open a Pull Request
- 🌐 **Translate** — Help with localization via the translation files in `translations/`

## Community

- **Telegram:** [t.me/vectopen](https://t.me/vectopen)
- **GitHub Issues:** [github.com/malabo1990/-Vectopen/issues](https://github.com/malabo1990/-Vectopen/issues)

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Godot Engine](https://godotengine.org/)
- Testing via [gdUnit4](https://github.com/MikeSchulze/gdUnit4)
- Inspired by Affinity Designer, Figma, and Inkscape
