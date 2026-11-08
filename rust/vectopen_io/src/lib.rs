//! vectopen_io — importación (y más adelante exportación) NATIVA de Vectopen.
//!
//! Núcleo en Rust puro (model, guard, raster, svg…) que se prueba con
//! `cargo test`; aquí solo está el puente con Godot. Expuesto a GDScript como
//! `VectopenIO` (`ClassDB.instantiate("VectopenIO")`). Si esta librería no
//! carga en un sistema, Vectopen usa los importadores GDScript de siempre.

pub mod affinity;
pub mod guard;
pub mod model;
pub mod raster;
pub mod stroke;
pub mod svg;
pub mod svg_write;

use godot::classes::image::Format;
use godot::classes::{Image, RefCounted};
use godot::prelude::*;

use model::*;

struct VectopenIoExtension;

#[gdextension]
unsafe impl ExtensionLibrary for VectopenIoExtension {}

/// Extensiones que el importador nativo ya lee. El resto → GDScript.
pub const IMPORT_EXTS: &[&str] = &[
    "svg", "svgz", "png", "jpg", "jpeg", "webp", "gif", "bmp", "tif", "tiff",
    "af", "afdesign", "afphoto", "afpub", "aftemplate",
];

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct VectopenIO {
    base: Base<RefCounted>,
}

#[godot_api]
impl VectopenIO {
    #[func]
    fn version(&self) -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Malla del trazo de pincel (StrokeGeom._halves nativo, ver stroke.rs).
    /// Devuelve {points, indices, v, k, beyond} como el GDScript.
    #[func]
    fn stroke_halves(&self, pts: PackedVector2Array, half: PackedFloat32Array, cap_s: i32, cap_e: i32) -> VarDictionary {
        let p: Vec<stroke::V> = pts.as_slice().iter().map(|v| stroke::V::new(v.x, v.y)).collect();
        let m = stroke::halves(&p, half.as_slice(), cap_s, cap_e);
        let mut d = VarDictionary::new();
        let pv: PackedVector2Array = m.points.iter().map(|v| Vector2::new(v.x, v.y)).collect();
        let iv: PackedInt32Array = m.indices.iter().copied().collect();
        let vv: PackedFloat32Array = m.v.iter().copied().collect();
        let kv: PackedInt32Array = m.k.iter().copied().collect();
        let bv: PackedFloat32Array = m.beyond.iter().copied().collect();
        d.set("points", &pv);
        d.set("indices", &iv);
        d.set("v", &vv);
        d.set("k", &kv);
        d.set("beyond", &bv);
        d
    }

    /// Extensiones (sin punto) que `import_file` sabe leer.
    #[func]
    fn import_extensions(&self) -> PackedStringArray {
        IMPORT_EXTS.iter().map(|s| GString::from(*s)).collect()
    }

    /// Importa `path` (ruta del sistema, ya globalizada). Devuelve
    /// {ok, error, size, items, warnings}; `items` con el formato de svg_import.gd.
    #[func]
    fn import_file(&self, path: GString) -> VarDictionary {
        let p = path.to_string();
        let r = guard::run_isolated(move || import_path(&p));
        let mut d = VarDictionary::new();
        match r {
            Ok(doc) => {
                d.set("ok", true);
                d.set("error", "");
                d.set("size", v2(doc.size));
                let mut items = VarArray::new();
                for it in &doc.items {
                    if let Some(v) = item_to_godot(it) {
                        items.push(&v.to_variant());
                    }
                }
                d.set("items", &items);
                let mut pages = VarArray::new();
                for pg in &doc.pages {
                    let mut pd = VarDictionary::new();
                    pd.set("name", pg.name.as_str());
                    pd.set("size", v2(pg.size));
                    pd.set("origin", v2(pg.origin));
                    pd.set("bg", &col(pg.bg));
                    let mut its = VarArray::new();
                    for it in &pg.items {
                        if let Some(v) = item_to_godot(it) {
                            its.push(&v.to_variant());
                        }
                    }
                    pd.set("items", &its);
                    pages.push(&pd.to_variant());
                }
                d.set("pages", &pages);
                let mut w = VarArray::new();
                for s in &doc.warnings {
                    w.push(&GString::from(s.as_str()).to_variant());
                }
                d.set("warnings", &w);
            }
            Err(e) => {
                d.set("ok", false);
                d.set("error", e.as_str());
                d.set("size", Vector2::new(800.0, 600.0));
                d.set("items", &VarArray::new());
                d.set("warnings", &VarArray::new());
            }
        }
        d
    }

