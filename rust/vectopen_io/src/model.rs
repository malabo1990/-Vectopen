//! Documento importado, independiente de Godot (se prueba con `cargo test`).
//! Es el MISMO formato que producen svg_import.gd / ps_import.gd, para que
//! SvgImport.build() cree los mismos objetos editables con cualquiera de los dos.

use std::collections::BTreeSet;

pub type V2 = [f32; 2];
/// Color RGBA 0..1.
pub type Rgba = [f32; 4];

/// Transformación afín como la de Godot: x' = a·x + c·y + e ; y' = b·x + d·y + f.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Xf {
    pub a: f32,
    pub b: f32,
    pub c: f32,
    pub d: f32,
    pub e: f32,
    pub f: f32,
}

impl Xf {
    pub const IDENTITY: Xf = Xf { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0 };
    pub fn apply(&self, p: V2) -> V2 {
        [self.a * p[0] + self.c * p[1] + self.e, self.b * p[0] + self.d * p[1] + self.f]
    }
    /// Escala media (para grosores de trazo y discontinuos).
    pub fn scale(&self) -> f32 {
        (self.a * self.d - self.b * self.c).abs().sqrt()
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Sub {
    pub anchors: Vec<V2>,
    /// Asas relativas a su ancla (como Curve2D).
    pub ins: Vec<V2>,
    pub outs: Vec<V2>,
    pub closed: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Grad {
    pub radial: bool,
    /// Radianes, en el espacio final (y hacia abajo).
    pub angle: f32,
    pub stops: Vec<(f32, Rgba)>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PathItem {
    pub subs: Vec<Sub>,
    pub fill: Option<Rgba>,
    pub stroke: Option<Rgba>,
    pub grad: Option<Grad>,
    /// [trazo, hueco] ya escalados.
    pub dash: Option<[f32; 2]>,
    pub width: f32,
    /// 0 = plano, 1 = redondo, 2 = cuadrado.
    pub cap: i32,
    pub evenodd: bool,
    pub opacity: f32,
    pub name: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TextItem {
    pub text: String,
    /// Esquina superior izquierda de la caja de texto.
    pub xf: Xf,
    pub size: f32,
    pub color: Option<Rgba>,
    pub family: String,
    pub bold: bool,
    pub opacity: f32,
    /// Formato enriquecido (vacío = todo con el estilo de arriba).
    pub rich: Option<RichText>,
}

/// Texto con tramos de formato, párrafo con caja y alineación (como los
/// textos de Vectopen: meta «runs», «text_paragraph», «width», «text_align»).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct RichText {
    /// Párrafo con caja (ajusta líneas al ancho) o texto artístico (una línea por párrafo).
    pub paragraph: bool,
    pub width: f32,
    pub height: f32,
    /// "left" | "center" | "right" | "fill".
    pub align: String,
    pub weight: i32,
    pub italic: bool,
    pub runs: Vec<Run>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Run {
    /// Caracteres (puntos de código, como String.length() de Godot).
    pub length: usize,
    pub color: Rgba,
    pub size: f32,
    pub weight: i32,
    pub italic: bool,
    pub underline: bool,
    pub stroke: Option<(Rgba, f32)>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ImageItem {
    pub width: u32,
    pub height: u32,
    /// RGBA8, fila a fila.
    pub rgba: Vec<u8>,
    /// Píxel (0,0)-(w,h) → documento.
    pub xf: Xf,
    pub opacity: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Item {
    Path(PathItem),
    Text(TextItem),
    Image(ImageItem),
    /// Forma que RECORTA su contenido (y se dibuja también), como el «contenido
    /// dentro de una forma» de Affinity o los clipPath de SVG.
    Clip(Box<PathItem>, Vec<Item>),
}

/// Página o artboard de un documento con varios (Affinity, PDF de varias páginas…).
#[derive(Clone, Debug, Default)]
pub struct Page {
    pub name: String,
    /// Posición en el lienzo (para colocar los artboards como en el original).
    pub origin: V2,
    pub size: V2,
    /// Color de fondo (None = transparente).
    pub bg: Option<Rgba>,
    /// En coordenadas de la página (0,0 = esquina superior izquierda).
    pub items: Vec<Item>,
}

#[derive(Clone, Debug, Default)]
pub struct Doc {
    pub size: V2,
    /// Contenido de la PRIMERA página (o del documento si solo hay una).
    pub items: Vec<Item>,
    /// Todas las páginas/artboards si hay más de una (vacío si solo una).
    pub pages: Vec<Page>,
    /// Lo que no se pudo importar («texto», «recortes»…), sin repetir.
    pub warnings: BTreeSet<String>,
}

impl Doc {
    pub fn new(size: V2) -> Doc {
        Doc { size, items: Vec::new(), pages: Vec::new(), warnings: BTreeSet::new() }
    }
    /// Caja que ocupa todo el contenido (x0, y0, x1, y1), o None si está vacío.
    pub fn bounds(&self) -> Option<[f32; 4]> {
        let mut b = [f32::MAX, f32::MAX, f32::MIN, f32::MIN];
        let mut add = |p: V2| {
            b[0] = b[0].min(p[0]);
            b[1] = b[1].min(p[1]);
            b[2] = b[2].max(p[0]);
            b[3] = b[3].max(p[1]);
        };
        for it in &self.items {
            match it {
                Item::Path(p) => p.subs.iter().flat_map(|s| s.anchors.iter()).for_each(|a| add(*a)),
                Item::Image(im) => {
                    for c in [[0.0, 0.0], [im.width as f32, 0.0], [0.0, im.height as f32], [im.width as f32, im.height as f32]] {
                        add(im.xf.apply(c));
                    }
                }
                Item::Text(t) => add([t.xf.e, t.xf.f]),
                Item::Clip(m, _) => m.subs.iter().flat_map(|s| s.anchors.iter()).for_each(|a| add(*a)),
            }
        }
        (b[0] <= b[2]).then_some(b)
    }
    pub fn warn(&mut self, w: &str) {
        self.warnings.insert(w.to_string());
    }
}

/// Construye subtrazados Bézier (puerto de SvgImport._Builder).
#[derive(Default)]
pub struct Builder {
    pub subs: Vec<Sub>,
    cur: Sub,
}

impl Builder {
    pub fn move_to(&mut self, p: V2) {
        self.flush(false);
        self.push(p, [0.0; 2]);
    }
    pub fn line_to(&mut self, p: V2) {
        if self.cur.anchors.is_empty() {
            return self.move_to(p);
        }
        self.push(p, [0.0; 2]);
    }
    pub fn cubic_to(&mut self, c1: V2, c2: V2, p: V2) {
        if self.cur.anchors.is_empty() {
            self.move_to(c1);
        }
        let last = self.cur.anchors.len() - 1;
        let a = self.cur.anchors[last];
        self.cur.outs[last] = [c1[0] - a[0], c1[1] - a[1]];
        self.push(p, [c2[0] - p[0], c2[1] - p[1]]);
    }
    pub fn quad_to(&mut self, q: V2, p: V2) {
        let p0 = self.cur.anchors.last().copied().unwrap_or(q);
        let c1 = [p0[0] + 2.0 / 3.0 * (q[0] - p0[0]), p0[1] + 2.0 / 3.0 * (q[1] - p0[1])];
        let c2 = [p[0] + 2.0 / 3.0 * (q[0] - p[0]), p[1] + 2.0 / 3.0 * (q[1] - p[1])];
        self.cubic_to(c1, c2, p);
    }
    pub fn close(&mut self) {
        // Si el último punto repite el primero, se funden (cierre limpio).
        let n = self.cur.anchors.len();
        if n >= 2 && near(self.cur.anchors[n - 1], self.cur.anchors[0]) {
            self.cur.ins[0] = self.cur.ins[n - 1];
            self.cur.anchors.pop();
            self.cur.ins.pop();
            self.cur.outs.pop();
        }
        self.flush(true);
    }
    /// Último punto del subtrazado en curso.
    pub fn last(&self) -> Option<V2> {
        self.cur.anchors.last().copied()
    }
    pub fn finish(mut self) -> Vec<Sub> {
        self.flush(false);
        self.subs
    }
    fn push(&mut self, p: V2, inn: V2) {
        self.cur.anchors.push(p);
        self.cur.ins.push(inn);
        self.cur.outs.push([0.0; 2]);
    }
    fn flush(&mut self, closed: bool) {
        let mut s = std::mem::take(&mut self.cur);
        if s.anchors.len() >= 2 {
            s.closed = closed;
            self.subs.push(s);
        }
    }
}

fn near(a: V2, b: V2) -> bool {
    (a[0] - b[0]).abs() < 1e-4 && (a[1] - b[1]).abs() < 1e-4
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cierre_funde_el_punto_repetido() {
        let mut b = Builder::default();
        b.move_to([0.0, 0.0]);
        b.line_to([10.0, 0.0]);
        b.line_to([10.0, 10.0]);
        b.line_to([0.0, 0.0]);
        b.close();
        let s = b.finish();
        assert_eq!(s.len(), 1);
        assert!(s[0].closed);
        assert_eq!(s[0].anchors.len(), 3);
    }

    #[test]
    fn curva_guarda_asas_relativas() {
        let mut b = Builder::default();
        b.move_to([0.0, 0.0]);
        b.cubic_to([1.0, 2.0], [9.0, 2.0], [10.0, 0.0]);
        let s = b.finish();
        assert_eq!(s[0].outs[0], [1.0, 2.0]);
        assert_eq!(s[0].ins[1], [-1.0, 2.0]);
    }

    #[test]
    fn un_solo_punto_no_es_trazado() {
        let mut b = Builder::default();
        b.move_to([5.0, 5.0]);
        assert!(b.finish().is_empty());
    }
}
