//! Malla del trazo de pincel (VGSE): traducción NATIVA de
//! `StrokeGeom._halves` (script_gdscript/shapes/stroke_geom.gd) y sus
//! auxiliares (_trim_ends, _side, _arc, _cut_loops, _next_backtrack, _fan).
//!
//! Mismo resultado que el GDScript (que sigue de respaldo si esta librería
//! no carga), entre 20 y 50 veces más rápido: con un trazo largo el GDScript
//! tardaba ~8 ms por punto nuevo mientras se dibujaba.
//!
//! Rust puro (sin Godot): se prueba con `cargo test`.

use std::f32::consts::PI;

const CMP_EPSILON: f32 = 0.00001;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct V {
    pub x: f32,
    pub y: f32,
}

impl V {
    pub fn new(x: f32, y: f32) -> V {
        V { x, y }
    }
    fn add(self, o: V) -> V {
        V::new(self.x + o.x, self.y + o.y)
    }
    fn sub(self, o: V) -> V {
        V::new(self.x - o.x, self.y - o.y)
    }
    fn mul(self, s: f32) -> V {
        V::new(self.x * s, self.y * s)
    }
    fn dot(self, o: V) -> f32 {
        self.x * o.x + self.y * o.y
    }
    fn cross(self, o: V) -> f32 {
        self.x * o.y - self.y * o.x
    }
    fn len_sq(self) -> f32 {
        self.x * self.x + self.y * self.y
    }
    fn len(self) -> f32 {
        self.len_sq().sqrt()
    }
    fn dist(self, o: V) -> f32 {
        self.sub(o).len()
    }
    /// Como Vector2.normalized() de Godot: (0,0) si la longitud es 0.
    fn norm(self) -> V {
        let l = self.len_sq();
        if l == 0.0 {
            return V::default();
        }
        let l = l.sqrt();
        V::new(self.x / l, self.y / l)
    }
    fn angle(self) -> f32 {
        self.y.atan2(self.x)
    }
    /// Vector2(-y, x)
    fn perp(self) -> V {
        V::new(-self.y, self.x)
    }
}

fn is_equal_approx(a: f32, b: f32) -> bool {
    if a == b {
        return true;
    }
    let mut tol = CMP_EPSILON * a.abs();
    if tol < CMP_EPSILON {
        tol = CMP_EPSILON;
    }
    (a - b).abs() < tol
}

fn wrapf(value: f32, min: f32, max: f32) -> f32 {
    let range = max - min;
    if range.abs() < CMP_EPSILON {
        return min;
    }
    let result = value - range * ((value - min) / range).floor();
    if is_equal_approx(result, max) {
        return min;
    }
    result
}

/// Geometry2D.segment_intersects_segment de Godot.
fn seg_intersect(fa: V, ta: V, fb: V, tb: V) -> Option<V> {
    let b = ta.sub(fa);
    let mut c = fb.sub(fa);
    let mut d = tb.sub(fa);
    let ab_len = b.dot(b);
    if ab_len <= 0.0 {
        return None;
    }
    let bn = b.mul(1.0 / ab_len);
    c = V::new(c.x * bn.x + c.y * bn.y, c.y * bn.x - c.x * bn.y);
    d = V::new(d.x * bn.x + d.y * bn.y, d.y * bn.x - d.x * bn.y);
    if (c.y < -CMP_EPSILON && d.y < -CMP_EPSILON) || (c.y > CMP_EPSILON && d.y > CMP_EPSILON) {
        return None;
    }
    if is_equal_approx(c.y, d.y) {
        return None;
    }
    let ab_pos = d.x + (c.x - d.x) * d.y / (d.y - c.y);
    if !(0.0..=1.0).contains(&ab_pos) {
        return None;
    }
    Some(fa.add(b.mul(ab_pos)))
}

