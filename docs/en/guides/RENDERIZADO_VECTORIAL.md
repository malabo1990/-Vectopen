# Vector Rendering in Godot 4 — Technical Guide for Vectopen

## 1. The Problem: "Staircase" Curves

In Godot, curved lines look stepped because:

1. **Godot renders vectors as rasterized polygons** — converts curves into triangles/textures
2. **The monitor has square pixels** — a diagonal line is always approximated
3. **Without anti-aliasing, each pixel is either 100% color or 0%** → visible steps

Anti-aliasing (AA) smooths this by giving edge pixels partial opacity.

---

## 2. Godot 4 Renderers

Godot 4 has 3 backend renderers:

### 2.1 gl_compatibility (OpenGL 3.3 / GLES 3.0)
| Aspect | Value |
|--------|-------|
| **MSAA 2D** | ❌ Not supported (the error you see) |
| **Performance** | High (old GPU) |
| **Use case** | Minimum hardware, Web export, old mobile |
| **AA available** | FXAA in 3D, 2D has none |

### 2.2 forward+ (Vulkan)
| Aspect | Value |
|--------|-------|
| **MSAA 2D** | ✅ x2, x4, x8, x16 |
| **Performance** | Excellent |
| **Use case** | PC, consoles, maximum quality |
| **AA available** | MSAA + FXAA + TAA |

### 2.3 mobile (Vulkan)
| Aspect | Value |
|--------|-------|
| **MSAA 2D** | ✅ x2, x4 |
| **Performance** | Balanced |
| **Use case** | Android/iOS |

**Conclusion 1:** Switching to `forward+` enables MSAA 2D and curves look smooth instantly.

---

## 3. Anti-Aliasing (AA) — Types

### 3.1 MSAA (Multisample Anti-Aliasing)
- **How it works**: Takes multiple samples per pixel and averages them
- **Quality**: Very good (x4, x8)
- **Cost**: High (x8 = 8x more GPU work)
- **Godot**: `Project Settings > Rendering > Anti Aliasing > Quality > MSAA 2D`
- **Best for**: 3D scenes with geometry, also improves 2D

### 3.2 FXAA (Fast Approximate AA)
- **How it works**: Post-process that detects edges and smooths them
- **Quality**: Acceptable, edges slightly blurry
- **Cost**: Very low
- **Godot**: `Project Settings > Rendering > Anti Aliasing > Quality > Screen Space AA`
- **Best for**: When MSAA is too expensive

### 3.3 TAA (Temporal AA)
- **How it works**: Uses previous frames to smooth
- **Quality**: Very good, but can have ghosting
- **Cost**: Medium
- **Godot**: `Project Settings > Rendering > Anti Aliasing > Quality > Use TAA`
- **Best for**: Static scenes or slow movement

### 3.4 SSAA (Super-Sampling AA)
- **How it works**: Renders at higher resolution, scales down
- **Quality**: Perfect
- **Cost**: Extremely high (4K rendered for 1080p)
- **Not recommended** for Vectopen

### 3.5 Custom Shader AA
- **How it works**: Shader that applies analytic anti-aliasing on primitive edges
- **Quality**: Depends on the shader
- **Cost**: Low to medium
- **Full control**: You can implement your own algorithm

**Visual comparison:**

| Method | Quality | Performance | Implementation |
|--------|---------|-------------|----------------|
| MSAA x4 | ⭐⭐⭐⭐ | Medium | 1 click in settings |
| MSAA x8 | ⭐⭐⭐⭐⭐ | Low | 1 click |
| TAA | ⭐⭐⭐⭐ | High | 1 click |
| FXAA | ⭐⭐⭐ | Very high | 1 click |
| Custom shader | ⭐⭐⭐⭐⭐ | Medium | Requires code |

---

## 4. Vector Rendering vs Rasterized

### 4.1 Rasterized (Godot native)
```
Vector curve → Triangles → Pixels
```
- Godot converts everything to triangles
- Curves are approximated with straight segments
- Quality depends on the number of segments
- More segments = smoother but slower

**Affecting settings:**
```gdscript
# In curve drawing (draw_arc, draw_circle, etc.)
draw_arc(center, radius, start, end, segments, color)
# More segments = smoother curve
```

### 4.2 Pure vector (Skia, Cairo, NanoVG, Blend2D)
```
Vector curve → Fragment shader → Perfect pixel
```
- Does not approximate with triangles
- Calculates the color of each pixel analytically
- Native sub-pixel anti-aliasing
- Perfect curves without steps

---

## 5. Practical Implementation for Vectopen

### Option A: Switch to forward+ (simplest)
```
Project Settings > Rendering > Renderer > forward+
Rendering > Anti Aliasing > Quality > MSAA 2D > x4
```

**Advantages:** 1 config change, MSAA works  
**Disadvantages:** Not pure vector, curves are still polygonal approximations

### Option B: GDExtension + Vector Library
```
Godot (UI) ←→ GDExtension (C++) ←→ Skia/Blend2D/NanoVG ←→ OpenGL/Vulkan
```

