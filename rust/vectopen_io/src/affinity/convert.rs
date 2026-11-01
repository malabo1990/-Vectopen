//! Árbol de Affinity → Doc de Vectopen (el mismo formato que svg_import.gd).
//!
//! Se convierte: página (DocR.DfSz), grupos, curvas (PCrv), formas (ShpN:
//! rectángulo con esquinas redondeadas y elipse), relleno de color o
//! degradado, trazo con grosor, opacidad, visibilidad y matrices (Xfrm).
//! Lo que aún no, queda en `warnings` (texto, imágenes, efectos…).

use super::container::Archive;
use super::stream::{Doc as Tree, Obj, Val};
use crate::model::*;

pub fn convert(t: &Tree, archive: &Archive) -> Result<Doc, String> {
    let docn = t.obj(&t.root, "DocR").ok_or("el documento no tiene contenido")?;
    let size = match docn.get("DfSz") {
        Some(Val::Nums(n)) if n.len() >= 2 && n[0] > 0.0 && n[1] > 0.0 => [n[0] as f32, n[1] as f32],
        _ => [800.0, 600.0],
    };
    let mut doc = Doc::new(size);
    let spreads: Vec<&Obj> = children(t, docn).into_iter().filter(|o| o.is("Sprd")).collect();
    let mut pages: Vec<Page> = Vec::new();
    {
        let mut c = Conv { t, archive, doc: &mut doc, stories: Default::default(), origins: Vec::new(), depth: 0 };
        for (si, sp) in spreads.iter().enumerate() {
            let kids = children(t, sp);
            let is_ab = |k: &&Obj| k.is("ShpN") && matches!(k.get("ABEn"), Some(Val::Bool(true)));
            if kids.iter().any(is_ab) {
                // Artboards: cada uno, una página. Lo que quede fuera va al primero,
                // respetando el orden: lo de antes DEBAJO de su contenido y lo de
                // después ENCIMA.
                let first = pages.len();
                let (mut below, mut above) = (Vec::new(), Vec::new());
                for k in kids {
                    if is_ab(&k) {
                        if let Some(p) = c.artboard(k, pages.len() + 1) {
                            pages.push(p);
                        }
                    } else if pages.len() == first {
                        below.push(k);
                    } else {
                        above.push(k);
                    }
                }
                if pages.len() > first && !(below.is_empty() && above.is_empty()) {
                    c.doc.warn("objetos fuera de los artboards (en el primero)");
                    let o = c.origins.get(first).copied().unwrap_or([0.0, 0.0]);
                    let m = Xf { e: -o[0], f: -o[1], ..Xf::IDENTITY };
                    let lo = c.convert_list(below, m);
                    let hi = c.convert_list(above, m);
                    let page = &mut pages[first];
                    let mut items = lo;
                    items.append(&mut page.items);
                    items.extend(hi);
                    page.items = items;
                }
            } else {
                // Tamaño real del pliego (SprB): puede estar a otra resolución
                // que DfSz (p. ej. el doble) o ser más grande que la página.
                let (psize, off) = match nums(sp, "SprB") {
                    Some(b) if b.len() == 4 && b[2] > b[0] && b[3] > b[1] => {
                        ([(b[2] - b[0]) as f32, (b[3] - b[1]) as f32], Xf { e: -b[0] as f32, f: -b[1] as f32, ..Xf::IDENTITY })
                    }
                    _ => (size, Xf::IDENTITY),
                };
                let size = psize;
                let saved = std::mem::take(&mut c.doc.items);
                for k in kids {
                    c.node(k, off, 1.0);
                }
                let items = std::mem::replace(&mut c.doc.items, saved);
                let bg = t.obj(sp, "BgrC").and_then(|col| c.color(col)).filter(|b| b[3] > 0.0);
                // Páginas una al lado de otra, con 80 px de separación.
                let x = pages.iter().map(|p: &Page| p.origin[0] + p.size[0] + 80.0).fold(0.0, f32::max);
                pages.push(Page { name: format!("Página {}", si + 1), origin: [x, 0.0], size, bg, items });
            }
        }
    }
    if let Some(p0) = pages.first() {
        doc.size = p0.size;
        doc.items = p0.items.clone();
    }
    if pages.len() > 1 {
        doc.pages = pages;
    }
    Ok(doc)
}

