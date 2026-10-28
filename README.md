# Vectopen — Free, Open-Source Vector Graphics Editor

**Vectopen** is a free, open-source vector graphics editor for **Windows, macOS and Linux**, built with **Godot Engine 4.7**. No account, no telemetry, no paid tier.

🌐 **Website:** https://malabo1990.github.io/vectopen-web/ · 📖 **Manual:** [English](https://malabo1990.github.io/vectopen-web/docs/) · [Español](https://malabo1990.github.io/vectopen-web/docs/es/) · 💬 **Telegram:** [t.me/vectopen](https://t.me/vectopen)

![Vectopen — Modern interface](https://malabo1990.github.io/vectopen-web/media/shots/modern_light.webp)

## Download

**Version 0.2.0-alpha** — [all files on the Releases page](https://github.com/malabo1990/-Vectopen/releases/tag/v0.2.0-alpha)

| System | Package |
|---|---|
| Windows 10/11 (x64) | `.zip` — extract and run `Vectopen.exe` |
| macOS (Intel + Apple Silicon) | universal `.dmg` / `.zip` — *not yet tested on a real Mac* |
| Linux (x86_64) | `.deb`, `.rpm`, portable `.tar.gz` |

Alpha builds are not signed yet: see the [installation guide](https://malabo1990.github.io/vectopen-web/docs/getting-started/installation/) for the Windows and macOS warnings.

## Features

- ✏️ **Drawing & node editing** — pen, Bézier and brush (with tablet pressure), full node editing; rectangles, ellipses, polygons, stars and a shape library (heart, drop, arrows, cloud…).
- 🖼️ **Vectorize images with AI** — turn logos, icons, scans and drawings into vector shapes ([VTracer](https://github.com/visioncortex/vtracer): Bézier, polygon or pixel output). Two **offline AI tools** prepare the image: **background removal** (U²-Net) and **×4 upscaling** (Real-ESRGAN). The models ship inside the app — nothing is uploaded. *(Linux build in 0.2.0-alpha.)* [Guide →](https://malabo1990.github.io/vectopen-web/docs/objects/vectorize/)
- 🎨 **Colour & gradients** — solid, linear and radial gradients on fill **and stroke**, edited on the canvas.
- ✨ **Effects, filters & shaders** — shadows, glow, bevel, 3D, overlays; image filters (frosted glass, grain, duotone, neon, glitch, halftone…); a live shader editor with templates.
- 🗂️ **Professional layers** — sub-layers, clipping masks, type icons, thumbnails, compact view, search filters.
- 📄 **Many artboards, huge files** — the `.vtc` format loads pages on demand: 1,000 pages / 100,000 objects open in ~1.4 s.
- 🔤 **Text & typography** — point and paragraph text, linked frames, Google Fonts, per-letter effects, text to curves.
- 🧩 **Scripts & add-ons** — a GDScript console with the Vectopen API; install add-ons from `.zip`, folder or `.gd`.
- 🤖 **MCP server** — let an AI agent drive a running Vectopen through the same undoable operations as the UI.
- 🖥️ **Three interfaces** — Smart, Modern and Pro; light/dark theme; 10 languages.
- 📤 **Export** — SVG, PDF, EPS, PNG, JPEG, WEBP, Godot scenes. **Import** — SVG (real Bézier curves), PNG/JPEG/WEBP, glTF.

## Run from source

Requires [Godot Engine 4.7+](https://godotengine.org/download/) (standard build, no .NET).

```bash
git clone https://github.com/malabo1990/-Vectopen.git
cd -Vectopen
godot --path . --editor
```

The main scene is `res://scenes/canvas/canvas.tscn`. The native parts (text shaping and the vectorizer) are Rust GDExtensions in `rust/`; packaged builds are produced with `tools/package_release.sh`.

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
| Language | GDScript (~98%) + Rust GDExtensions via [godot-rust](https://github.com/godot-rust/gdext) |
| Vectorizing | [VTracer](https://github.com/visioncortex/vtracer) |
| AI image tools | [ONNX Runtime](https://onnxruntime.ai/) (via `ort`): U²-Net-p (background removal), Real-ESRGAN General x4v3 (upscaling) |
| Testing | gdUnit4 (750+ unit tests) + interface tests that click the real UI |
| Format | `.vtc` (paged, compressed document container) — [specification](https://malabo1990.github.io/vectopen-web/docs/files/project-format/#technical-details) |

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
- Vectorizing by [VTracer](https://github.com/visioncortex/vtracer) (MIT); background removal with U²-Net ([rembg](https://github.com/danielgatis/rembg) model, Apache-2.0); upscaling with [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (BSD-3-Clause)