**Recommended architecture:**
```
┌─────────────────────────────────────────┐
│  Godot Editor (UI, events, scene tree)   │
│  ┌───────────────────────────────────┐  │
│  │ TextureRect (displays the canvas)  │  │
│  │   ↑ texture each frame            │  │
│  └───────────────────────────────────┘  │
│              ↕ GDExtension               │
│  ┌───────────────────────────────────┐  │
│  │ Vector Engine (Blend2D/Skia)      │  │
│  │ - Renders perfect curves          │  │
│  │ - Native anti-aliasing            │  │
│  │ - Dash arrays, strokes, gradients │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**Per-frame flow:**
1. Godot detects input (mouse)
2. Passes coordinates to the GDExtension
3. Vector engine renders curves to a buffer
4. Buffer is copied to a Godot texture (ViewportTexture or ImageTexture)
5. TextureRect displays the result

### Option C: Shader-based vector rendering (custom)
You can write shaders that draw curves analytically:

```glsl
// Fragment shader for bezier curve
// Each pixel calculates its distance to the curve
// and applies anti-aliasing based on distance
void fragment() {
    float dist = sd_bezier(UV, control_points);
    float alpha = 1.0 - smoothstep(0.0, 1.0/SCREEN_PIXEL_SIZE, abs(dist));
    COLOR = vec4(stroke_color, alpha);
}
```

**Advantages:** No external dependencies  
**Disadvantages:** Extremely complex for arbitrary curves, variable performance

---

## 6. Script Performance

### 6.1 CPU bottleneck (GDScript)
GDScript is interpreted, not compiled. Intensive operations:

| Operation | Cost |
|-----------|------|
| Function calls | High (dynamic dispatch) |
| Large loops (>1000 iterations) | High |
| Frequent `get_node()` | Medium |
| Variant assignment | Medium |
| Simple math calculations | Low |

**Recommendations for Vectopen:**
- The **drawing loop** must be in C++ (GDExtension) or in a fragment shader
- GDScript handles UI, events, tool logic — not rendering
- Use `PackedVector2Array` instead of `Array[Vector2]` for dense data
- Avoid `get_node()` in loops — cache references
- Use `@onready` for every node accessed frequently

### 6.2 GPU bottleneck
| Factor | Impact |
|--------|--------|
| MSAA x4 | 4x more pixels to process |
| Number of curves | Draw calls |
| Texture size | Memory |
| Complex shaders | Instructions per pixel |

### 6.3 RenderingServer calls
Instead of nodes, you can operate directly on the `RenderingServer`:

```gdscript
# Instead of CanvasItem (node)
var ci = RenderingServer.canvas_item_create()
RenderingServer.canvas_item_set_parent(ci, canvas)
RenderingServer.canvas_item_add_line(ci, from, to, color)
```

This is ~10x faster than using nodes for massive draw calls.

---

## 7. Final Recommendation

### For Vectopen today:
1. **Switch to `forward+`** — immediate solution, MSAA 2D works
2. **Reduce MSAA to x4** — quality/performance balance

### For Vectopen in the future (professional quality):
1. **Implement GDExtension with Blend2D** — open source (zlib), modern, fast
2. **The canvas renders to an off-screen buffer** via GDExtension
3. **Godot only displays the result** in a TextureRect
4. **Blend2D's native anti-aliasing** — perfect curves always
5. **No dependency on Godot's renderer** — works on gl_compatibility and forward+

### Recommended stack:
```
┌────────────────────────────────────────────┐
│  Godot 4.7 (forward+)                       │
│  ├── UI: Control nodes (menus, panels)      │
│  ├── Logic: GDScript (tools, events)        │
│  └── Render: GDExtension (Blend2D C++)      │
│       └── Anti-aliasing: native (sub-pixel) │
│       └── Curves: analytic bezier           │
│       └── Strokes: dash arrays, caps, joins │
└────────────────────────────────────────────┘
```

### Visual quality comparison table:

| Method | Smooth curve? | Anti-aliasing | Performance | Effort |
|--------|-------------|---------------|-------------|--------|
| `gl_compatibility` + no AA | ❌ Steps | ❌ | ✅ High | 0 |
| `forward+` MSAA x4 | ✅ Improved | ✅ Good | 🟡 Medium | 5 min |
| `forward+` MSAA x8 | ✅ Very good | ✅ Very good | 🔴 Low | 5 min |
| Custom shader AA | ✅✅ Smooth | ✅✅ Good | ✅ High | 2-3 days |
| GDExtension + Blend2D | ✅✅✅ Perfect | ✅✅✅ Excellent | ✅ High | 2-4 weeks |

---

## 8. Resources

- **Blend2D**: https://blend2d.com/ (zlib license, open source)
- **Skia**: https://skia.org/ (Apache 2.0, open source)
- **NanoVG**: https://github.com/memononen/nanovg (zlib license)
- **Godot Rendering docs**: https://docs.godotengine.org/en/stable/tutorials/rendering/

---

*Documented by: Development Agent — July 2026*