struct Conv<'a> {
    t: &'a Tree,
    archive: &'a Archive<'a>,
    doc: &'a mut Doc,
    /// Historias ya colocadas: un texto enlazado entre varios marcos se
    /// importa una sola vez (en el primero).
    stories: std::collections::HashSet<usize>,
    /// Esquina de cada artboard ya creado (para recolocar objetos sueltos).
    origins: Vec<V2>,
    /// Profundidad actual: un archivo manipulado podría enlazar un hijo con su
    /// propio antepasado (bucle); se corta en vez de recurrir sin fin.
    depth: usize,
}

const MAX_LAYER_DEPTH: usize = 256;

/// Hijos («Chld») de un nodo, siguiendo enlaces.
fn children<'a>(t: &'a Tree, o: &'a Obj) -> Vec<&'a Obj> {
    let mut out = Vec::new();
    for v in o.all("Chld") {
        match v {
            Val::List(l) => out.extend(l.iter().filter_map(|x| t.deref(x))),
            other => out.extend(t.deref(other)),
        }
    }
    out
}

/// Primer objeto de un campo que puede ser objeto, enlace o lista.
fn first<'a>(t: &'a Tree, o: &'a Obj, f: &str) -> Option<&'a Obj> {
    match o.get(f)? {
        Val::List(l) => l.iter().find_map(|x| t.deref(x)),
        v => t.deref(v),
    }
}

fn num(o: &Obj, f: &str) -> Option<f64> {
    match o.get(f)? {
        Val::Float(v) => Some(*v),
        Val::Int(v) => Some(*v as f64),
        _ => None,
    }
}

fn nums<'a>(o: &'a Obj, f: &str) -> Option<&'a [f64]> {
    match o.get(f)? {
        Val::Nums(n) => Some(n),
        _ => None,
    }
}

