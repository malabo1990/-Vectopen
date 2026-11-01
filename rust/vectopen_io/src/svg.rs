//! SVG / SVGZ → Doc, con usvg (CSS, <use>, viewBox, unidades, transformaciones
//! y degradados ya resueltos). Las imágenes externas NO se leen del disco:
//! solo las incrustadas (data:), así un SVG no puede leer otros archivos.

use std::sync::{Arc, OnceLock};

use usvg::tiny_skia_path::PathSegment;
use usvg::{Node, Paint};

use crate::model::*;

fn fontdb() -> Arc<usvg::fontdb::Database> {
    static DB: OnceLock<Arc<usvg::fontdb::Database>> = OnceLock::new();
    DB.get_or_init(|| {
        let mut db = usvg::fontdb::Database::new();
        db.load_system_fonts();
        Arc::new(db)
    })
    .clone()
}

/// ¿Está instalada en el sistema una fuente con esta familia?
pub fn font_installed(family: &str) -> bool {
    let f = family.trim().to_lowercase();
    if f.is_empty() {
        return true;
    }
    fontdb().faces().any(|face| face.families.iter().any(|(n, _)| n.to_lowercase() == f))
}

pub fn parse(bytes: &[u8]) -> Result<Doc, String> {
    let mut opt = usvg::Options::default();
    opt.fontdb = fontdb();
    // Sin acceso a archivos externos (seguridad): solo datos incrustados.
    opt.image_href_resolver.resolve_string = Box::new(|_, _| None);
    let tree = usvg::Tree::from_data(bytes, &opt).map_err(|e| format!("SVG no válido: {e}"))?;
    let sz = tree.size();
    let mut doc = Doc::new([sz.width(), sz.height()]);
    walk(tree.root(), 1.0, &mut doc);
    Ok(doc)
}

fn xf(t: usvg::Transform) -> Xf {
    Xf { a: t.sx, b: t.ky, c: t.kx, d: t.sy, e: t.tx, f: t.ty }
}

fn walk(g: &usvg::Group, opacity: f32, doc: &mut Doc) {
    let op = opacity * g.opacity().get();
    if g.clip_path().is_some() || g.mask().is_some() {
        doc.warn("recortes");
    }
    if !g.filters().is_empty() {
        doc.warn("filtros");
    }
    for n in g.children() {
        match n {
            Node::Group(c) => walk(c, op, doc),
            Node::Path(p) => path(p, op, doc),
            Node::Image(i) => image(i, op, doc),
            Node::Text(t) => text(t, op, doc),
        }
    }
}

fn color(c: usvg::Color, a: f32) -> Rgba {
    [c.red as f32 / 255.0, c.green as f32 / 255.0, c.blue as f32 / 255.0, a]
}

/// Color plano y degradado (si lo hay) de una pintura.
fn paint(p: &Paint, a: f32, m: Xf, doc: &mut Doc) -> (Option<Rgba>, Option<Grad>) {
    match p {
        Paint::Color(c) => (Some(color(*c, a)), None),
        Paint::LinearGradient(lg) => {
            let g = grad(lg.stops(), a, false, {
                let t = xf(lg.transform());
                let p0 = m.apply(t.apply([lg.x1(), lg.y1()]));
                let p1 = m.apply(t.apply([lg.x2(), lg.y2()]));
                (p1[1] - p0[1]).atan2(p1[0] - p0[0])
            });
            (mid(&g), g)
        }
        Paint::RadialGradient(rg) => {
            let g = grad(rg.stops(), a, true, 0.0);
            (mid(&g), g)
        }
        Paint::Pattern(_) => {
            doc.warn("patrones");
            (Some([0.5, 0.5, 0.5, a]), None)
        }
    }
}

fn grad(stops: &[usvg::Stop], a: f32, radial: bool, angle: f32) -> Option<Grad> {
    if stops.is_empty() {
        return None;
    }
    Some(Grad {
        radial,
        angle,
        stops: stops.iter().map(|s| (s.offset().get(), color(s.color(), s.opacity().get() * a))).collect(),
    })
}

/// Color de reserva para formas que no admiten degradado: el del centro.
fn mid(g: &Option<Grad>) -> Option<Rgba> {
    let g = g.as_ref()?;
    let (a, b) = (g.stops.first()?.1, g.stops.last()?.1);
    Some([0, 1, 2, 3].map(|i| (a[i] + b[i]) * 0.5))
}

