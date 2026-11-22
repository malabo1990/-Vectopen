//! Relleno de contornos con huecos (VAL-66): teselado con lyon, robusto con
//! anillos que se tocan o se cruzan («huecos pellizcados» de una foto
//! vectorizada), donde el triangulador de Godot falla y había que rehacerlo
//! con todos los puntos (~0,5 s por forma).

use lyon_tessellation::math::point;
use lyon_tessellation::path::Path;
use lyon_tessellation::{BuffersBuilder, FillOptions, FillRule, FillTessellator, FillVertex, VertexBuffers};

/// Triángulos que rellenan `rings` (cada anillo, una lista de puntos cerrada
/// implícitamente). `evenodd` = regla par-impar; si no, «no cero».
/// Devuelve (vértices, índices); vacío si no hay nada que rellenar.
pub fn fill_rings(rings: &[Vec<[f32; 2]>], evenodd: bool) -> (Vec<[f32; 2]>, Vec<u32>) {
    let mut b = Path::builder();
    let mut any = false;
    for r in rings {
        if r.len() < 3 {
            continue;
        }
        b.begin(point(r[0][0], r[0][1]));
        for p in &r[1..] {
            b.line_to(point(p[0], p[1]));
        }
        b.end(true);
        any = true;
    }
    if !any {
        return (Vec::new(), Vec::new());
    }
    let path = b.build();
    let mut buf: VertexBuffers<[f32; 2], u32> = VertexBuffers::new();
    let rule = if evenodd { FillRule::EvenOdd } else { FillRule::NonZero };
    let opts = FillOptions::tolerance(0.01).with_fill_rule(rule);
    let res = FillTessellator::new().tessellate_path(
        &path,
        &opts,
        &mut BuffersBuilder::new(&mut buf, |v: FillVertex| {
            let p = v.position();
            [p.x, p.y]
        }),
    );
    if res.is_err() {
        return (Vec::new(), Vec::new());
    }
    (buf.vertices, buf.indices)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn area(v: &[[f32; 2]], idx: &[u32]) -> f32 {
        idx.chunks(3)
            .map(|t| {
                let (a, b, c) = (v[t[0] as usize], v[t[1] as usize], v[t[2] as usize]);
                ((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])).abs() * 0.5
            })
            .sum()
    }

    fn sq(x: f32, y: f32, s: f32) -> Vec<[f32; 2]> {
        vec![[x, y], [x + s, y], [x + s, y + s], [x, y + s]]
    }

    #[test]
    fn hueco_par_impar() {
        let (v, i) = fill_rings(&[sq(0.0, 0.0, 100.0), sq(25.0, 25.0, 50.0)], true);
        assert!((area(&v, &i) - (10000.0 - 2500.0)).abs() < 1.0);
    }

    #[test]
    fn hueco_pellizcado_que_toca_el_borde() {
        // El hueco comparte un vértice con el contorno exterior.
        let outer = sq(0.0, 0.0, 100.0);
        let hole = vec![[0.0, 0.0], [50.0, 20.0], [20.0, 50.0]];
        let (v, i) = fill_rings(&[outer, hole], true);
        let expect = 10000.0 - 0.5 * ((50.0f32 * 50.0) - (20.0 * 20.0));
        assert!((area(&v, &i) - expect).abs() < 1.0, "área {}", area(&v, &i));
    }

    #[test]
    fn contorno_que_se_cruza() {
        // Pajarita: dos triángulos de 50 × 50 / 2 cada uno.
        let bow = vec![[0.0, 0.0], [100.0, 100.0], [100.0, 0.0], [0.0, 100.0]];
        let (v, i) = fill_rings(&[bow], true);
        assert!((area(&v, &i) - 5000.0).abs() < 1.0);
    }
}