/// Matriz de Affinity [a c tx ; b d ty].
fn xfrm(o: &Obj) -> Option<Xf> {
    let n = nums(o, "Xfrm")?;
    (n.len() == 6).then(|| Xf { a: n[0] as f32, c: n[1] as f32, e: n[2] as f32, b: n[3] as f32, d: n[4] as f32, f: n[5] as f32 })
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

fn f32s(b: &[u8]) -> Vec<f32> {
    b.chunks_exact(4).map(|c| f32::from_le_bytes(c.try_into().unwrap())).collect()
}

fn hsl(h: f32, s: f32, l: f32) -> [f32; 3] {
    if s <= 0.0 {
        return [l, l, l];
    }
    let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
    let p = 2.0 * l - q;
    let ch = |mut t: f32| {
        if t < 0.0 {
            t += 1.0
        }
        if t > 1.0 {
            t -= 1.0
        }
        if t < 1.0 / 6.0 {
            p + (q - p) * 6.0 * t
        } else if t < 0.5 {
            q
        } else if t < 2.0 / 3.0 {
            p + (q - p) * (2.0 / 3.0 - t) * 6.0
        } else {
            p
        }
    };
    [ch(h + 1.0 / 3.0), ch(h), ch(h - 1.0 / 3.0)]
}

impl<'a> Conv<'a> {
    fn color(&mut self, c: &Obj) -> Option<Rgba> {
        let Some(Val::Raw(raw)) = c.get("_col") else { return None };
        let v = f32s(raw);
        let cl = |x: f32| x.clamp(0.0, 1.0);
        match c.class().as_str() {
            "RGBA" if v.len() >= 4 => Some([cl(v[0]), cl(v[1]), cl(v[2]), cl(v[3])]),
            "HSLA" if v.len() >= 4 => {
                let [r, g, b] = hsl(v[0], cl(v[1]), cl(v[2]));
                Some([cl(r), cl(g), cl(b), cl(v[3])])
            }
            "CMYK" if v.len() >= 5 => {
                let k = 1.0 - cl(v[3]);
                Some([(1.0 - cl(v[0])) * k, (1.0 - cl(v[1])) * k, (1.0 - cl(v[2])) * k, cl(v[4])])
            }
            "GRAY" if v.len() >= 2 => Some([cl(v[0]), cl(v[0]), cl(v[0]), cl(v[1])]),
            other => {
                self.doc.warn(&format!("colores {other}"));
                Some([0.5, 0.5, 0.5, 1.0])
            }
        }
    }

    /// Relleno de un descriptor (FDsc): (color plano, degradado).
    fn fill(&mut self, fd: Option<&Obj>, xf: Xf) -> (Option<Rgba>, Option<Grad>) {
        let t = self.t;
        let Some(fd) = fd else { return (None, None) };
        let Some(def) = t.obj(fd, "FDeF") else { return (None, None) };
        match def.class().as_str() {
            "FilS" => (t.obj(def, "Colr").and_then(|c| self.color(c)), None),
            "FilG" => {
                let Some(g) = t.obj(def, "Grad") else { return (None, None) };
                let cols: Vec<&Obj> = match g.get("Cols") {
                    Some(Val::List(l)) => l.iter().filter_map(|x| t.deref(x)).collect(),
                    Some(v) => t.deref(v).into_iter().collect(),
                    None => Vec::new(),
                };
                let pos: Vec<f32> = match g.get("Posn") {
                    Some(Val::List(l)) => l.iter().map(|p| if let Val::Nums(n) = p { n[0] as f32 } else { 0.0 }).collect(),
                    _ => Vec::new(),
                };
                let mut stops = Vec::new();
                for (i, c) in cols.iter().enumerate() {
                    if let Some(col) = self.color(c) {
                        let o = pos.get(i).copied().unwrap_or(i as f32 / (cols.len().max(2) - 1) as f32);
                        stops.push((o.clamp(0.0, 1.0), col));
                    }
                }
                if stops.is_empty() {
                    return (None, None);
                }
                let radial = matches!(def.get("Type"), Some(Val::Enum(1)) | Some(Val::Enum(2)));
                // Dirección: eje x de la matriz del degradado (FDeX), llevada a la página.
                let angle = match nums(fd, "FDeX") {
                    Some(n) if n.len() == 6 => {
                        let gx = Xf { a: n[0] as f32, c: n[1] as f32, e: n[2] as f32, b: n[3] as f32, d: n[4] as f32, f: n[5] as f32 };
                        let m = mul(xf, gx);
                        m.b.atan2(m.a)
                    }
                    _ => 0.0,
                };
                let mid = {
                    let (a, b) = (stops[0].1, stops[stops.len() - 1].1);
                    [0, 1, 2, 3].map(|i| (a[i] + b[i]) * 0.5)
                };
                (Some(mid), Some(Grad { radial, angle, stops }))
            }
            "FilN" => (None, None),
            other => {
                self.doc.warn(&format!("rellenos {other}"));
                (None, None)
            }
        }
    }

    fn node(&mut self, o: &'a Obj, parent: Xf, opacity: f32) {
        let t = self.t;
        if matches!(o.get("Visi"), Some(Val::Bool(false))) {
            return;
        }
        if self.depth >= MAX_LAYER_DEPTH || self.doc.items.len() > 2_000_000 {
            self.doc.warn("capas anidadas demasiado profundas (se cortó)");
            return;
        }
        let xf = match xfrm(o) {
            Some(m) => mul(parent, m),
            None => parent,
        };
        let op = opacity * num(o, "Opac").unwrap_or(1.0) as f32;
        let class = o.class();
        let mut kids = children(t, o);
        let before = self.doc.items.len();
        match class.as_str() {
            "PCrv" => {
                let subs = curves(t, o, xf);
                self.shape(o, subs, xf, op);
            }
            "ShpN" => {
                let subs = self.parametric(o, xf);
                self.shape(o, subs, xf, op);
            }
            "TxtA" | "TxtF" => self.text(o, parent, op),
            "ImgN" | "Rstr" => self.bitmap(o, xf, op),
            "MPIN" => self.doc.warn("capas de píxeles especiales"),
            "EmbN" => self.doc.warn("documentos incrustados"),
            "Grup" | "Scop" | "Sprd" | "LogN" => {}
            c if c.ends_with("RA") => self.doc.warn("capas de ajuste"),
            other => self.doc.warn(&format!("capas {other}")),
        }
        // Hijos de una forma = contenido RECORTADO por ella (la forma se dibuja también).
        let clip_shape = matches!(class.as_str(), "PCrv" | "ShpN")
            && !kids.is_empty()
            && matches!(self.doc.items.last(), Some(Item::Path(_)))
            && self.doc.items.len() > before;
        if !clip_shape && matches!(class.as_str(), "PCrv" | "ShpN" | "ImgN" | "TxtA" | "TxtF") && !kids.is_empty() {
            self.doc.warn("recortes por imagen o texto (sin recortar)");
        }
        if let Some(Val::List(fx)) = o.get("FiEf") {
            if fx.iter().filter_map(|e| t.deref(e)).any(|e| matches!(e.get("Enab"), Some(Val::Bool(true)))) {
                self.doc.warn("efectos");
            }
        }
        self.depth += 1;
        if clip_shape {
            let Some(Item::Path(mask)) = self.doc.items.pop() else { unreachable!() };
            let saved = std::mem::take(&mut self.doc.items);
            for ch in kids.drain(..) {
                // El contenido hereda la posición de la forma, no su opacidad.
                self.node(ch, xf, 1.0);
            }
            let inner = std::mem::replace(&mut self.doc.items, saved);
            let mut mask = mask;
            let mop = mask.opacity;
            mask.opacity = 1.0;
            // La opacidad de la forma afecta a todo el conjunto.
            let inner = inner.into_iter().map(|it| with_opacity(it, mop)).collect();
            mask.opacity = mop;
            self.doc.items.push(Item::Clip(Box::new(mask), inner));
        } else {
            for ch in kids.drain(..) {
                self.node(ch, xf, op);
            }
        }
        self.depth -= 1;
    }

    fn shape(&mut self, o: &Obj, subs: Vec<Sub>, xf: Xf, op: f32) {
        let t = self.t;
        if subs.is_empty() {
            return;
        }
        let (fill, grad) = self.fill(first(t, o, "BFFl"), xf);
        let fo = num(o, "FOpc").unwrap_or(1.0) as f32;
        let fill = fill.map(|mut c| {
            c[3] *= fo;
            c
        });
        let (stroke_col, _) = self.fill(first(t, o, "LIFl"), xf);
        let width = first(t, o, "LILn")
            .and_then(|ld| t.obj(ld, "LDeL"))
            .and_then(|ls| num(ls, "Wght"))
            .unwrap_or(0.0) as f32;
        let stroke = if width > 0.0 { stroke_col } else { None };
        let name = match o.get("Desc") {
            Some(Val::Str(s)) if !s.is_empty() => s.clone(),
            _ => if o.is("ShpN") { "Forma".to_string() } else { "Trazado".to_string() },
        };
        self.doc.items.push(Item::Path(PathItem {
            subs,
            fill,
            stroke,
            grad,
            dash: None,
            width: if stroke.is_some() { width } else { 0.0 },
            cap: 0,
            evenodd: false,
            opacity: op,
            name,
        }));
    }

    /// Formas paramétricas (ShpN) → curvas. Caja local ShpB = (x0, y0, x1, y1).
    fn parametric(&mut self, o: &Obj, xf: Xf) -> Vec<Sub> {
        let t = self.t;
        let Some(b) = nums(o, "ShpB").filter(|b| b.len() == 4) else { return Vec::new() };
        let (x0, y0, x1, y1) = (b[0] as f32, b[1] as f32, b[2] as f32, b[3] as f32);
        let Some(sh) = t.obj(o, "Shpe") else { return Vec::new() };
        let mut bl = Builder::default();
        let p = |x: f32, y: f32| xf.apply([x, y]);
        const K: f32 = 0.552_284_8;
        match sh.class().as_str() {
            "ShpE" => {
                let (cx, cy, rx, ry) = ((x0 + x1) / 2.0, (y0 + y1) / 2.0, (x1 - x0) / 2.0, (y1 - y0) / 2.0);
                bl.move_to(p(cx + rx, cy));
                bl.cubic_to(p(cx + rx, cy + ry * K), p(cx + rx * K, cy + ry), p(cx, cy + ry));
                bl.cubic_to(p(cx - rx * K, cy + ry), p(cx - rx, cy + ry * K), p(cx - rx, cy));
                bl.cubic_to(p(cx - rx, cy - ry * K), p(cx - rx * K, cy - ry), p(cx, cy - ry));
                bl.cubic_to(p(cx + rx * K, cy - ry), p(cx + rx, cy - ry * K), p(cx + rx, cy));
                bl.close();
            }
            c => {
                if c != "ShNR" {
                    self.doc.warn("formas especiales (como su caja)");
                }
                // Radios de esquina: fracción del lado menor/2 (o absolutos si AbSz).
                let half = ((x1 - x0).abs().min((y1 - y0).abs())) / 2.0;
                let abs = matches!(sh.get("AbSz"), Some(Val::Bool(true)));
                let mut r = match sh.get("ShCR") {
                    Some(Val::Nums(n)) if n.len() == 4 && c == "ShNR" => [n[0], n[1], n[2], n[3]].map(|v| {
                        let v = v as f32;
                        (if abs { v } else { v * half }).clamp(0.0, half)
                    }),
                    _ => [0.0; 4],
                };
                // Tipo de cada esquina (CTyp): 0 = recta; otros = redondeada
                // (biselada, cóncava… se aproximan como redondeadas).
                let types: Vec<u16> = match sh.get("CTyp") {
                    Some(Val::List(l)) => l.iter().map(|v| if let Val::Enum(e) = v { *e } else { 0 }).collect(),
                    _ => vec![0; 4],
                };
                for (i, ri) in r.iter_mut().enumerate() {
                    match types.get(i).copied().unwrap_or(0) {
                        0 => *ri = 0.0,
                        1 => {}
                        _ => self.doc.warn("esquinas especiales (como redondeadas)"),
                    }
                }
                let [tl, tr, br, blr] = r;
                bl.move_to(p(x0 + tl, y0));
                bl.line_to(p(x1 - tr, y0));
                if tr > 0.0 {
                    bl.cubic_to(p(x1 - tr + tr * K, y0), p(x1, y0 + tr - tr * K), p(x1, y0 + tr));
                }
                bl.line_to(p(x1, y1 - br));
                if br > 0.0 {
                    bl.cubic_to(p(x1, y1 - br + br * K), p(x1 - br + br * K, y1), p(x1 - br, y1));
                }
                bl.line_to(p(x0 + blr, y1));
                if blr > 0.0 {
                    bl.cubic_to(p(x0 + blr - blr * K, y1), p(x0, y1 - blr + blr * K), p(x0, y1 - blr));
                }
                bl.line_to(p(x0, y0 + tl));
                if tl > 0.0 {
                    bl.cubic_to(p(x0, y0 + tl - tl * K), p(x0 + tl - tl * K, y0), p(x0 + tl, y0));
                }
                bl.close();
            }
        }
        bl.finish()
    }
}

/// Curvas de un PCrv: Crvs → Data (uno o varios subtrazados). Cada punto es
/// un registro de 18 bytes: x, y (f64) + tipo de ancla + tipo de asa
/// (0 = ancla, 1 = asa de salida, 2 = asa de entrada).
fn curves(t: &Tree, o: &Obj, xf: Xf) -> Vec<Sub> {
    let mut out = Vec::new();
    let Some(cv) = t.obj(o, "Crvs") else { return out };
    let datas: Vec<&Obj> = match cv.get("Data") {
        Some(Val::List(l)) => l.iter().filter_map(|x| t.deref(x)).collect(),
        Some(v) => t.deref(v).into_iter().collect(),
        None => Vec::new(),
    };
    for d in datas {
        let mut closed = false;
        let mut recs: Option<(u16, &[u8])> = None;
        for (_, v) in &d.fields {
            match v {
                Val::Bool(b) => closed = *b,
                Val::Records(sz, data) => recs = Some((*sz, data)),
                _ => {}
            }
        }
        let Some((18, data)) = recs else { continue };
        let mut bl = Builder::default();
        let (mut c1, mut c2): (Option<V2>, Option<V2>) = (None, None);
        let mut started = false;
        for r in data.chunks_exact(18) {
            let x = f64::from_le_bytes(r[0..8].try_into().unwrap()) as f32;
            let y = f64::from_le_bytes(r[8..16].try_into().unwrap()) as f32;
            let pt = xf.apply([x, y]);
            match r[17] {
                1 => c1 = Some(pt),
                2 => c2 = Some(pt),
                _ => {
                    if !started {
                        bl.move_to(pt);
                        started = true;
                    } else if c1.is_some() || c2.is_some() {
                        let prev = bl_last(&bl).unwrap_or(pt);
                        bl.cubic_to(c1.unwrap_or(prev), c2.unwrap_or(pt), pt);
                    } else {
                        bl.line_to(pt);
                    }
                    c1 = None;
                    c2 = None;
                }
            }
        }
        if closed {
            bl.close();
        }
        out.extend(bl.finish());
    }
    out
}

fn bl_last(b: &Builder) -> Option<V2> {
    b.last()
}

fn list<'a>(t: &'a Tree, v: Option<&'a Val>) -> Vec<&'a Obj> {
    match v {
        Some(Val::List(l)) => l.iter().filter_map(|x| t.deref(x)).collect(),
        Some(v) => t.deref(v).into_iter().collect(),
        None => Vec::new(),
    }
}

fn floats(o: &Obj, f: &str) -> Vec<f64> {
    match o.get(f) {
        Some(Val::List(l)) => l.iter().map(|v| match v { Val::Float(x) => *x, Val::Int(x) => *x as f64, _ => 0.0 }).collect(),
        _ => Vec::new(),
    }
}

fn ints(o: &Obj, f: &str) -> Vec<i64> {
    match o.get(f) {
        Some(Val::List(l)) => l.iter().map(|v| match v { Val::Int(x) => *x, Val::Float(x) => *x as i64, _ => 0 }).collect(),
        _ => Vec::new(),
    }
}

fn s_of(o: &Obj, f: &str) -> String {
    match o.get(f) {
        Some(Val::Str(s)) => s.clone(),
        _ => String::new(),
    }
}

impl<'a> Conv<'a> {
    /// Texto artístico (TxtA) o en marco (TxtF) → texto editable de Vectopen.
    fn text(&mut self, o: &'a Obj, parent: Xf, op: f32) {
        let t = self.t;
        let Some(story) = t.obj(o, "StSt") else { return };
        if !self.stories.insert(story as *const Obj as usize) {
            return; // continuación de un texto enlazado ya importado
        }
        // Historia: uno o varios bloques con el texto (Utf8) y sus tramos.
        let mut text = String::new();
        let mut runs: Vec<Run> = Vec::new();
        let mut align = "left";
        let mut first_style: Option<(f32, String, i32, bool)> = None;
        for blk in list(t, story.get("Blok")) {
            let base = text.chars().count();
            let raw = t.obj(blk, "Glyp").map(|g| s_of(g, "Utf8")).unwrap_or_default();
            let raw = raw.trim_end_matches('\0');
            let mut pos = 0usize;
            for run in t.obj(blk, "GAtt").map(|ga| list(t, ga.get("Runs"))).unwrap_or_default() {
                let end = num(run, "Indx").unwrap_or(0.0).max(0.0) as usize;
                let Some(item) = t.obj(run, "Item") else { continue };
                let size = floats(item, "Doub").first().copied().unwrap_or(12.0) as f32;
                let font = t.obj(item, "DFnt");
                let family = font.map(|f| s_of(f, "Famy")).unwrap_or_default();
                let weight = font.and_then(|f| num(f, "Wegt")).unwrap_or(400.0) as i32;
                let italic = font.map(|f| matches!(f.get("Ital"), Some(Val::Bool(true)))).unwrap_or(false);
                let objs = list(t, item.get("Objs"));
                let (fill, _) = self.fill(objs.first().copied(), Xf::IDENTITY);
                let (stroke_col, _) = self.fill(objs.get(1).copied(), Xf::IDENTITY);
                let stroke_w = objs.get(2).and_then(|ld| t.obj(ld, "LDeL")).and_then(|ls| num(ls, "Wght")).unwrap_or(0.0) as f32;
                if first_style.is_none() {
                    first_style = Some((size, family.clone(), weight, italic));
                }
                let len = end.saturating_sub(pos);
                pos = pos.max(end);
                if len == 0 {
                    continue;
                }
                runs.push(Run {
                    length: len,
                    color: fill.unwrap_or([0.0, 0.0, 0.0, 1.0]),
                    size,
                    weight,
                    italic,
                    underline: false,
                    stroke: match (stroke_col, stroke_w > 0.0) {
                        (Some(c), true) => Some((c, stroke_w)),
                        _ => None,
                    },
                });
            }
            if let Some(pa) = t.obj(blk, "PAtt").and_then(|pa| list(t, pa.get("Runs")).into_iter().next()).and_then(|r| t.obj(r, "Item")) {
                align = match ints(pa, "Ints").first().copied().unwrap_or(0) {
                    1 => "center",
                    2 => "right",
                    3..=6 => "fill",
                    _ => "left",
                };
            }
            if !text.is_empty() && !raw.is_empty() {
                text.push('\n');
                if let Some(last) = runs.last_mut() {
                    last.length += 1;
                }
            }
            let _ = base;
            text.push_str(&raw.replace(['\u{2029}', '\u{2028}'], "\n").replace('\r', "\n"));
        }
        // Los tramos deben sumar exactamente la longitud del texto.
        let n = text.chars().count();
        let mut total = 0;
        runs.retain_mut(|r| {
            if total >= n {
                return false;
            }
            r.length = r.length.min(n - total);
            total += r.length;
            true
        });
        if total < n {
            if let Some(last) = runs.last_mut() {
                last.length += n - total;
            }
        }
        if text.trim().is_empty() {
            return;
        }
        let (size, family, weight, italic) = first_style.unwrap_or((12.0, String::new(), 400, false));
        // Caja: FrmB del marco (TxtH), en el espacio del nodo.
        let frame = t.obj(o, "TxtH");
        let paragraph = frame.map(|f| !f.is("ArFr")).unwrap_or(false);
        let fb = frame.and_then(|f| nums(f, "FrmB")).filter(|b| b.len() == 4).map(|b| [b[0] as f32, b[1] as f32, b[2] as f32, b[3] as f32]);
        let own = xfrm(o).unwrap_or(Xf::IDENTITY);
        let m = mul(parent, own);
        let [x0, y0, x1, y1] = fb.unwrap_or([0.0, 0.0, 0.0, 0.0]);
        let origin = m.apply([x0, y0]);
        // Escala del TEXTO: en los marcos la da FTxS (el marco puede estirarse
        // sin deformar las letras); en el artístico, la matriz del nodo.
        let tx = match nums(o, "FTxS") {
            Some(n) if n.len() == 6 => mul(parent, Xf { a: n[0] as f32, c: n[1] as f32, e: 0.0, b: n[3] as f32, d: n[4] as f32, f: 0.0 }),
            _ => m,
        };
        let k = tx.scale().max(1e-6);
        let xf = Xf { e: origin[0], f: origin[1], ..tx };
        let (w, h) = {
            let a = m.apply([x0, y0]);
            let b = m.apply([x1, y0]);
            let c = m.apply([x0, y1]);
            (((b[0] - a[0]).hypot(b[1] - a[1])) / k, ((c[0] - a[0]).hypot(c[1] - a[1])) / k)
        };
        let color = runs.first().map(|r| r.color);
        self.doc.items.push(Item::Text(TextItem {
            text,
            xf,
            size,
            color,
            family,
            bold: weight >= 600,
            opacity: op,
            rich: Some(RichText { paragraph, width: w, height: h, align: align.into(), weight, italic, runs }),
        }));
        if matches!(o.get("TxtH"), Some(_)) && frame.map(|f| f.is("PaFr") || f.is("PthT")).unwrap_or(false) {
            self.doc.warn("texto en trazado (como texto normal)");
        }
    }
}

impl<'a> Conv<'a> {
    /// Imagen colocada (ImgN) o capa de píxeles (Rstr): sus mosaicos → imagen.
    fn bitmap(&mut self, o: &'a Obj, xf: Xf, op: f32) {
        let t = self.t;
        let Some(bm) = t.obj(o, "Bitm") else {
            self.doc.warn("imágenes sin datos");
            return;
        };
        if matches!(bm.get("Frmt"), Some(Val::Enum(6))) {
            self.doc.warn("máscaras de píxeles");
            return;
        }
        // Imagen colocada con su ORIGINAL guardado (Bckg → «c/N»: un Blck con
        // el PNG/JPEG tal cual): máxima calidad, sin depender de los mosaicos.
        if let Some(Val::Str(name)) = bm.get("Bckg") {
            if let Some(im) = self.archive.read(name).ok().and_then(|b| super::stream::parse(&b).ok()).and_then(|blk| match blk.root.get("Data") {
                Some(Val::Raw(r)) => crate::raster::decode(r).ok(),
                _ => None,
            }) {
                let (bw, bh) = (num(bm, "BmpW").unwrap_or(im.width as f64) as f32, num(bm, "BmpH").unwrap_or(im.height as f64) as f32);
                let s = Xf { a: bw / im.width as f32, d: bh / im.height as f32, ..Xf::IDENTITY };
                self.doc.items.push(Item::Image(ImageItem { width: im.width, height: im.height, rgba: im.data, xf: mul(xf, s), opacity: op }));
                return;
            }
        }
        match super::bitmap::decode(self.archive, t, bm) {
            Ok((im, k)) => {
                if im.data.chunks_exact(4).all(|p| p[3] == 0) {
                    return; // capa vacía
                }
                let s = Xf { a: k, d: k, ..Xf::IDENTITY };
                self.doc.items.push(Item::Image(ImageItem { width: im.width, height: im.height, rgba: im.data, xf: mul(xf, s), opacity: op }));
            }
            Err(e) => self.doc.warn(&format!("imágenes ({e})")),
        }
    }
}

fn with_opacity(it: Item, k: f32) -> Item {
    if (k - 1.0).abs() < 1e-6 {
        return it;
    }
    match it {
        Item::Path(mut p) => {
            p.opacity *= k;
            Item::Path(p)
        }
        Item::Text(mut t) => {
            t.opacity *= k;
            Item::Text(t)
        }
        Item::Image(mut i) => {
            i.opacity *= k;
            Item::Image(i)
        }
        Item::Clip(m, kids) => Item::Clip(m, kids.into_iter().map(|c| with_opacity(c, k)).collect()),
    }
}

impl<'a> Conv<'a> {
    /// Artboard (ShpN con ABEn) → página con su tamaño, fondo y contenido.
    fn artboard(&mut self, k: &'a Obj, n: usize) -> Option<Page> {
        let t = self.t;
        let b = nums(k, "ShpB").filter(|b| b.len() == 4)?;
        let m = xfrm(k).unwrap_or(Xf::IDENTITY);
        let corners = [[b[0], b[1]], [b[2], b[1]], [b[0], b[3]], [b[2], b[3]]].map(|p| m.apply([p[0] as f32, p[1] as f32]));
        let x0 = corners.iter().map(|p| p[0]).fold(f32::MAX, f32::min);
        let y0 = corners.iter().map(|p| p[1]).fold(f32::MAX, f32::min);
        let x1 = corners.iter().map(|p| p[0]).fold(f32::MIN, f32::max);
        let y1 = corners.iter().map(|p| p[1]).fold(f32::MIN, f32::max);
        if !(x1 > x0 && y1 > y0) {
            return None;
        }
        self.origins.push([x0, y0]);
        let (bg, _) = self.fill(first(t, k, "BFFl"), m);
        let name = match k.get("Desc") {
            Some(Val::Str(s)) if !s.is_empty() => s.clone(),
            _ => format!("Artboard {n}"),
        };
        // Contenido en coordenadas del artboard.
        let to_page = mul(Xf { e: -x0, f: -y0, ..Xf::IDENTITY }, m);
        let saved = std::mem::take(&mut self.doc.items);
        let op = num(k, "Opac").unwrap_or(1.0) as f32;
        for ch in children(t, k) {
            self.node(ch, to_page, op);
        }
        let items = std::mem::replace(&mut self.doc.items, saved);
        Some(Page { name, origin: [x0, y0], size: [x1 - x0, y1 - y0], bg: bg.filter(|c| c[3] > 0.0), items })
    }
}

impl<'a> Conv<'a> {
    /// Convierte una lista de nodos aparte y devuelve sus elementos.
    fn convert_list(&mut self, list: Vec<&'a Obj>, m: Xf) -> Vec<Item> {
        let saved = std::mem::take(&mut self.doc.items);
        for k in list {
            self.node(k, m, 1.0);
        }
        std::mem::replace(&mut self.doc.items, saved)
    }
}