fn path(p: &usvg::Path, op: f32, doc: &mut Doc) {
    if !p.is_visible() {
        return;
    }
    let m = xf(p.abs_transform());
    let mut b = Builder::default();
    for seg in p.data().segments() {
        match seg {
            PathSegment::MoveTo(a) => b.move_to(m.apply([a.x, a.y])),
            PathSegment::LineTo(a) => b.line_to(m.apply([a.x, a.y])),
            PathSegment::QuadTo(q, a) => b.quad_to(m.apply([q.x, q.y]), m.apply([a.x, a.y])),
            PathSegment::CubicTo(c1, c2, a) => {
                b.cubic_to(m.apply([c1.x, c1.y]), m.apply([c2.x, c2.y]), m.apply([a.x, a.y]))
            }
            PathSegment::Close => b.close(),
        }
    }
    let subs = b.finish();
    if subs.is_empty() {
        return;
    }
    let k = m.scale();
    let (fill, grad, evenodd) = match p.fill() {
        Some(f) => {
            let (c, g) = paint(f.paint(), f.opacity().get(), m, doc);
            (c, g, f.rule() == usvg::FillRule::EvenOdd)
        }
        None => (None, None, false),
    };
    let (mut stroke, mut width, mut cap, mut dash) = (None, 0.0, 0, None);
    if let Some(s) = p.stroke() {
        let (c, g) = paint(s.paint(), s.opacity().get(), m, doc);
        if g.is_some() {
            doc.warn("degradados en el trazo");
        }
        stroke = c;
        width = s.width().get() * k;
        cap = match s.linecap() {
            usvg::LineCap::Butt => 0,
            usvg::LineCap::Round => 1,
            usvg::LineCap::Square => 2,
        };
        if let Some(d) = s.dasharray() {
            let d0 = d.first().copied().unwrap_or(0.0);
            let d1 = d.get(1).copied().unwrap_or(d0);
            if d0 > 0.0 || d1 > 0.0 {
                dash = Some([d0 * k, d1 * k]);
            }
        }
    }
    let name = if p.id().is_empty() { "Trazado".to_string() } else { p.id().to_string() };
    doc.items.push(Item::Path(PathItem { subs, fill, stroke, grad, dash, width, cap, evenodd, opacity: op, name, effects: Vec::new() }));
}

fn image(i: &usvg::Image, op: f32, doc: &mut Doc) {
    if !i.is_visible() {
        return;
    }
    let bytes: &[u8] = match i.kind() {
        usvg::ImageKind::JPEG(d) | usvg::ImageKind::PNG(d) | usvg::ImageKind::GIF(d) | usvg::ImageKind::WEBP(d) => d,
        usvg::ImageKind::SVG(sub) => {
            // SVG dentro de SVG: sus objetos se añaden con la transformación de la imagen.
            let m = xf(i.abs_transform());
            let mut inner = Doc::new(doc.size);
            walk(sub.root(), op, &mut inner);
            for it in inner.items {
                doc.items.push(transform_item(it, m));
            }
            doc.warnings.extend(inner.warnings);
            return;
        }
    };
    match crate::raster::decode(bytes) {
        Ok(im) => {
            let sz = i.size();
            let s = Xf { a: sz.width() / im.width as f32, b: 0.0, c: 0.0, d: sz.height() / im.height as f32, e: 0.0, f: 0.0 };
            let t = mul(xf(i.abs_transform()), s);
            doc.items.push(Item::Image(ImageItem { width: im.width, height: im.height, rgba: im.data, xf: t, opacity: op, effects: Vec::new() }));
        }
        Err(_) => doc.warn("imágenes dañadas"),
    }
}

fn text(t: &usvg::Text, op: f32, doc: &mut Doc) {
    let m = xf(t.abs_transform());
    let chunks = t.chunks();
    for ch in chunks {
        let s = ch.text().trim();
        if s.is_empty() {
            continue;
        }
        let Some(span) = ch.spans().first() else { continue };
        let size = span.font_size().get();
        let fam = span
            .font()
            .families()
            .first()
            .map(|f| match f {
                usvg::FontFamily::Named(n) => n.clone(),
                other => other.to_string(),
            })
            .unwrap_or_else(|| "sans-serif".into());
        let col = span.fill().map(|f| match f.paint() {
            Paint::Color(c) => color(*c, f.opacity().get()),
            _ => [0.0, 0.0, 0.0, f.opacity().get()],
        });
        // Una sola línea: la caja real del texto ya maquetado. Varias: la línea
        // base de cada una (la caja empieza ~0,8·tamaño más arriba).
        let origin = if chunks.len() == 1 {
            let bb = t.bounding_box();
            [bb.left(), bb.top()]
        } else {
            [ch.x().unwrap_or(0.0), ch.y().unwrap_or(0.0) - size * 0.8]
        };
        let pos = m.apply(origin);
        let xft = Xf { e: pos[0], f: pos[1], ..m };
        let xft = Xf { a: m.a, b: m.b, c: m.c, d: m.d, ..xft };
        doc.items.push(Item::Text(TextItem {
            text: s.to_string(),
            xf: xft,
            size,
            color: col,
            family: fam,
            bold: span.font().weight() >= 600,
            opacity: op,
            effects: Vec::new(),
            rich: None,
        }));
    }
}

