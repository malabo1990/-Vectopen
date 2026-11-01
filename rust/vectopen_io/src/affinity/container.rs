//! Contenedor de Affinity (.af, .afdesign, .afphoto, .afpub…): cabecera,
//! cadena de tablas de archivos (una por guardado; vale la más reciente) y
//! archivos internos guardados sin comprimir, en zlib o en zstd.
//!
//! Formato estudiado a partir de afread (C++, MIT, © 2020-2021 Vladimir
//! Mamonov, https://github.com/VMDevCpp/afread) y comprobado con documentos
//! de Affinity 1, 2 y 3. Implementación propia.

use std::collections::HashMap;

/// Firma de todos los archivos de Affinity: 00 FF 4B 41.
pub const MAGIC: [u8; 4] = [0x00, 0xFF, 0x4B, 0x41];
/// Tamaño máximo de un archivo interno descomprimido.
const MAX_ENTRY: u64 = 512 * 1024 * 1024;

pub struct Archive<'a> {
    data: &'a [u8],
    pub version: u16,
    /// Clase del documento: "Prsn" (diseño/foto/publicación), "AsA" (recursos)…
    pub class: String,
    thumb_offset: u64,
    /// nombre → entrada de la revisión más reciente.
    files: HashMap<String, Entry>,
    /// id interno → nombre (las revisiones posteriores solo traen el id).
    ids: HashMap<u32, String>,
}

#[derive(Clone, Copy, Debug)]
struct Entry {
    offset: u64,
    size: u64,
    csize: u64,
    compression: u8,
    date: u64,
}

pub(crate) struct Rd<'a> {
    pub b: &'a [u8],
    pub p: usize,
}

impl<'a> Rd<'a> {
    pub fn new(b: &'a [u8], p: usize) -> Self {
        Rd { b, p }
    }
    pub fn take(&mut self, n: usize) -> Result<&'a [u8], String> {
        let end = self.p.checked_add(n).ok_or("desbordamiento")?;
        if end > self.b.len() {
            return Err(format!("datos cortados en {}", self.p));
        }
        let s = &self.b[self.p..end];
        self.p = end;
        Ok(s)
    }
    pub fn u8(&mut self) -> Result<u8, String> {
        Ok(self.take(1)?[0])
    }
    pub fn u16(&mut self) -> Result<u16, String> {
        Ok(u16::from_le_bytes(self.take(2)?.try_into().unwrap()))
    }
    pub fn u32(&mut self) -> Result<u32, String> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    pub fn u64(&mut self) -> Result<u64, String> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
    pub fn left(&self) -> usize {
        self.b.len().saturating_sub(self.p)
    }
}

fn tag(b: &[u8]) -> String {
    b.iter().rev().map(|&c| c as char).collect()
}