    /// Convierte cualquier archivo que sepa importar a SVG (p. ej. Affinity →
    /// SVG). Devuelve "" si salió bien o el mensaje de error.
    #[func]
    fn convert_to_svg(&self, src: GString, dst: GString) -> GString {
        let (s, d) = (src.to_string(), dst.to_string());
        let r = guard::run_isolated(move || {
            let doc = import_path(&s)?;
            std::fs::write(&d, svg_write::to_svg(&doc)).map_err(|e| format!("no se pudo escribir «{}» ({e})", guard::file_name(&d)))
        });
        match r {
            Ok(()) => GString::new(),
            Err(e) => GString::from(e.as_str()),
        }
    }

    /// Cualquier imagen (también JPEG CMYK) → PNG. Vacío si no se pudo leer.
    #[func]
    fn image_to_png(&self, bytes: PackedByteArray) -> PackedByteArray {
        let b = bytes.to_vec();
        match guard::run_isolated(move || raster::to_png(&b)) {
            Ok(png) => PackedByteArray::from(png.as_slice()),
            Err(_) => PackedByteArray::new(),
        }
    }
}

/// Lee y convierte un archivo según su extensión, comprobando que su contenido
/// sea de verdad de ese tipo.
pub fn import_path(path: &str) -> Result<Doc, String> {
    let name = guard::file_name(path);
    let ext = std::path::Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    if !IMPORT_EXTS.contains(&ext.as_str()) {
        return Err(format!("el importador nativo aún no lee .{ext}"));
    }
    let bytes = guard::read_file(path)?;
    let kind = guard::sniff(&bytes);
    match ext.as_str() {
        e if affinity::EXTS.contains(&e) => {
            if kind != "affinity" {
                return Err(format!("«{name}» no es un archivo de Affinity válido{} o está dañado", seems(kind)));
            }
            affinity::import(&bytes)
        }
        "svg" | "svgz" => {
            if kind != "svg" && kind != "gzip" {
                return Err(format!("«{name}» no es un SVG válido{} o está dañado", seems(kind)));
            }
            svg::parse(&bytes)
        }
        _ => {
            let im = raster::decode(&bytes).map_err(|e| format!("no se pudo leer la imagen «{name}» ({e})"))?;
            let mut doc = Doc::new([im.width as f32, im.height as f32]);
            doc.items.push(Item::Image(ImageItem {
                width: im.width,
                height: im.height,
                rgba: im.data,
                xf: Xf::IDENTITY,
                opacity: 1.0,
                effects: Vec::new(),
            }));
            Ok(doc)
        }
    }
}

fn seems(kind: &str) -> String {
    if kind.is_empty() {
        String::new()
    } else {
        format!(" (parece {})", kind.to_uppercase())
    }
}

// ── Doc → Godot ─────────────────────────────────────────────────────────────
fn v2(p: V2) -> Vector2 {
    Vector2::new(p[0], p[1])
}

fn col(c: Option<Rgba>) -> Variant {
    match c {
        Some(c) => Color::from_rgba(c[0], c[1], c[2], c[3]).to_variant(),
        None => Variant::nil(),
    }
}

fn xform(m: Xf) -> Transform2D {
    Transform2D::from_cols(Vector2::new(m.a, m.b), Vector2::new(m.c, m.d), Vector2::new(m.e, m.f))
}

fn packed(v: &[V2]) -> PackedVector2Array {
    v.iter().map(|p| v2(*p)).collect()
}

fn effects_to_godot(list: &[Effect]) -> VarArray {
    let mut a = VarArray::new();
    for e in list {
        let mut d = VarDictionary::new();
        d.set("type", e.kind.as_str());
        d.set("enabled", true);
        d.set("offset_x", e.offset[0]);
        d.set("offset_y", e.offset[1]);
        d.set("blur", e.blur);
        d.set("radius", e.blur); // el desenfoque de Vectopen lee «radius»
        d.set("width", e.width);
        d.set("color", &col(Some(e.color)));
        a.push(&d.to_variant());
    }
    a
}

