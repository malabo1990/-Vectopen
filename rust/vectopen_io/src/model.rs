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
}

#[derive(Clone, Debug, Default)]
pub struct Doc {
    pub size: V2,
    pub items: Vec<Item>,
    /// Lo que no se pudo importar («texto», «recortes»…), sin repetir.
    pub warnings: BTreeSet<String>,
}

impl Doc {
    pub fn new(size: V2) -> Doc {
        Doc { size, items: Vec::new(), warnings: BTreeSet::new() }
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
