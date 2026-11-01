//! Píxeles de Affinity (DyBm): un plano por canal en mosaicos de 256 bytes ×
//! 256 filas. Cada mosaico tiene un estado: 0/1 = ceros, 2 = todo 0xFF,
//! 3 = 1.0 (float), 4 = datos en un archivo interno («d/…»), 5 = no guardado
//! a resolución completa (se usa el nivel reducido «MI…»).
//! La rejilla empieza en el píxel (0,0); LInf/TInf no desplazan (comprobado).

use super::container::Archive;
use super::stream::{tag, Doc as Tree, Obj, Tag, Val};
use crate::guard::MAX_IMAGE_PIXELS;
use crate::raster::Rgba8;

const T: usize = 256;

fn int(o: &Obj, f: &str) -> Option<i64> {
    int_t(o, tag(f))
}

fn int_t(o: &Obj, k: Tag) -> Option<i64> {
    match o.get_tag(k)? {
        Val::Int(v) => Some(*v),
        Val::Float(v) => Some(*v as i64),
        Val::Enum(v) => Some(*v as i64),
        _ => None,
    }
}

fn statuses(o: &Obj, f: &str) -> Vec<u8> {
    statuses_t(o, tag(f))
}

fn statuses_t(o: &Obj, k: Tag) -> Vec<u8> {
    match o.get_tag(k) {
        Some(Val::List(l)) => l.iter().map(|v| if let Val::Int(x) = v { *x as u8 } else { 0 }).collect(),
        _ => Vec::new(),
    }
}

/// Bloques de datos de un canal, en orden («Idx1» puede repetirse o ser lista).
fn blocks<'a>(t: &'a Tree, o: &'a Obj, k: Tag) -> Vec<&'a Obj> {
    let mut out = Vec::new();
    for v in o.all_tag(k) {
        match v {
            Val::List(l) => out.extend(l.iter().filter_map(|x| t.deref(x))),
            other => out.extend(t.deref(other)),
        }
    }
    out
}

/// Un plano (canal) de `w_bytes` × `h` a partir de una rejilla de mosaicos.
#[allow(clippy::too_many_arguments)]
fn plane(
    a: &Archive, grid_w: usize, grid_h: usize, sta: &[u8], blks: &[&Obj],
    left: usize, top: usize, w_bytes: usize, h: usize,
) -> Result<Vec<u8>, String> {
    let mut out = vec![0u8; w_bytes * h];
    let mut bi = 0;
    for (k, &s) in sta.iter().enumerate().take(grid_w * grid_h) {
        let (col, row) = (k % grid_w, k / grid_w);
        // Origen del mosaico en coordenadas de la imagen (puede ser negativo).
        let ox = col as i64 * T as i64 - (left * T) as i64;
        let oy = row as i64 * T as i64 - (top * T) as i64;
        let fill = |out: &mut Vec<u8>, v: u8| {
            for y in 0..T as i64 {
                let iy = oy + y;
                if iy < 0 || iy >= h as i64 {
                    continue;
                }
                let x0 = ox.max(0);
                let x1 = (ox + T as i64).min(w_bytes as i64);
                if x0 < x1 {
                    let r = iy as usize * w_bytes;
                    out[r + x0 as usize..r + x1 as usize].fill(v);
                }
            }
        };
        match s {
            0 | 1 => {}
            2 | 3 => fill(&mut out, 0xFF),
            4 => {
                let Some(b) = blks.get(bi) else { return Err("faltan mosaicos".into()) };
                bi += 1;
                let name = match b.get("Data") {
                    Some(Val::Str(n)) => n.clone(),
                    _ => return Err("mosaico sin datos".into()),
                };
                let buf = a.read(&name)?;
                if buf.len() != T * T {
                    return Err("mosaico con tamaño inesperado".into());
                }
                let rect = match b.get("Rect") {
                    Some(Val::Nums(n)) if n.len() == 4 => [n[0] as usize, n[1] as usize, n[2] as usize, n[3] as usize],
                    _ => [0, 0, T, T],
                };
                let [rx0, ry0, rx1, ry1] = rect.map(|v| v.min(T));
                for y in ry0..ry1 {
                    let iy = oy + y as i64;
                    if iy < 0 || iy >= h as i64 {
                        continue;
                    }
                    for x in rx0..rx1 {
                        let ix = ox + x as i64;
                        if ix >= 0 && (ix as usize) < w_bytes {
                            out[iy as usize * w_bytes + ix as usize] = buf[y * T + x];
                        }
                    }
                }
            }
            _ => return Err(format!("estado de mosaico desconocido ({s})")),
        }
    }
    Ok(out)
}

