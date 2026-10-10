//! Glifos VECTORIALES para zoom extremo.
//!
//! Sin MSDF cada letra se rasteriza a tamaño × oversampling; por encima de
//! un tope (raster_cap px por letra) el bitmap se vuelve enorme o, con el
//! tope, borroso. A partir de ahí la letra se dibuja con su CONTORNO real:
//! las curvas se teselan con una tolerancia fijada en px de PANTALLA (nítida
//! a cualquier zoom) y el borde lleva una línea antialiasada de 1 px.
//!
//! Las mallas se cachean por (fuente, glifo, nivel de detalle, trazo) y se
//! comparten entre todos los textos.

use std::cell::RefCell;
use std::collections::HashMap;

use godot::builtin::{
    Color, PackedColorArray, PackedInt32Array, PackedVector2Array, PackedVector3Array, Rect2, Rid, Vector2,
};
use godot::classes::{RenderingServer, TextServer};
use godot::obj::{Gd, Singleton};

use lyon_tessellation::math::point;
use lyon_tessellation::path::Path;
use lyon_tessellation::{
    BuffersBuilder, FillOptions, FillRule, FillTessellator, FillVertex, LineJoin, StrokeOptions,
    StrokeTessellator, StrokeVertex, VertexBuffers,
};

/// Tamaño de referencia al que se piden los contornos: lo bastante grande
/// para que el hinting de FreeType no deforme la letra (a 16–24 px los
/// puntos se ajustan a la rejilla y la forma ampliada se notaría).
const REF_SIZE: i64 = 2048;
/// Error máximo de las curvas, en px de pantalla.
const SCREEN_TOLERANCE: f32 = 0.15;
/// Tope del nivel de detalle (≈ 16 M px por letra): más allá no cambia nada.
const MAX_LOD: i32 = 48;
const MAX_CACHE: usize = 4096;

struct GlyphMesh {
    /// Vértices en unidades REF_SIZE (origen = punto de la línea base).
    verts: Vec<Vector2>,
    indices: Vec<i32>,
    /// Aristas del borde (pares de índices) para el antialias.
    edges: Vec<i32>,
    bounds: Rect2,
}

thread_local! {
    static CACHE: RefCell<HashMap<(u64, i64, i32, u32), Option<GlyphMesh>>> = RefCell::new(HashMap::new());
}

/// Nivel de detalle para una letra de `screen_px` px en pantalla (pasos de √2).
pub fn lod_for(screen_px: f32) -> i32 {
    ((screen_px.max(1.0).log2() * 2.0).ceil() as i32).min(MAX_LOD)
}

fn lod_px(lod: i32) -> f32 {
    2f32.powf(lod as f32 / 2.0)
}

/// Dibuja un glifo como malla. `stroke_px` = grosor del contorno (outline)
/// en px de la fuente a `font_size`; 0 = relleno. `screen_px` = alto de la
/// letra en pantalla (font_size × escala). `cull` = rect local visible.
#[allow(clippy::too_many_arguments)]
pub fn draw_glyph(
    ts: &Gd<TextServer>,
    font_rid: Rid,
    index: i64,
    font_size: i64,
    stroke_px: f32,
    screen_px: f32,
    gp: Vector2,
    color: Color,
    canvas_rid: Rid,
    cull: Option<Rect2>,
) {
    let lod = lod_for(screen_px);
    let s = font_size.max(1) as f32 / REF_SIZE as f32;
    // Grosor en unidades REF, cuantizado a 1/8 px para la clave de caché.
    let stroke_q = (stroke_px / s * 8.0).round().max(0.0) as u32;
    let key = (font_rid.to_u64(), index, lod, stroke_q);

    CACHE.with(|c| {
        let mut cache = c.borrow_mut();
        if !cache.contains_key(&key) {
            if cache.len() >= MAX_CACHE {
                cache.clear();
            }
            let tol = SCREEN_TOLERANCE * REF_SIZE as f32 / lod_px(lod);
            let mesh = build_mesh(ts, font_rid, index, tol, stroke_q as f32 / 8.0);
            cache.insert(key, mesh);
        }
        let Some(mesh) = cache.get(&key).and_then(|m| m.as_ref()) else {
            return;
        };

        let world = Rect2::new(mesh.bounds.position * s + gp, mesh.bounds.size * s);
        if let Some(c) = cull {
            if !c.intersects(world) {
                return;
            }
        }

        let mut pts = PackedVector2Array::new();
        pts.resize(mesh.verts.len());
        {
            let sl = pts.as_mut_slice();
            for (o, v) in sl.iter_mut().zip(&mesh.verts) {
                *o = *v * s + gp;
            }
        }
        let cols = PackedColorArray::from(&[color][..]);
        let mut rs = RenderingServer::singleton();
        rs.canvas_item_add_triangle_array(canvas_rid, &PackedInt32Array::from(mesh.indices.as_slice()), &pts, &cols);

        // Borde antialiasado de ~1 px de pantalla (el relleno de triángulos no
        // tiene antialias y a este tamaño se verían escalones).
        if !mesh.edges.is_empty() {
            let mut lines = PackedVector2Array::new();
            lines.resize(mesh.edges.len());
            {
                let sl = lines.as_mut_slice();
                for (o, &i) in sl.iter_mut().zip(&mesh.edges) {
                    *o = pts.as_slice()[i as usize];
                }
            }
            let px_local = font_size.max(1) as f32 / screen_px.max(1.0);
            rs.canvas_item_add_multiline_ex(canvas_rid, &lines, &cols)
                .width(px_local)
                .antialiased(true)
                .done();
        }
    });
}