#[derive(Default, Debug)]
pub struct Mesh {
    pub points: Vec<V>,
    pub indices: Vec<i32>,
    pub v: Vec<f32>,
    pub k: Vec<i32>,
    pub beyond: Vec<f32>,
}

#[derive(Clone, Copy, Debug)]
struct E {
    p: V,
    o: i32,
}

fn cumulative(pts: &[V]) -> Vec<f32> {
    let mut cum = vec![0.0f32; pts.len()];
    for i in 1..pts.len() {
        cum[i] = cum[i - 1] + pts[i].dist(pts[i - 1]);
    }
    cum
}

fn trim_ends(pts: Vec<V>, half: Vec<f32>) -> (Vec<V>, Vec<f32>) {
    let n = pts.len();
    if n <= 3 {
        return (pts, half);
    }
    let cum = cumulative(&pts);
    let total = cum[n - 1];
    let ws = (half[0] * 1.5).min(total * 0.25);
    let we = (half[n - 1] * 1.5).min(total * 0.25);
    let mut op = vec![pts[0]];
    let mut oh = vec![half[0]];
    for i in 1..n - 1 {
        if cum[i] >= ws && total - cum[i] >= we {
            op.push(pts[i]);
            oh.push(half[i]);
        }
    }
    op.push(pts[n - 1]);
    oh.push(half[n - 1]);
    if op.len() >= 2 {
        (op, oh)
    } else {
        (pts, half)
    }
}

fn arc(c: V, a: V, b: V) -> Vec<V> {
    let r = a.len();
    let a0 = a.angle();
    let sweep = wrapf(b.angle() - a0, -PI, PI);
    let segs = ((sweep.abs() / PI * (r * 0.8 + 16.0).clamp(16.0, 48.0)) as i32).clamp(2, 48);
    (0..=segs)
        .map(|k| {
            let t = a0 + sweep * k as f32 / segs as f32;
            c.add(V::new(t.cos(), t.sin()).mul(r))
        })
        .collect()
}

fn side(pts: &[V], half: &[f32], sgn: f32) -> Vec<E> {
    let n = pts.len();
    let mut out = Vec::with_capacity(n + 16);
    for i in 0..n {
        let d0 = if i > 0 { pts[i].sub(pts[i - 1]).norm() } else { pts[1].sub(pts[0]).norm() };
        let d1 = if i < n - 1 { pts[i + 1].sub(pts[i]).norm() } else { d0 };
        let n0 = d0.perp().mul(sgn);
        let n1 = d1.perp().mul(sgn);
        let h = half[i];
        let mut mdir = n0.add(n1);
        let outer = d0.cross(d1) * sgn < 0.0;
        let o = i as i32;
        if mdir.len_sq() < 1e-8 {
            out.push(E { p: pts[i].add(n0.mul(h)), o });
            out.push(E { p: pts[i].add(n1.mul(h)), o });
            continue;
        }
        mdir = mdir.norm();
        let mlen = h / mdir.dot(n1).max(0.0001);
        if outer && mlen > h * 1.02 {
            for q in arc(pts[i], n0.mul(h), n1.mul(h)) {
                out.push(E { p: q, o });
            }
        } else {
            let mut reach = pts[i]
                .dist(pts[i.saturating_sub(1)])
                .min(pts[i].dist(pts[(i + 1).min(n - 1)]));
            if i == 0 || i == n - 1 {
                reach = h;
            }
            out.push(E { p: pts[i].add(mdir.mul(mlen.min((h * h + reach * reach).sqrt()))), o });
        }
    }
    out
}

fn next_backtrack(side: &[E], axis: &[V]) -> Vec<i32> {
    let n = side.len();
    let mut nxt = vec![-1i32; n];
    let mut nextr = -1i32;
    for q in (0..n).rev() {
        let mut back = true;
        if axis.len() >= 2 && q < n - 1 {
            let o = side[q].o as usize;
            let ad = axis[(o + 1).min(axis.len() - 1)].sub(axis[o.saturating_sub(1)]);
            back = side[q + 1].p.sub(side[q].p).dot(ad) < 0.0;
        } else if q == n - 1 {
            back = false;
        }
        if back {
            nextr = q as i32;
        }
        nxt[q] = nextr;
    }
    nxt
}

