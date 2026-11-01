//! vectopen_io — importación (y más adelante exportación) NATIVA de Vectopen.
//!
//! Núcleo en Rust puro (model, guard, raster, svg…) que se prueba con
//! `cargo test`; aquí solo está el puente con Godot. Expuesto a GDScript como
//! `VectopenIO` (`ClassDB.instantiate("VectopenIO")`). Si esta librería no
//! carga en un sistema, Vectopen usa los importadores GDScript de siempre.

pub mod guard;
pub mod model;
pub mod raster;
pub mod svg;

use godot::classes::image::Format;
use godot::classes::{Image, RefCounted};
use godot::prelude::*;

use model::*;

struct VectopenIoExtension;

#[gdextension]
unsafe impl ExtensionLibrary for VectopenIoExtension {}

/// Extensiones que el importador nativo ya lee. El resto → GDScript.
pub const IMPORT_EXTS: &[&str] = &["svg", "svgz", "png", "jpg", "jpeg", "webp", "gif", "bmp", "tif", "tiff"];

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
        }
    }
    Some(d)
}
