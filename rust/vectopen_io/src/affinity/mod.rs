//! Documentos nativos de Affinity (Designer, Photo, Publisher 1-2 y el
//! Affinity 3 unificado): .af .afdesign .afphoto .afpub .aftemplate.

pub mod container;
pub mod stream;

#[cfg(test)]
mod tests {
    use super::*;

    /// Con los archivos reales: AFFINITY_LIST=lista.txt cargo test --release affinity_real -- --nocapture
    #[test]
    fn affinity_real() {
        let Ok(list) = std::env::var("AFFINITY_LIST") else { return };
        let (mut ok, mut bad) = (0, 0);
        for p in std::fs::read_to_string(list).unwrap().lines().filter(|l| !l.is_empty()) {
            let data = std::fs::read(p).unwrap();
            let t = std::time::Instant::now();
            let r = container::Archive::open(&data).and_then(|a| {
                let names = a.names().len();
                let dd = a.read("doc.dat")?;
                let doc = stream::parse(&dd)?;
                Ok((a.version, a.class.clone(), names, dd.len(), doc.shared.len(), a.thumbnail().map(|t| t.len())))
            });
            match r {
                Ok(v) => {
                    ok += 1;
                    println!("OK   {:?} {:>5} ms  {}", v, t.elapsed().as_millis(), p.rsplit('/').next().unwrap());
                }
                Err(e) => {
                    bad += 1;
                    println!("FAIL {e}  {}", p.rsplit('/').next().unwrap());
                }
            }
        }
        println!("ok={ok} fallos={bad}");
    }
}

#[cfg(test)]
mod names_test {
    /// AFFINITY_FILE=archivo cargo test --release affinity_names -- --nocapture
    #[test]
    fn affinity_names() {
        let Ok(p) = std::env::var("AFFINITY_FILE") else { return };
        let data = std::fs::read(p).unwrap();
        let a = super::container::Archive::open(&data).unwrap();
        for n in a.names().iter().filter(|n| !n.starts_with("d/")) {
            println!("NAME {n}");
        }
    }
}

pub mod bitmap;
pub mod convert;

use crate::model::{Doc, ImageItem, Item, Xf};

/// Extensiones de Affinity (1, 2 y 3).
pub const EXTS: &[&str] = &["af", "afdesign", "afphoto", "afpub", "aftemplate"];

/// Importa un documento de Affinity. Si no se puede interpretar (o no tiene
/// nada convertible), se usa su vista previa incrustada.
pub fn import(data: &[u8]) -> Result<Doc, String> {
    import_nested(data, 0)
}

/// Documentos incrustados (EmbN) son a su vez documentos de Affinity: se
/// importan con un límite de anidamiento.
pub(crate) fn import_nested(data: &[u8], level: usize) -> Result<Doc, String> {
    if level > 4 {
        return Err("documentos incrustados demasiado anidados".into());
    }
    let a = container::Archive::open(data)?;
    if a.class != "Prsn" {
        return Err("es una biblioteca de recursos de Affinity, no un documento".into());
    }
    let parsed = a.read("doc.dat").and_then(|dd| stream::parse(&dd)).and_then(|t| convert::convert(&t, &a, level));
    let mut doc = match parsed {
        Ok(d) => d,
        Err(e) => {
            let mut d = Doc::new([800.0, 600.0]);
            d.warn(&format!("no se pudo leer el contenido ({e})"));
            d
        }
    };
    if doc.items.is_empty() {
        if let Some(png) = a.thumbnail() {
            if let Ok(im) = crate::raster::decode(png) {
                let s = Xf { a: doc.size[0] / im.width as f32, d: doc.size[1] / im.height as f32, ..Xf::IDENTITY };
                doc.items.push(Item::Image(ImageItem { width: im.width, height: im.height, rgba: im.data, xf: s, opacity: 1.0, effects: Vec::new() }));
                doc.warn("solo la vista previa (imagen)");
            }
        }
    }
    Ok(doc)
}

