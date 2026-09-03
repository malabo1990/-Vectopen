---
title: "Artboards, layers, and a magnet"
date: 2026-09-03
summary: "The recent stretch in one place: the multi-artboard rewrite, the professional layer panel with clip masks, the smart snap system, formal undo state, and a fresh website."
tags: [architecture, layers, snapping, undo]
draft: false
---

Vectopen has been quiet on the outside and busy on the inside. This is the
first post — a catch-up on what landed over the last stretch, roughly in the
order it happened.

## Multi-artboard, done properly

The old canvas assumed one artboard. Five different places hard-coded
`get_child(0)`, and the node that was *supposed* to manage artboards was named
`manager_script`, so half the lookups silently missed it. Symptom: "only the
first artboard works — you can't select or drag the second one."

`ArtboardManager` is now the single authority. Everything that needs to know
*which* artboard goes through it:

- `get_active_artboard()` — the target for new shapes with no explicit point
- `artboard_at_point(world_pos)` — geometric hit-test
- `owning_artboard(node)` — hierarchy lookup, for the "outside the artboard"
  warning in the layer panel

Benchmarks it now survives: a 1,000-page book with ~100k owned elements, and a
single path with 100k bezier control points.

## The layer panel grew up

The layer tree is now a real mirror of the scene graph, not a parallel model:

- **Drag-drop reparenting to any depth.** A grandchild can be pulled out to the
  top level, or dropped three groups deep, and its global transform is
  preserved. Undo/redo walks the whole chain back and forth.
- **Per-row eye / lock / mask**, in fixed columns, on every row.
- **Stencil clip masks** for groups *and* text. This one was a real fix — in
  Godot, `clip_children` clips to the *shape the node draws*. A bare group or a
  text node draws nothing, so turning on clipping made the children vanish.
  Now the top child (or, for text, the letters) becomes the mask and the rest
  of the content is reparented under it — the Illustrator/Affinity behaviour.

While fixing that I found a latent bug: the serializer returned early for every
shape kind *without* saving children, so figure-inside-figure nesting was lost
on save. Fixed and covered with a round-trip test.

## A magnet that actually snaps

`SnapManager.smart_snap()` now does three things per axis, closest wins:

1. **Alignment** — edges and centers against other shapes, the artboard, and
   ruler guides you drag out from the rulers.
2. **Equal spacing** — if the gap to a neighbour matches an existing gap
   somewhere else, it snaps to that distance.
3. **Distribution** — centre a shape exactly between its two side neighbours.

The guides draw full-width across the viewport with the pixel distance shown,
and new ruler guides round to whole pixels. Threshold is constant in screen
space at any zoom.

## Undo you can trust

Two things here. First, `MoveTool._do_apply_transform()` restored a node's
z-order index on undo but re-appended it at the end on redo — asymmetric. Now
it remembers where the node landed and restores that on redo too, so an
artboard-to-artboard move round-trips exactly: parent, global position **and**
z-order.

Second, a new `NodeState` helper: one place to capture and restore the
*non-geometric* state of a node — visibility, lock, clip, clip-mask, z-index.
It's additive to the geometry snapshot, so cancelling a transform with Escape
now restores the whole state, not just position and size.

The rule for the whole selection/transform system: **every bug found becomes a
permanent test.** `TransformRegression_test.gd` is the graveyard.

## Also

- The Inspector now reads `SelectionManager` directly as the source of truth,
  instead of a mirror that `MoveTool` maintains. The fan-out
  (SelectionManager → canvas, layers, inspector) is real now.
- Light/dark theme from design tokens, localisation retranslated on the fly,
  and the tools toolbar got the same monochrome treatment as everything else.
- This website. Black, grey and white — no colour — using the real Vectopen
  mark. And the thing you're reading it on.

Next: the bounding-box bug-hunt matrix (every handle × every shape type × every
zoom level), the font core system, and starting to define the `.vtc` document
format.