fn cut_loops(side: &[E], cum: &[f32], half: &[f32], axis: &[V]) -> Vec<E> {
    let n = side.len();
    let nxt = next_backtrack(side, axis);
    let mut out = Vec::with_capacity(n);
    let mut i = 0usize;
    while i < n {
        out.push(side[i]);
        if i + 3 >= n {
            i += 1;
            continue;
        }
        let r = nxt[i];
        if r < 0 {
            out.extend_from_slice(&side[i + 1..]);
            break;
        }
        let c0 = cum[side[i].o as usize];
        let reach = half[side[i].o as usize] * 4.0 + 1.0;
        if cum[side[r as usize].o as usize] - c0 > reach {
            i += 1;
            continue;
        }
        let a = side[i].p;
        let b = side[i + 1].p;
        let mut hit: Option<(usize, V)> = None;
        let mut j = i + 2;
        while j < n - 1 && cum[side[j].o as usize] - c0 <= reach {
            if let Some(x) = seg_intersect(a, b, side[j].p, side[j + 1].p) {
                hit = Some((j, x));
            }
            j += 1;
        }
        if let Some((hj, x)) = hit {
            out.push(E { p: x, o: side[i + 1].o });
            i = hj + 1;
            continue;
        }
        i += 1;
    }
    out
}

fn fan(m: &mut Mesh, c: V, dir: V, r: f32) {
    if r < 0.0005 || dir.len_sq() < 1e-12 {
        return;
    }
    let a0 = dir.norm().angle() - PI * 0.5;
    let segs = ((r * 0.8) as i32 + 16).clamp(16, 48);
    let ci = m.points.len() as i32;
    m.points.push(c);
    for k in 0..=segs {
        let a = a0 + PI * k as f32 / segs as f32;
        m.points.push(c.add(V::new(a.cos(), a.sin()).mul(r)));
    }
    for k in 0..segs {
        m.indices.extend_from_slice(&[ci, ci + 1 + k, ci + 2 + k]);
    }
    m.v.push(0.5);
    for _ in 0..=segs {
        m.v.push(1.0);
    }
}