#[cfg(test)]
mod svg_test {
    /// Convierte cada archivo de la lista a SVG + su miniatura (para comparar):
    /// AFFINITY_LIST=lista AFFINITY_OUT=carpeta cargo test --release affinity_to_svg -- --nocapture
    #[test]
    fn affinity_to_svg() {
        let (Ok(list), Ok(out)) = (std::env::var("AFFINITY_LIST"), std::env::var("AFFINITY_OUT")) else { return };
        for (i, p) in std::fs::read_to_string(list).unwrap().lines().filter(|l| !l.is_empty()).enumerate() {
            let data = std::fs::read(p).unwrap();
            let t = std::time::Instant::now();
            match super::import(&data) {
                Ok(doc) => {
                    let svg = crate::svg_write::to_svg_all(&doc);
                    std::fs::write(format!("{out}/{i:02}.svg"), svg).unwrap();
                    if let Some(th) = super::container::Archive::open(&data).ok().and_then(|a| a.thumbnail().map(|t| t.to_vec())) {
                        std::fs::write(format!("{out}/{i:02}_thumb.png"), th).unwrap();
                    }
                    println!("OK   {i:02} {:>4} ms items={:<5} pág={:<3} size={:?} warn={:?}  {}", t.elapsed().as_millis(), doc.items.len(), doc.pages.len(), doc.size, doc.warnings, p.rsplit('/').next().unwrap());
                }
                Err(e) => println!("FAIL {i:02} {e}  {}", p.rsplit('/').next().unwrap()),
            }
        }
    }
}

#[cfg(test)]
mod robust {
    use super::*;

    #[test]
    fn basura_da_error() {
        assert!(import(b"esto no es affinity").is_err());
        assert!(import(&[0x00, 0xFF, 0x4B, 0x41, 11, 0]).is_err());
        assert!(stream::parse(b"\x00\xffKS\x02\x00").is_err());
    }

    #[test]
    fn archivo_real_cortado_no_revienta() {
        let Ok(p) = std::env::var("AFFINITY_FILE") else { return };
        let data = std::fs::read(p).unwrap();
        for cut in [16, 100, data.len() / 3, data.len() / 2, data.len() - 10] {
            let _ = import(&data[..cut]);
            let _ = crate::guard::run_isolated({
                let d = data[..cut].to_vec();
                move || import(&d).map(|_| ())
            });
        }
        // Bytes cambiados en medio del documento.
        let mut bad = data.clone();
        for i in (200..bad.len()).step_by(997) {
            bad[i] ^= 0x5A;
        }
        let _ = import(&bad);
    }
}

#[cfg(test)]
mod dybm_debug {
    /// AFFINITY_FILE=… cargo test --release dybm_tags -- --nocapture
    #[test]
    fn dybm_tags() {
        let Ok(p) = std::env::var("AFFINITY_FILE") else { return };
        let data = std::fs::read(p).unwrap();
        let a = super::container::Archive::open(&data).unwrap();
        let t = super::stream::parse(&a.read("doc.dat").unwrap()).unwrap();
        let mut n = 0;
        for o in t.shared.values() {
            if o.is("DyBm") && n < 3 {
                n += 1;
                let tags: Vec<String> = o.fields.iter().map(|(k, v)| {
                    let name: String = k.iter().map(|&c| if c.is_ascii_graphic() { c as char } else { char::from_digit(c as u32, 10).unwrap_or('?') }).collect();
                    match v {
                        super::stream::Val::Int(i) => format!("{name}={i}"),
                        super::stream::Val::Enum(i) => format!("{name}=e{i}"),
                        super::stream::Val::List(l) => format!("{name}[{}]", l.len()),
                        _ => name,
                    }
                }).collect();
                println!("DYBM {}", tags.join(" "));
                for ch in ["Sta1", "Sta2", "Sta3", "Sta4"] {
                    if let Some(super::stream::Val::List(l)) = o.get(ch) {
                        let v: Vec<String> = l.iter().map(|x| match x { super::stream::Val::Int(i) => i.to_string(), _ => "?".into() }).collect();
                        println!("  {ch} {}", v.join(","));
                    }
                }
                println!("ERR {:?}", super::bitmap::decode(&a, &t, o).err());
            }
        }
    }
}

