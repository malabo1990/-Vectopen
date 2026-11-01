# PENDIENTE — estado actual

**Actualizado:** 2026-11-01
**Estado del árbol:** rama `multi-artboard-lazy-loading` con cambios de trabajo en curso (ver `git status`); este documento no altera el historial.

El plan de producto vive en [`ROADMAP.md`](ROADMAP.md) y en
[`docs/roadmap/`](docs/roadmap/). Las tareas del próximo release están como
issues del milestone [`0.2.1-alpha`](https://github.com/malabo1990/-Vectopen/milestone/1).

Lo de septiembre de 2026 quedó archivado en
[`docs/archive/PENDIENTE-2026-09.md`](docs/archive/PENDIENTE-2026-09.md):
su trabajo ya está commiteado (`422357d`, `4331471`).

---

## 1. Verificaciones manuales en el editor

Ninguna comprobada todavía:

- [ ] Cambiar de tema con 2+ elementos seleccionados: los chips Smart/Modern/Pro
      deben seguir el tema (antes se quedaban claros en tema oscuro).
- [ ] Seleccionar 2 polígonos regulares → panel Triángulo → *Aplicar a selección*
      → `Ctrl+Z`: los dos vuelven a ser regulares a la vez.
- [ ] Rectángulo → *Esquinas independientes* → mover los 4 sliders → *Aplicar a
      selección* → `Ctrl+Z`: las 4 esquinas revierten en **un solo** paso.

## 2. Pruebas

- [ ] Ejecutar la suite **completa** de gdUnit4 (en septiembre solo se corrieron
      las áreas tocadas y adyacentes).

## 3. Documentación

- [ ] Mantener `docs/roadmap/` al día cuando cambie el alcance de una fase.
- [ ] Al cerrar el milestone `0.2.1-alpha`, mover los items hechos a la sección
      *Done* de `ROADMAP.md`.

---

## Higiene de `godot_mcp` / `claude.bat`

Incidente real (2026-09): con el plugin activo y sin servidor MCP levantado, el
proyecto escribió ~250 GB de logs.

- Antes y después de cada sesión de agente: matar `Godot_v4*` y
  `node … godot-mcp-server` sueltos.
- Comprobar el tamaño de `user://logs/`: debe estar en KB, no en GB.
- Mantener el plugin **desactivado** para edición normal y `vectopen_mcp.cfg`
  con `enabled=false` salvo sesión de agente.