/// `StrokeGeom._halves`: tira de grosor variable en dos mitades (eje ↔
/// borde) sin lazos en el lado interior, con remates (0 plano, 1 redondo,
/// 2 cuadrado). Devuelve puntos, índices, v (a través), k (punto del eje de
/// cada vértice) y beyond (cuánto pasa del extremo en los remates).
pub fn halves(pts_in: &[V], half_in: &[f32], cap_s: i32, cap_e: i32) -> Mesh {
    let mut m = Mesh::default();
    let mut pts = pts_in.to_vec();
    let half = half_in.to_vec();
    let n = pts.len();
    if n < 2 || half.len() < n {
        return m;
    }
    if cap_s == 2 {
        pts[0] = pts[0].add(pts[0].sub(pts[1]).norm().mul(half[0]));
    }
    if cap_e == 2 {
        pts[n - 1] = pts[n - 1].add(pts[n - 1].sub(pts[n - 2]).norm().mul(half[n - 1]));
    }
    let (pts, half) = trim_ends(pts, half);
    let n = pts.len();
    let cum = cumulative(&pts);
    let d_s = pts[1].sub(pts[0]).norm();
    let d_e = pts[n - 1].sub(pts[n - 2]).norm();
    let sides = [side(&pts, &half, 1.0), side(&pts, &half, -1.0)];
    let axis0 = 0i32;
    for (i, p) in pts.iter().enumerate() {
        m.points.push(*p);
        m.v.push(0.5);
        m.k.push(i as i32);
    }
    for (si, raw) in sides.iter().enumerate() {
        let sd = cut_loops(raw, &cum, &half, &pts);
        let sv = if si == 0 { 0.0 } else { 1.0 };
        let base = m.points.len() as i32;
        for e in &sd {
            m.points.push(e.p);
            m.v.push(sv);
            m.k.push(e.o);
        }
        // Cremallera eje ↔ borde (los dueños del borde no decrecen).
        let mut k = 0i32;
        let mut o = sd[0].o;
        let last = sd.len() as i32 - 1;
        loop {
            if k < last && sd[(k + 1) as usize].o <= o {
                m.indices.extend_from_slice(&[axis0 + o, base + k, base + k + 1]);
                k += 1;
            } else if o < n as i32 - 1 {
                m.indices.extend_from_slice(&[base + k, axis0 + o, axis0 + o + 1]);
                o += 1;
            } else if k < last {
                m.indices.extend_from_slice(&[axis0 + o, base + k, base + k + 1]);
                k += 1;
            } else {
                break;
            }
        }
    }
    m.beyond = vec![0.0; m.k.len()];
    for (cap, ki, cdir) in [(cap_s, 0usize, d_s.mul(-1.0)), (cap_e, n - 1, d_e)] {
        if cap != 1 {
            continue;
        }
        let c0 = m.points.len();
        let dir = cdir.norm();
        fan(&mut m, pts[ki], cdir, half[ki]);
        for q in c0..m.points.len() {
            m.k.push(ki as i32);
            m.beyond.push(m.points[q].sub(pts[ki]).dot(dir).max(0.0));
        }
    }
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    fn line(n: usize, f: impl Fn(f32) -> V) -> Vec<V> {
        (0..n).map(|i| f(i as f32)).collect()
    }

    #[test]
    fn tramo_recto_da_una_tira_con_remates() {
        let pts = line(20, |i| V::new(i * 2.0, 0.0));
        let half = vec![3.0; 20];
        let m = halves(&pts, &half, 1, 1);
        assert_eq!(m.points.len(), m.v.len());
        assert_eq!(m.points.len(), m.k.len());
        assert_eq!(m.points.len(), m.beyond.len());
        assert!(m.indices.len() % 3 == 0 && !m.indices.is_empty());
        assert!(m.indices.iter().all(|&i| (i as usize) < m.points.len()));
        // los bordes quedan a ±3 del eje
        let ys: Vec<f32> = m.points.iter().map(|p| p.y).collect();
        let maxy = ys.iter().cloned().fold(f32::MIN, f32::max);
        let miny = ys.iter().cloned().fold(f32::MAX, f32::min);
        assert!((maxy - 3.0).abs() < 1e-3 && (miny + 3.0).abs() < 1e-3);
        // remate redondo: pasa del extremo hasta el radio
        let b = m.beyond.iter().cloned().fold(0.0, f32::max);
        assert!((b - 3.0).abs() < 1e-2);
    }

    #[test]
    fn giro_cerrado_no_deja_lazos_en_el_borde() {
        // horquilla más cerrada que el grosor
        let mut pts = line(30, |i| V::new(i, 0.0));
        pts.extend(line(30, |i| V::new(29.0 - i, 1.0)));
        let half = vec![4.0; pts.len()];
        let m = halves(&pts, &half, 1, 1);
        assert!(!m.indices.is_empty());
        assert!(m.points.iter().all(|p| p.x.is_finite() && p.y.is_finite()));
    }

    #[test]
    fn cruce_de_segmentos_como_godot() {
        let x = seg_intersect(V::new(0., 0.), V::new(10., 0.), V::new(5., -5.), V::new(5., 5.)).unwrap();
        assert!((x.x - 5.0).abs() < 1e-5 && x.y.abs() < 1e-5);
        assert!(seg_intersect(V::new(0., 0.), V::new(10., 0.), V::new(0., 1.), V::new(10., 1.)).is_none());
    }
}