#[cfg(test)]
mod bckg_debug {
    /// AFFINITY_FILE=… cargo test --release bckg_head -- --nocapture
    #[test]
    fn bckg_head() {
        let Ok(p) = std::env::var("AFFINITY_FILE") else { return };
        let data = std::fs::read(p).unwrap();
        let a = super::container::Archive::open(&data).unwrap();
        for n in a.names().into_iter().filter(|n| n.starts_with("c/") || n.starts_with("edc/")) {
            let b = a.read(n).unwrap_or_default();
            println!("BCKG {n} len={} head={:02x?}", b.len(), &b[..b.len().min(16)]);
            match super::stream::parse(&b) {
                Ok(t) => {
                    fn show(o: &super::stream::Obj, d: usize) {
                        for (k, v) in &o.fields {
                            let name: String = k.iter().map(|&c| if c.is_ascii_graphic() { c as char } else { '_' }).collect();
                            let desc = match v {
                                super::stream::Val::Raw(r) => format!("raw {} head={:02x?}", r.len(), &r[..r.len().min(12)]),
                                super::stream::Val::Obj(o2) => format!("obj {}", o2.class()),
                                super::stream::Val::List(l) => format!("list {}", l.len()),
                                other => format!("{:?}", other).chars().take(80).collect(),
                            };
                            println!("{}{name} = {desc}", "  ".repeat(d));
                            if let super::stream::Val::Obj(o2) = v { if d < 3 { show(o2, d + 1); } }
                        }
                    }
                    println!("ROOT class={}", t.root.class());
                    show(&t.root, 1);
                }
                Err(e) => println!("ERR {e}"),
            }
        }
    }
}

#[cfg(test)]
mod items_debug {
    use crate::model::Item;
    fn bb(subs: &[crate::model::Sub]) -> [i32; 4] {
        let mut b = [i32::MAX, i32::MAX, i32::MIN, i32::MIN];
        for s in subs { for a in &s.anchors { b[0] = b[0].min(a[0] as i32); b[1] = b[1].min(a[1] as i32); b[2] = b[2].max(a[0] as i32); b[3] = b[3].max(a[1] as i32); } }
        b
    }
    fn show(items: &[Item], d: usize) {
        for it in items {
            let pad = "  ".repeat(d);
            match it {
                Item::Path(p) => println!("{pad}PATH {} bb={:?} fill={:?} grad={} op={} fx={:?}", p.name, bb(&p.subs), p.fill.map(|c| c.map(|v| (v * 100.0) as i32)), p.grad.is_some(), p.opacity, p.effects.iter().map(|e| (e.kind.clone(), e.blur as i32)).collect::<Vec<_>>()),
                Item::Text(t) => println!("{pad}TEXT {:?} at=({:.0},{:.0}) size={}", t.text.chars().take(20).collect::<String>(), t.xf.e, t.xf.f, t.size),
                Item::Image(i) => println!("{pad}IMG {}x{} at=({:.0},{:.0})", i.width, i.height, i.xf.e, i.xf.f),
                Item::Clip(m, k, _) => { println!("{pad}CLIP mask={} bb={:?} fill={:?}", m.name, bb(&m.subs), m.fill.map(|c| c.map(|v| (v * 100.0) as i32))); show(k, d + 1); }
            }
        }
    }
    /// AFFINITY_FILE=… cargo test --release items_tree -- --nocapture
    #[test]
    fn items_tree() {
        let Ok(p) = std::env::var("AFFINITY_FILE") else { return };
        let doc = super::import(&std::fs::read(p).unwrap()).unwrap();
        println!("SIZE {:?} warn={:?}", doc.size, doc.warnings);
        if doc.pages.is_empty() {
            show(&doc.items, 0);
        }
        for pg in &doc.pages {
            println!("PAGE {} {:?}", pg.name, pg.size);
            show(&pg.items, 1);
        }
    }
}
