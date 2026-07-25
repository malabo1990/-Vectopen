# Contributing to Vectopen

First off, thank you for considering contributing to Vectopen! We welcome help from everyone, whether you're a developer, designer, translator, or user.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Report Bugs](#report-bugs)
  - [Suggest Features](#suggest-features)
  - [Submit Code Changes](#submit-code-changes)
  - [Improve Documentation](#improve-documentation)
  - [Translate the Project](#translate-the-project)
- [Development Setup](#development-setup)
- [Coding Guidelines](#coding-guidelines)
  - [GDScript Conventions](#gdscript-conventions)
  - [Architecture Rules](#architecture-rules)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Harassment, discrimination, or toxic behavior of any kind will not be tolerated.

## How Can I Contribute?

### Report Bugs

1. Check if the bug has already been reported in [GitHub Issues](https://github.com/malabo1990/-Vectopen/issues)
2. If not, open a new issue with:
   - A clear title and description
   - Steps to reproduce the bug
   - Expected vs actual behavior
   - Screenshots or GIFs if applicable
   - Godot version and operating system

### Suggest Features

1. Open a [GitHub Issue](https://github.com/malabo1990/-Vectopen/issues/new) with the label `enhancement`
2. Describe the feature and the problem it solves
3. Reference similar features in other tools (Affinity Designer, Figma, Illustrator) if applicable

### Submit Code Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes following the [coding guidelines](#coding-guidelines)
4. Write or update tests
5. Commit and push to your fork
6. Open a Pull Request to the `main` branch

### Improve Documentation

- Fix typos or clarify language in README, CONTRIBUTING, or technical docs
- Add missing JSDoc-style comments to GDScript functions
- Create tutorials or guides for using Vectopen

### Translate the Project

1. Check `translations/vectopen.csv` for the base strings
2. Copy an existing `.translation` file (e.g., `vectopen.en.translation`) as a template
3. Translate the strings
4. Submit a PR with your new translation file

## Development Setup

### Prerequisites

- [Godot Engine 4.7+](https://godotengine.org/download/) with GL Compatibility renderer
- [gdUnit4](https://github.com/MikeSchulze/gdUnit4) (included as `addons/gdUnit4/`)

### First Run

```bash
git clone https://github.com/malabo1990/-Vectopen.git
cd -Vectopen
godot --path . --editor
```

The main scene is `res://scenes/canvas/canvas.tscn`.

### Running Tests

Tests use gdUnit4. Open the project in Godot, then:

1. Go to **Project > Tools > gdUnit4 > Run All Tests**
2. Or run from the command line (see gdUnit4 docs)

## Coding Guidelines

### GDScript Conventions

| Rule | Convention |
|------|-----------|
| File names | `snake_case.gd` (e.g., `bezier_tool.gd`) |
| Class names | `PascalCase` (e.g., `class MoveTool`) |
| Variables | `snake_case` |
| Constants | `UPPER_SNAKE_CASE` |
| Signals | Use `GlobalEvents.emit_safe()` instead of direct `emit_signal()` |
| Node access | Use `%UniqueName` notation over `get_node()` |
| Static types | Always type variables and function returns |

### Architecture Rules

- **Data flow:** UI → Signal → GlobalEvents → DataRepository (model). Never modify data directly from UI code.
- **Tools:** Every tool must implement `activate()`, `deactivate()`, and `handle_input(event) -> bool`.
- **Canvas rendering:** Use `queue_redraw()` + `_draw()` for all vector rendering. Never use Control nodes for canvas drawing.
- **Undo/Redo:** All data mutations must go through DataRepository to be undoable.
- **Signals:** Prefer `GlobalEvents` signal bus over direct node references for cross-system communication.
- **Singletons:** Use autoloads for global state, but keep them focused (avoid god objects).

## Testing

- Tests are located in `test/` and mirror the `script_gdscript/` structure
- We use **gdUnit4** as the testing framework
- Aim to cover new code with at least one test case
- Run existing tests before submitting a PR to ensure nothing is broken

### Test Structure

```
test/
  autoloads/       # Tests for singleton autoloads
  canvas/          # Tests for canvas and bounding box
  core/            # Tests for core math (DVec2, etc.)
  shapes/          # Tests for vector shapes
  tools/           # Tests for editing tools
  ui/              # Tests for UI components
```

## Pull Request Process

1. Ensure your branch is based on the latest `main`
2. Run all tests to confirm nothing is broken
3. Update documentation if your change affects the public API or CLI
4. Add a clear description of what your PR does and why
5. Reference any related issues (e.g., "Closes #42")
6. A maintainer will review your PR and may request changes

### PR Checklist

- [ ] Code follows GDScript conventions
- [ ] Tests added/updated for new functionality
- [ ] Documentation updated (if applicable)
- [ ] All existing tests pass
- [ ] No new unused imports or orphaned files

---

Thank you for contributing to Vectopen! 🎨