/// DyBm → RGBA8 (y factor de escala si se usó un nivel reducido).
pub fn decode(a: &Archive, t: &Tree, bm: &Obj) -> Result<(Rgba8, f32), String> {
    if !bm.is("DyBm") {
        return Err(format!("mapa de bits {} no compatible", bm.class()));
    }
    let fmt = int(bm, "Frmt").unwrap_or(0);
    let (ps, nch) = match fmt {
        0 => (1, 4), // RGBA 8
        1 => (2, 4), // RGBA 16
        2 => (1, 2), // gris + alfa 8
        3 => (2, 2), // gris + alfa 16
        4 => (1, 5), // CMYK + alfa 8
        6 => (1, 1), // máscara
        f => return Err(format!("formato de píxeles {f} no compatible")),
    };
    let w = int(bm, "BmpW").unwrap_or(0).max(0) as usize;
    let h = int(bm, "BmpH").unwrap_or(0).max(0) as usize;
    if w == 0 || h == 0 {
        return Err("imagen vacía".into());
    }
    // ¿Resolución completa o nivel reducido (todo en estado 5)?
    let full = statuses(bm, "Sta1");
    // Mosaicos en estado 5 = solo guardados en un nivel reducido: se usa el
    // MEJOR nivel disponible (1 = mitad, 2 = cuarto…).
    // Imagen enorme: el primer nivel reducido que quepa en el límite de memoria.
    let fits = |l: u8| ((w >> l) as u64 + 1) * ((h >> l) as u64 + 1) <= MAX_IMAGE_PIXELS;
    let too_big = (w as u64) * (h as u64) > MAX_IMAGE_PIXELS;
    let use_mip = full.is_empty() || full.contains(&5) || too_big;
    let level: u8 = (1..=12u8)
        .find(|&l| bm.get_tag([b'M', b'T', l, b'1']).is_some() && fits(l))
        .ok_or_else(|| if too_big { format!("imagen demasiado grande ({w}×{h})") } else { "imagen sin datos de píxeles".to_string() })
        .or_else(|e| if use_mip { Err(e) } else { Ok(1) })?;
    let (mut pw, mut ph, mut scale) = (w, h, 1.0f32);
    let mut planes: Vec<Vec<u8>> = Vec::new();
    for ch in 1..=nch {
        let (gw, gh, sta, blks, l, tp) = if use_mip {
            // Nivel reducido 1 (la mitad): etiquetas «MW» + nivel (byte) + canal.
            let c = b'0' + ch as u8;
            let f = 1usize << level;
            let gw = int_t(bm, [b'M', b'W', level, c]).map(|v| v.max(0) as usize).unwrap_or((w.div_ceil(f) * ps).div_ceil(T));
            let gh = int_t(bm, [b'M', b'H', level, c]).map(|v| v.max(0) as usize).unwrap_or(h.div_ceil(f).div_ceil(T));
            (gw, gh, statuses_t(bm, [b'M', b'T', level, c]), blocks(t, bm, [b'M', b'I', level, c]), 0, 0)
        } else {
            // Sin TWi/THi (algunas versiones): se deduce del tamaño de la imagen.
            let gw = int(bm, &format!("TWi{ch}")).map(|v| v.max(0) as usize).unwrap_or((w * ps).div_ceil(T));
            let gh = int(bm, &format!("THi{ch}")).map(|v| v.max(0) as usize).unwrap_or(h.div_ceil(T));
            // La rejilla empieza en el píxel (0,0) de la imagen (LInf/TInf no desplazan).
            (gw, gh, statuses(bm, &format!("Sta{ch}")), blocks(t, bm, tag(&format!("Idx{ch}"))), 0, 0)
        };
        if use_mip {
            let f = 1usize << level;
            pw = w.div_ceil(f);
            ph = h.div_ceil(f);
            scale = w as f32 / pw as f32;
        }
        let sta = if sta.iter().all(|&s| s == 5) && !use_mip { vec![2; sta.len()] } else { sta };
        if gw * gh == 0 || gw * gh > 1_000_000 {
            return Err("rejilla de mosaicos inválida".into());
        }
        planes.push(plane(a, gw, gh, &sta, &blks, l, tp, pw * ps, ph)?);
    }
    let px = |p: &Vec<u8>, i: usize| p[i * ps + ps - 1]; // 16 bits → byte alto
    let n = pw * ph;
    let mut rgba = vec![0u8; n * 4];
    for i in 0..n {
        let (r, g, b, al) = match nch {
            4 => (px(&planes[0], i), px(&planes[1], i), px(&planes[2], i), px(&planes[3], i)),
            2 => {
                let v = px(&planes[0], i);
                (v, v, v, px(&planes[1], i))
            }
            5 => {
                let k = 255 - px(&planes[3], i) as u32;
                let c = |v: u8| ((255 - v as u32) * k / 255) as u8;
                (c(px(&planes[0], i)), c(px(&planes[1], i)), c(px(&planes[2], i)), px(&planes[4], i))
            }
            _ => {
                let v = px(&planes[0], i);
                (v, v, v, 255)
            }
        };
        // Affinity guarda color PREMULTIPLICADO por el alfa.
        let un = |c: u8| if al == 0 { 0 } else { ((c as u32 * 255 + al as u32 / 2) / al as u32).min(255) as u8 };
        rgba[i * 4..i * 4 + 4].copy_from_slice(&[un(r), un(g), un(b), al]);
    }
    Ok((Rgba8 { width: pw as u32, height: ph as u32, data: rgba }, scale))
}