fn build_mesh(ts: &Gd<TextServer>, font_rid: Rid, index: i64, tol: f32, stroke_ref: f32) -> Option<GlyphMesh> {
    let data = ts.font_get_glyph_contours(font_rid, REF_SIZE, index);
    let points: PackedVector3Array = data.get("points")?.try_to().ok()?;
    let contours: PackedInt32Array = data.get("contours")?.try_to().ok()?;
    if points.is_empty() || contours.is_empty() {
        return None;
    }
    let path = contours_to_path(points.as_slice(), contours.as_slice())?;

    let mut buf: VertexBuffers<Vector2, u32> = VertexBuffers::new();
    if stroke_ref > 0.0 {
        // outline_size de Godot crece hacia fuera y hacia dentro del borde:
        // línea centrada en el contorno con ese grosor a cada lado.
        let opts = StrokeOptions::tolerance(tol)
            .with_line_width(stroke_ref * 2.0)
            .with_line_join(LineJoin::Round);
        StrokeTessellator::new()
            .tessellate_path(&path, &opts, &mut BuffersBuilder::new(&mut buf, |v: StrokeVertex| {
                let p = v.position();
                Vector2::new(p.x, p.y)
            }))
            .ok()?;
    } else {
        let opts = FillOptions::tolerance(tol).with_fill_rule(FillRule::NonZero);
        FillTessellator::new()
            .tessellate_path(&path, &opts, &mut BuffersBuilder::new(&mut buf, |v: FillVertex| {
                let p = v.position();
                Vector2::new(p.x, p.y)
            }))
            .ok()?;
    }
    if buf.indices.is_empty() {
        return None;
    }

    let indices: Vec<i32> = buf.indices.iter().map(|&i| i as i32).collect();
    let edges = boundary_edges(&indices);
    let mut min = buf.vertices[0];
    let mut max = buf.vertices[0];
    for v in &buf.vertices {
        min = Vector2::new(min.x.min(v.x), min.y.min(v.y));
        max = Vector2::new(max.x.max(v.x), max.y.max(v.y));
    }
    Some(GlyphMesh { verts: buf.vertices, indices, edges, bounds: Rect2::new(min, max - min) })
}

/// Aristas que pertenecen a un solo triángulo = borde de la malla.
fn boundary_edges(indices: &[i32]) -> Vec<i32> {
    let mut count: HashMap<(i32, i32), u32> = HashMap::with_capacity(indices.len());
    for t in indices.chunks_exact(3) {
        for (a, b) in [(t[0], t[1]), (t[1], t[2]), (t[2], t[0])] {
            *count.entry((a.min(b), a.max(b))).or_insert(0) += 1;
        }
    }
    let mut out = Vec::new();
    for ((a, b), n) in count {
        if n == 1 {
            out.push(a);
            out.push(b);
        }
    }
    out
}

/// Contornos TrueType/CFF de TextServer (z = etiqueta: 1 en curva, 0 control
/// cuadrático, 2 control cúbico) → Path de lyon.
fn contours_to_path(pts: &[godot::builtin::Vector3], ends: &[i32]) -> Option<Path> {
    let mut b = Path::builder();
    let mut start = 0usize;
    let mut any = false;
    for &end in ends {
        let end = end as usize;
        if end < start || end >= pts.len() {
            break;
        }
        let c = &pts[start..=end];
        start = end + 1;
        if c.len() < 2 {
            continue;
        }
        let n = c.len();
        let p = |i: usize| {
            let v = c[i % n];
            point(v.x, v.y)
        };
        let tag = |i: usize| c[i % n].z.round() as i32;

        // Punto inicial: el primero en curva; si no hay, el medio de dos
        // controles cuadráticos.
        let first_on = (0..n).find(|&i| tag(i) == 1);
        let (origin, first) = match first_on {
            Some(i) => (p(i), i),
            None => (p(0).lerp(p(1), 0.5), 0),
        };
        b.begin(origin);
        let mut conic: Option<lyon_tessellation::math::Point> = None;
        let mut cubic: Vec<lyon_tessellation::math::Point> = Vec::new();
        let steps = if first_on.is_some() { n } else { n + 1 };
        for k in 1..=steps {
            let i = first + k;
            let closing = k == steps;
            let (pt, t) = if closing { (origin, 1) } else { (p(i), tag(i)) };
            match t {
                1 => {
                    if let Some(cp) = conic.take() {
                        b.quadratic_bezier_to(cp, pt);
                    } else if cubic.len() >= 2 {
                        b.cubic_bezier_to(cubic[0], cubic[1], pt);
                        cubic.clear();
                    } else {
                        b.line_to(pt);
                    }
                }
                0 => {
                    if let Some(cp) = conic {
                        b.quadratic_bezier_to(cp, cp.lerp(pt, 0.5));
                    }
                    conic = Some(pt);
                }
                _ => cubic.push(pt),
            }
        }
        b.end(true);
        any = true;
    }
    any.then(|| b.build())
}