fn mul(p: Xf, q: Xf) -> Xf {
    Xf {
        a: p.a * q.a + p.c * q.b,
        b: p.b * q.a + p.d * q.b,
        c: p.a * q.c + p.c * q.d,
        d: p.b * q.c + p.d * q.d,
        e: p.a * q.e + p.c * q.f + p.e,
        f: p.b * q.e + p.d * q.f + p.f,
    }
}

/// Aplica una transformación a un elemento ya convertido.
pub fn transform_item_pub(it: Item, m: Xf) -> Item {
    transform_item(it, m)
}

fn transform_item(it: Item, m: Xf) -> Item {
    match it {
        Item::Path(mut p) => {
            for s in &mut p.subs {
                for i in 0..s.anchors.len() {
                    let a = s.anchors[i];
                    let pa = m.apply(a);
                    let pin = m.apply([a[0] + s.ins[i][0], a[1] + s.ins[i][1]]);
                    let pout = m.apply([a[0] + s.outs[i][0], a[1] + s.outs[i][1]]);
                    s.ins[i] = [pin[0] - pa[0], pin[1] - pa[1]];
                    s.outs[i] = [pout[0] - pa[0], pout[1] - pa[1]];
                    s.anchors[i] = pa;
                }
            }
            p.width *= m.scale();
            Item::Path(p)
        }
        Item::Text(mut t) => {
            t.xf = mul(m, t.xf);
            Item::Text(t)
        }
        Item::Image(mut im) => {
            im.xf = mul(m, im.xf);
            Item::Image(im)
        }
        Item::Clip(mask, kids, draw) => {
            let Item::Path(pm) = transform_item(Item::Path(*mask), m) else { unreachable!() };
            Item::Clip(Box::new(pm), kids.into_iter().map(|k| transform_item(k, m)).collect(), draw)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn items(svg: &str) -> Doc {
        parse(svg.as_bytes()).unwrap()
    }

    #[test]
    fn rect_con_viewbox_y_transform() {
        let d = items(r##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 100 50">
            <g transform="translate(10 5)"><rect id="caja" x="0" y="0" width="20" height="10" fill="#ff0000"/></g></svg>"##);
        assert_eq!(d.size, [200.0, 100.0]);
        let Item::Path(p) = &d.items[0] else { panic!() };
        assert_eq!(p.name, "caja");
        assert_eq!(p.subs[0].anchors[0], [20.0, 10.0]); // (10,5)·2
        assert_eq!(p.fill, Some([1.0, 0.0, 0.0, 1.0]));
        assert!(p.subs[0].closed);
    }

    #[test]
    fn css_trazo_discontinuo_y_extremo() {
        let d = items(r##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
            <style>.l{stroke:#00f;stroke-width:2;stroke-dasharray:4 2;stroke-linecap:round;fill:none}</style>
            <path class="l" d="M0 0 L10 10"/></svg>"##);
        let Item::Path(p) = &d.items[0] else { panic!() };
        assert_eq!(p.stroke, Some([0.0, 0.0, 1.0, 1.0]));
        assert_eq!((p.width, p.cap, p.dash), (2.0, 1, Some([4.0, 2.0])));
        assert_eq!(p.fill, None);
    }

    #[test]
    fn degradado_lineal_vertical() {
        let d = items(r##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
            <linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
            <rect width="10" height="10" fill="url(#g)"/></svg>"##);
        let Item::Path(p) = &d.items[0] else { panic!() };
        let g = p.grad.as_ref().unwrap();
        assert!((g.angle - std::f32::consts::FRAC_PI_2).abs() < 1e-3);
        assert_eq!(g.stops.len(), 2);
    }

    #[test]
    fn use_se_resuelve_y_opacidad_de_grupo() {
        let d = items(r##"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="10" height="10">
            <defs><circle id="c" r="2"/></defs><g opacity="0.5"><use xlink:href="#c" x="5" y="5"/></g></svg>"##);
        assert_eq!(d.items.len(), 1);
        let Item::Path(p) = &d.items[0] else { panic!() };
        assert!((p.opacity - 0.5).abs() < 1e-6);
    }

    #[test]
    fn svg_roto_da_error() {
        assert!(parse(b"<svg><g></svg").is_err());
    }

    #[test]
    fn imagen_externa_no_se_lee() {
        let d = items(r##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><image href="/etc/passwd" width="5" height="5"/></svg>"##);
        assert!(d.items.is_empty());
    }
}