impl<'a> Archive<'a> {
    pub fn open(data: &'a [u8]) -> Result<Archive<'a>, String> {
        let mut r = Rd::new(data, 0);
        if r.take(4)? != MAGIC {
            return Err("no es un archivo de Affinity".into());
        }
        let version = r.u16()?;
        let flag = r.u16()?;
        let class = tag(r.take(4)?);
        if !(7..=12).contains(&version) {
            return Err(format!("versión de Affinity no compatible ({version})"));
        }
        if flag & 3 != 0 {
            return Err("formato de Affinity no compatible (archivo comprimido entero)".into());
        }
        if r.take(4)? != b"#Inf" {
            return Err("cabecera de Affinity dañada".into());
        }
        let fat_offset = r.u64()?;
        let thumb_offset = r.u64()?;
        let mut a = Archive { data, version, class, thumb_offset, files: HashMap::new(), ids: HashMap::new() };
        a.load_fats(fat_offset)?;
        Ok(a)
    }

    fn load_fats(&mut self, first: u64) -> Result<(), String> {
        let mut off = first;
        let mut seen = 0;
        while off != 0 {
            seen += 1;
            if seen > 10_000 {
                return Err("tabla de archivos en bucle".into());
            }
            let mut r = Rd::new(self.data, usize::try_from(off).map_err(|_| "posición inválida")?);
            let t = r.take(4)?.to_vec();
            let kind = match &t[..] {
                b"#FAT" => 1,
                b"#FT2" => 2,
                b"#FT3" => 3,
                b"#FT4" => 4,
                _ => return Err("tabla de archivos dañada".into()),
            };
            let next = r.u64()?;
            let date = r.u64()?;
            r.u64()?;
            r.u64()?;
            r.u64()?;
            let files = r.u32()?;
            r.u32()?;
            r.u32()?;
            let dirs = r.u16()?;
            r.u8()?;
            for _ in 0..files {
                let id = r.u32()?;
                let fl = r.u8()?;
                if fl > 2 {
                    return Err("tabla de archivos dañada".into());
                }
                let mut e = None;
                if fl == 0 || fl == 1 {
                    let offset = r.u64()?;
                    let size = r.u64()?;
                    let csize = r.u64()?;
                    r.u32()?; // crc32
                    let mut compression = r.u8()?;
                    if kind != 1 {
                        r.u32()?;
                    }
                    if kind == 4 {
                        r.u32()?;
                    }
                    if kind <= 2 {
                        compression = match compression {
                            1 => 0x01,
                            2 => 0x41,
                            3 => 0x81,
                            4 => 0xc1,
                            _ => 0,
                        };
                    }
                    e = Some(Entry { offset, size, csize, compression, date });
                }
                let name = if fl == 0 {
                    let n = r.u16()? as usize;
                    Some(String::from_utf8_lossy(r.take(n)?).into_owned())
                } else {
                    None
                };
                if let Some(n) = &name {
                    self.ids.insert(id, n.clone());
                }
                let n = name.or_else(|| self.ids.get(&id).cloned());
                if let (Some(n), Some(e)) = (n, e) {
                    let newer = self.files.get(&n).map(|o| e.date >= o.date).unwrap_or(true);
                    if newer {
                        self.files.insert(n, e);
                    }
                }
            }
            for _ in 0..dirs {
                let n = r.u16()? as usize;
                r.u16()?;
                r.u64()?;
                r.take(n)?;
            }
            off = next;
        }
        Ok(())
    }

    pub fn names(&self) -> Vec<&str> {
        let mut v: Vec<&str> = self.files.keys().map(|s| s.as_str()).collect();
        v.sort();
        v
    }

    pub fn has(&self, name: &str) -> bool {
        self.files.contains_key(name)
    }

    /// Contenido descomprimido de un archivo interno.
    pub fn read(&self, name: &str) -> Result<Vec<u8>, String> {
        let e = *self.files.get(name).ok_or_else(|| format!("falta «{name}» dentro del archivo"))?;
        if e.size > MAX_ENTRY {
            return Err(format!("«{name}» es demasiado grande"));
        }
        let mut r = Rd::new(self.data, usize::try_from(e.offset).map_err(|_| "posición inválida")?);
        if r.take(4)? != b"#Fil" {
            return Err(format!("«{name}» está dañado"));
        }
        let raw = match e.compression & 3 {
            1 => {
                let src = r.take(e.csize as usize)?;
                miniz_oxide::inflate::decompress_to_vec_zlib_with_limit(src, e.size as usize)
                    .or_else(|_| miniz_oxide::inflate::decompress_to_vec_with_limit(src, e.size as usize))
                    .map_err(|_| format!("no se pudo descomprimir «{name}»"))?
            }
            2 => {
                let src = r.take(e.csize as usize)?;
                let mut dec = ruzstd::StreamingDecoder::new(src).map_err(|err| format!("zstd: {err}"))?;
                let mut out = Vec::with_capacity(e.size as usize);
                std::io::Read::read_to_end(&mut std::io::Read::take(&mut dec, e.size + 1), &mut out)
                    .map_err(|err| format!("zstd: {err}"))?;
                out
            }
            _ => r.take(e.size as usize)?.to_vec(),
        };
        if raw.len() as u64 != e.size {
            return Err(format!("«{name}» tiene un tamaño inesperado"));
        }
        let mut raw = raw;
        unpredict(&mut raw, e.compression);
        Ok(raw)
    }

    /// Miniatura PNG incrustada (vista previa), si la hay.
    pub fn thumbnail(&self) -> Option<&'a [u8]> {
        let start = usize::try_from(self.thumb_offset).ok()?;
        let tail = self.data.get(start..)?;
        let k = tail.windows(8).take(4096).position(|w| w == b"\x89PNG\r\n\x1a\n")?;
        let png = &tail[k..];
        // Hasta el final del bloque IEND.
        let end = png.windows(4).position(|w| w == b"IEND").map(|i| i + 8)?;
        Some(&png[..end.min(png.len())])
    }
}

/// Deshace los «predictores» con que Affinity guarda los mosaicos de píxeles
/// (cada valor = diferencia con el anterior; a veces con bytes reordenados).
fn unpredict(buf: &mut [u8], c: u8) {
    let mut flag = (c >> 5) & 1;
    let kind = match c & 0xc0 {
        0x40 => {
            flag = 0;
            1
        }
        0x80 => 2,
        0xc0 => 3,
        _ => {
            flag = 0;
            0
        }
    };
    let sum8 = |b: &mut [u8]| {
        let mut acc = 0u8;
        for v in b.iter_mut() {
            acc = acc.wrapping_add(*v);
            *v = acc;
        }
    };
    if flag == 0 {
        if kind == 1 {
            sum8(buf);
        }
        if kind == 2 {
            let mut acc = 0u16;
            for ch in buf.chunks_exact_mut(2) {
                acc = acc.wrapping_add(u16::from_le_bytes([ch[0], ch[1]]));
                ch.copy_from_slice(&acc.to_le_bytes());
            }
        }
    } else if kind == 2 {
        sum8(buf);
        if buf.len() == 0x10000 {
            // Bytes altos y bajos guardados en mitades separadas.
            let src = buf.to_vec();
            for i in 0..0x4000 {
                buf[i * 4 + 1] = src[i * 2];
                buf[i * 4 + 3] = src[i * 2 + 1];
                buf[i * 4] = src[0x8000 + i * 2];
                buf[i * 4 + 2] = src[0x8000 + i * 2 + 1];
            }
        }
    }
}
