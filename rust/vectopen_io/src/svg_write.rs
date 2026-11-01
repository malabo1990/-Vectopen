//! Doc → SVG. Para convertir cualquier formato importado a SVG estándar
//! (Affinity → SVG) y para comprobar visualmente las importaciones.

use std::fmt::Write;

use crate::model::*;

fn hex(c: Rgba) -> String {
    let b = |v: f32| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
    format!("#{:02x}{:02x}{:02x}", b(c[0]), b(c[1]), b(c[2]))
}

fn d(subs: &[Sub]) -> String {
    let mut s = String::new();
    for sb in subs {
        let n = sb.anchors.len();
        for i in 0..n {
            let a = sb.anchors[i];
            if i == 0 {
                let _ = write!(s, "M{:.3} {:.3}", a[0], a[1]);
                continue;
            }
            seg(&mut s, sb, i - 1, i);
        }
        if sb.closed && n > 1 {
            seg(&mut s, sb, n - 1, 0);
            s.push('Z');
        }
    }
    s
}

fn seg(s: &mut String, sb: &Sub, i: usize, j: usize) {
    let (a, b) = (sb.anchors[i], sb.anchors[j]);
    let (o, n) = (sb.outs[i], sb.ins[j]);
    if o == [0.0, 0.0] && n == [0.0, 0.0] {
        let _ = write!(*s, "L{:.3} {:.3}", b[0], b[1]);
    } else {
        let _ = write!(*s, "C{:.3} {:.3} {:.3} {:.3} {:.3} {:.3}", a[0] + o[0], a[1] + o[1], b[0] + n[0], b[1] + n[1], b[0], b[1]);
    }
}