fn item_to_godot(it: &Item) -> Option<VarDictionary> {
    let mut d = VarDictionary::new();
    match it {
        Item::Path(p) => {
            d.set("t", "path");
            let mut subs = VarArray::new();
            for s in &p.subs {
                let mut sd = VarDictionary::new();
                sd.set("anchors", &packed(&s.anchors));
                sd.set("ins", &packed(&s.ins));
                sd.set("outs", &packed(&s.outs));
                sd.set("closed", s.closed);
                subs.push(&sd.to_variant());
            }
            d.set("subs", &subs);
            d.set("fill", &col(p.fill));
            d.set("stroke", &col(p.stroke));
            match &p.grad {
                Some(g) => {
                    let mut gd = VarDictionary::new();
                    gd.set("type", if g.radial { 1 } else { 0 });
                    gd.set("angle", g.angle);
                    let mut stops = VarArray::new();
                    for (o, c) in &g.stops {
                        let mut s = VarArray::new();
                        s.push(&o.to_variant());
                        s.push(&col(Some(*c)));
                        stops.push(&s.to_variant());
                    }
                    gd.set("stops", &stops);
                    d.set("grad", &gd);
                }
                None => d.set("grad", &Variant::nil()),
            }
            match p.dash {
                Some([a, b]) => {
                    let mut da = VarArray::new();
                    da.push(&a.to_variant());
                    da.push(&b.to_variant());
                    d.set("dash", &da);
                }
                None => d.set("dash", &Variant::nil()),
            }
            d.set("width", p.width);
            d.set("cap", p.cap);
            d.set("evenodd", p.evenodd);
            d.set("opacity", p.opacity);
            d.set("name", p.name.as_str());
            d.set("effects", &effects_to_godot(&p.effects));
        }
        Item::Text(t) => {
            d.set("t", "text");
            d.set("text", t.text.as_str());
            d.set("xf", xform(t.xf));
            d.set("size", t.size);
            d.set("color", &col(t.color));
            d.set("family", t.family.as_str());
            d.set("bold", t.bold);
            d.set("opacity", t.opacity);
            d.set("effects", &effects_to_godot(&t.effects));
            if let Some(r) = &t.rich {
                d.set("kind", if r.paragraph { "text_paragraph" } else { "text_title" });
                d.set("width", r.width);
                d.set("height", r.height);
                d.set("align", r.align.as_str());
                d.set("weight", r.weight);
                d.set("italic", r.italic);
                let mut runs = VarArray::new();
                for run in &r.runs {
                    let mut rd = VarDictionary::new();
                    rd.set("length", run.length as i64);
                    rd.set("color", &col(Some(run.color)));
                    rd.set("size", run.size);
                    rd.set("weight", run.weight);
                    rd.set("bold", run.weight >= 600);
                    rd.set("italic", run.italic);
                    rd.set("underline", run.underline);
                    if let Some((c, w)) = run.stroke {
                        rd.set("stroke_color", &col(Some(c)));
                        rd.set("stroke_width", w);
                    }
                    runs.push(&rd.to_variant());
                }
                d.set("runs", &runs);
            }
        }
        Item::Clip(mask, kids, draw) => {
            d.set("t", "clip");
            d.set("draw_mask", *draw);
            let m = item_to_godot(&Item::Path((**mask).clone()))?;
            d.set("mask", &m);
            let mut arr = VarArray::new();
            for k in kids {
                if let Some(v) = item_to_godot(k) {
                    arr.push(&v.to_variant());
                }
            }
            d.set("items", &arr);
        }
        Item::Image(im) => {
            let img = Image::create_from_data(
                im.width as i32,
                im.height as i32,
                false,
                Format::RGBA8,
                &PackedByteArray::from(im.rgba.as_slice()),
            )?;
            d.set("t", "image");
            d.set("image", &img);
            d.set("xf", xform(im.xf));
            d.set("opacity", im.opacity);
            d.set("effects", &effects_to_godot(&im.effects));
        }
    }
    Some(d)
}