fn b64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len() * 4 / 3 + 4);
    for c in data.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        for k in 0..4 {
            if k <= c.len() {
                out.push(T[(n >> (18 - 6 * k) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

pub fn to_svg(doc: &Doc) -> String {
    let mut body = String::new();
    let mut gid = 0;
    write_items(&mut body, &doc.items, &mut gid);
    let mut s = String::new();
    let _ = writeln!(
        s,
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="{1}" viewBox="0 0 {0} {1}">"#,
        doc.size[0], doc.size[1]
    );
    s.push_str(&body);
    s.push_str("</svg>\n");
    s
}

fn write_items(s: &mut String, items: &[Item], gid: &mut usize) {
    for it in items {
        if let Item::Clip(mask, kids) = it {
            *gid += 1;
            let id = *gid;
            let _ = writeln!(*s, r#"<clipPath id="c{id}"><path d="{}"/></clipPath>"#, d(&mask.subs));
            write_items(s, &[Item::Path((**mask).clone())], gid);
            let _ = writeln!(*s, r#"<g clip-path="url(#c{id})">"#);
            write_items(s, kids, gid);
            s.push_str("</g>\n");
            continue;
        }
        write_one(s, it, gid);
    }
}

fn write_one(s: &mut String, it: &Item, gid: &mut usize) {
    {
        match it {
            Item::Path(p) => {
                let mut fill = p.fill.map(hex).unwrap_or_else(|| "none".into());
                let mut fo = p.fill.map(|c| c[3]).unwrap_or(1.0);
                if let Some(g) = &p.grad {
                    *gid += 1;
                    let (dx, dy) = (g.angle.cos() * 0.5, g.angle.sin() * 0.5);
                    let tagn = if g.radial { "radialGradient" } else { "linearGradient" };
                    let geo = if g.radial {
                        String::new()
                    } else {
                        format!(r#" x1="{}" y1="{}" x2="{}" y2="{}""#, 0.5 - dx, 0.5 - dy, 0.5 + dx, 0.5 + dy)
                    };
                    let _ = write!(*s, r#"<defs><{tagn} id="g{gid}"{geo}>"#);
                    for (o, c) in &g.stops {
                        let _ = write!(*s, r#"<stop offset="{o}" stop-color="{}" stop-opacity="{}"/>"#, hex(*c), c[3]);
                    }
                    let _ = write!(*s, "</{tagn}></defs>");
                    fill = format!("url(#g{gid})");
                    fo = 1.0;
                }
                let stroke = match p.stroke {
                    Some(c) => format!(r#" stroke="{}" stroke-opacity="{}" stroke-width="{}""#, hex(c), c[3], p.width),
                    None => String::new(),
                };
                let _ = writeln!(
                    *s,
                    r#"<path d="{}" fill="{fill}" fill-opacity="{fo}" fill-rule="{}" opacity="{}"{stroke}/>"#,
                    d(&p.subs),
                    if p.evenodd { "evenodd" } else { "nonzero" },
                    p.opacity
                );
            }
            Item::Image(im) => {
                let Some(buf) = image::RgbaImage::from_raw(im.width, im.height, im.rgba.clone()) else { return };
                let mut png = std::io::Cursor::new(Vec::new());
                if buf.write_to(&mut png, image::ImageFormat::Png).is_err() {
                    return;
                }
                let m = im.xf;
                let _ = writeln!(
                    *s,
                    r#"<image width="{}" height="{}" transform="matrix({} {} {} {} {} {})" opacity="{}" href="data:image/png;base64,{}"/>"#,
                    im.width, im.height, m.a, m.b, m.c, m.d, m.e, m.f, im.opacity, b64(png.get_ref())
                );
            }
            Item::Text(t) => {
                let m = t.xf;
                let esc = |x: &str| x.replace('&', "&amp;").replace('<', "&lt;");
                let anchor = match t.rich.as_ref().map(|r| r.align.as_str()) {
                    Some("center") => "middle",
                    Some("right") => "end",
                    _ => "start",
                };
                let ax = match (anchor, &t.rich) {
                    ("middle", Some(r)) => r.width / 2.0,
                    ("end", Some(r)) => r.width,
                    _ => 0.0,
                };
                let _ = write!(
                    s,
                    r#"<text transform="matrix({} {} {} {} {} {})" font-family="{}" font-size="{}" fill="{}" text-anchor="{anchor}" opacity="{}">"#,
                    m.a, m.b, m.c, m.d, m.e, m.f, t.family, t.size,
                    t.color.map(hex).unwrap_or_else(|| "#000".into()), t.opacity
                );
                // Tramos → <tspan>; cada salto de línea, una línea nueva.
                let chars: Vec<char> = t.text.chars().collect();
                let runs: Vec<(usize, Rgba, f32, i32)> = match &t.rich {
                    Some(r) if !r.runs.is_empty() => r.runs.iter().map(|x| (x.length, x.color, x.size, x.weight)).collect(),
                    _ => vec![(chars.len(), t.color.unwrap_or([0.0, 0.0, 0.0, 1.0]), t.size, if t.bold { 700 } else { 400 })],
                };
                let mut pos = 0;
                let mut line = 0;
                let mut new_line = true;
                for (len, c, size, w) in runs {
                    let seg: String = chars[pos.min(chars.len())..(pos + len).min(chars.len())].iter().collect();
                    pos += len;
                    for (k, part) in seg.split('\n').enumerate() {
                        if k > 0 {
                            line += 1;
                            new_line = true;
                        }
                        if part.is_empty() {
                            continue; // una línea vacía no se dibuja, pero el salto se mantiene
                        }
                        let pos_attr = if new_line {
                            new_line = false;
                            format!(r#" x="{ax}" y="{}""#, size * 0.85 + line as f32 * size * 1.2)
                        } else {
                            String::new()
                        };
                        let _ = write!(*s, r#"<tspan{pos_attr} fill="{}" fill-opacity="{}" font-size="{size}" font-weight="{w}">{}</tspan>"#, hex(c), c[3], esc(part));
                    }
                }
                s.push_str("</text>\n");
            }
            Item::Clip(..) => {}
        }
    }
}

/// Todas las páginas/artboards en un solo SVG, cada una en su posición (para
/// ver el documento entero, como la vista previa de Affinity).
pub fn to_svg_all(doc: &Doc) -> String {
    if doc.pages.is_empty() {
        return to_svg(doc);
    }
    let x0 = doc.pages.iter().map(|p| p.origin[0]).fold(f32::MAX, f32::min);
    let y0 = doc.pages.iter().map(|p| p.origin[1]).fold(f32::MAX, f32::min);
    let x1 = doc.pages.iter().map(|p| p.origin[0] + p.size[0]).fold(f32::MIN, f32::max);
    let y1 = doc.pages.iter().map(|p| p.origin[1] + p.size[1]).fold(f32::MIN, f32::max);
    let mut s = String::new();
    let _ = writeln!(s, r#"<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="{1}" viewBox="{x0} {y0} {0} {1}">"#, x1 - x0, y1 - y0);
    let mut gid = 0;
    for p in &doc.pages {
        let _ = writeln!(s, r#"<g transform="translate({} {})">"#, p.origin[0], p.origin[1]);
        if let Some(bg) = p.bg {
            let _ = writeln!(s, r#"<rect width="{}" height="{}" fill="{}" fill-opacity="{}"/>"#, p.size[0], p.size[1], hex(bg), bg[3]);
        }
        let mut body = String::new();
        write_items(&mut body, &p.items, &mut gid);
        s.push_str(&body);
        s.push_str("</g>\n");
    }
    s.push_str("</svg>\n");
    s
}
