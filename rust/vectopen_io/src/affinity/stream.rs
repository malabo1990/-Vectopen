//! Árbol de objetos de «doc.dat»: campos con etiqueta de 4 letras y un byte de
//! tipo (bit 0x80 = lista). Se lee ENTERO sin conocer el significado de cada
//! etiqueta; luego `convert` interpreta las que importan.

use std::collections::HashMap;
use std::rc::Rc;

use super::container::Rd;

/// Etiqueta de 4 letras en orden de lectura («PCrv», «Chld»…).
pub type Tag = [u8; 4];

/// Etiqueta desde texto; las cortas se rellenan con espacios (nunca falla).
pub fn tag(s: &str) -> Tag {
    let b = s.as_bytes();
    let g = |i: usize| b.get(i).copied().unwrap_or(b' ');
    [g(0), g(1), g(2), g(3)]
}

fn read_tag(r: &mut Rd) -> Result<Tag, String> {
    let b = r.take(4)?;
    Ok([b[3], b[2], b[1], b[0]])
}

#[derive(Debug, Clone)]
pub enum Val {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    /// Vectores de 2..6 números (enteros, float o double).
    Nums(Vec<f64>),
    Enum(u16),
    Str(String),
    /// Estructura de tamaño fijo, sin interpretar.
    Raw(Vec<u8>),
    /// Lista de registros de curva (tamaño de registro, registros seguidos).
    Records(u16, Vec<u8>),
    List(Vec<Val>),
    Obj(Rc<Obj>),
    Link(u32),
}

#[derive(Debug, Default)]
pub struct Obj {
    pub id: u32,
    /// Clases, de la más concreta a la más general («PCrv», «VNod», «Node»).
    pub classes: Vec<Tag>,
    pub fields: Vec<(Tag, Val)>,
}

impl Obj {
    pub fn get(&self, t: &str) -> Option<&Val> {
        self.get_tag(tag(t))
    }
    pub fn get_tag(&self, k: Tag) -> Option<&Val> {
        self.fields.iter().find(|(f, _)| *f == k).map(|(_, v)| v)
    }
    pub fn all(&self, t: &str) -> impl Iterator<Item = &Val> {
        self.all_tag(tag(t))
    }
    pub fn all_tag(&self, k: Tag) -> impl Iterator<Item = &Val> {
        self.fields.iter().filter(move |(f, _)| *f == k).map(|(_, v)| v)
    }
    pub fn is(&self, class: &str) -> bool {
        self.classes.first() == Some(&tag(class))
    }
    pub fn class(&self) -> String {
        self.classes.first().map(|t| String::from_utf8_lossy(t).into_owned()).unwrap_or_default()
    }
}

pub struct Doc {
    pub root: Obj,
    /// Objetos compartidos por id (los «Link» apuntan aquí).
    pub shared: HashMap<u32, Rc<Obj>>,
}

impl Doc {
    /// Sigue un enlace si lo es.
    pub fn deref<'a>(&'a self, v: &'a Val) -> Option<&'a Obj> {
        match v {
            Val::Obj(o) => Some(o),
            Val::Link(id) => self.shared.get(id).map(|o| o.as_ref()),
            _ => None,
        }
    }
    pub fn obj<'a>(&'a self, o: &'a Obj, t: &str) -> Option<&'a Obj> {
        o.get(t).and_then(|v| self.deref(v))
    }
}

const MAX_DEPTH: usize = 400;

struct P<'a> {
    r: Rd<'a>,
    shared: HashMap<u32, Rc<Obj>>,
    depth: usize,
}

pub fn parse(b: &[u8]) -> Result<Doc, String> {
    let mut p = P { r: Rd::new(b, 0), shared: HashMap::new(), depth: 0 };
    if p.r.take(4)? != [0x00, 0xFF, 0x4B, 0x53] {
        return Err("documento interno de Affinity no reconocido".into());
    }
    let ver = p.r.u16()?;
    let class = read_tag(&mut p.r)?;
    p.r.u16()?;
    if ver > 2 {
        return Err(format!("versión de documento no compatible ({ver})"));
    }
    if ver == 2 {
        p.r.u32()?;
    }
    let mut root = Obj { id: 0, classes: vec![class], fields: Vec::new() };
    root.fields = p.fields(true)?;
    Ok(Doc { root, shared: p.shared })
}

impl<'a> P<'a> {
    /// Número de elementos de una lista, comprobando que caben en lo que queda.
    fn count(&mut self, elem: usize) -> Result<usize, String> {
        let n = self.r.u32()? as usize;
        if n.saturating_mul(elem.max(1)) > self.r.left() {
            return Err("lista con tamaño imposible".into());
        }
        Ok(n)
    }

    fn fields(&mut self, with_tag: bool) -> Result<Vec<(Tag, Val)>, String> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            return Err("objetos anidados demasiado profundos".into());
        }
        let mut out = Vec::new();
        loop {
            let t = self.r.u8()?;
            let arr = t & 0x80 != 0;
            let t = t & 0x7f;
            if t == 0 {
                break;
            }
            let tg = if with_tag { read_tag(&mut self.r)? } else { *b"????" };
            let v = self.value(t, arr)?;
            out.push((tg, v));
        }
        self.depth -= 1;
        Ok(out)
    }

    fn num(&mut self, t: u8) -> Result<f64, String> {
        Ok(match t {
            0x01 => self.r.u8()? as f64,
            0x02 => self.r.u16()? as f64,
            0x03 | 0x34 | 0x2f => self.r.u32()? as f64,
            0x04 => self.r.u64()? as f64,
            0x05 => self.r.u8()? as i8 as f64,
            0x06 => self.r.u16()? as i16 as f64,
            0x07 => self.r.u32()? as i32 as f64,
            0x08 => self.r.u64()? as i64 as f64,
            0x09 => f32::from_bits(self.r.u32()?) as f64,
            0x0a => f64::from_bits(self.r.u64()?),
            _ => unreachable!(),
        })
    }

    fn value(&mut self, t: u8, arr: bool) -> Result<Val, String> {
        match t {
            0x01..=0x0a | 0x2f | 0x34 => {
                let int = !matches!(t, 0x09 | 0x0a);
                let one = |p: &mut Self| -> Result<Val, String> {
                    let v = p.num(t)?;
                    Ok(if int { Val::Int(v as i64) } else { Val::Float(v) })
                };
                if arr {
                    let n = self.count(1)?;
                    (0..n).map(|_| one(self)).collect::<Result<_, _>>().map(Val::List)
                } else {
                    one(self)
                }
            }
            0x15..=0x19 | 0x1f..=0x23 | 0x24..=0x28 => {
                let (k, sub) = match t {
                    0x15..=0x19 => ((t - 0x15 + 2) as usize, 0x07),
                    0x1f..=0x23 => ((t - 0x1f + 2) as usize, 0x09),
                    _ => ((t - 0x24 + 2) as usize, 0x0a),
                };
                let one = |p: &mut Self| -> Result<Val, String> {
                    (0..k).map(|_| p.num(sub)).collect::<Result<Vec<_>, _>>().map(Val::Nums)
                };
                if arr {
                    let n = self.count(k * 4)?;
                    (0..n).map(|_| one(self)).collect::<Result<_, _>>().map(Val::List)
                } else {
                    one(self)
                }
            }
            0x29 => {
                if arr {
                    let n = self.count(0)?;
                    let bytes = self.r.take(n.div_ceil(8))?;
                    Ok(Val::List((0..n).map(|i| Val::Bool(bytes[i / 8] >> (i % 8) & 1 == 1)).collect()))
                } else {
                    Ok(Val::Bool(self.r.u8()? != 0))
                }
            }
            0x2a => {
                if arr {
                    let n = self.count(2)?;
                    self.r.u16()?;
                    (0..n).map(|_| self.r.u16().map(Val::Enum)).collect::<Result<_, _>>().map(Val::List)
                } else {
                    let v = self.r.u16()?;
                    self.r.u16()?;
                    Ok(Val::Enum(v))
                }
            }
            0x2b | 0x2e => {
                let one = |p: &mut Self| -> Result<Val, String> {
                    let n = p.r.u32()? as usize;
                    Ok(Val::Str(String::from_utf8_lossy(p.r.take(n)?).into_owned()))
                };
                if arr {
                    self.r.u32()?;
                    let n = self.count(4)?;
                    (0..n).map(|_| one(self)).collect::<Result<_, _>>().map(Val::List)
                } else {
                    one(self)
                }
            }
            0x2c => {
                let n = if arr { self.count(0)? } else { 1 };
                let size = self.r.u16()?;
                let total = n.checked_mul(size as usize).ok_or("lista enorme")?;
                Ok(Val::Records(size, self.r.take(total)?.to_vec()))
            }
            0x2d => {
                let n = self.r.u32()? as usize;
                Ok(Val::Raw(self.r.take(n)?.to_vec()))
            }
            0x33 => {
                read_tag(&mut self.r)?;
                let n = self.r.u32()? as usize;
                Ok(Val::Str(String::from_utf8_lossy(self.r.take(n)?).into_owned()))
            }
            0x75 => {
                self.r.u16()?;
                let c = self.r.u8()? as usize;
                if c > 8 {
                    return Err("indicadores dañados".into());
                }
                Ok(Val::Raw(self.r.take(c)?.to_vec()))
            }
            0x35..=0x74 => {
                let size = (t - 0x34) as usize;
                if arr {
                    let n = self.count(size)?;
                    Ok(Val::List((0..n).map(|_| self.r.take(size).map(|b| Val::Raw(b.to_vec()))).collect::<Result<_, _>>()?))
                } else {
                    Ok(Val::Raw(self.r.take(size)?.to_vec()))
                }
            }
            0x30 | 0x31 | 0x32 => {
                let mut n = 1;
                let mut h32 = None;
                if arr {
                    n = self.count(1)?;
                    if t == 0x32 {
                        let tg = read_tag(&mut self.r)?;
                        self.r.u16()?;
                        h32 = Some(tg);
                    }
                }
                let mut objs = Vec::with_capacity(n.min(4096));
                for _ in 0..n {
                    objs.push(self.object(t, h32)?);
                }
                Ok(if arr { Val::List(objs) } else { objs.pop().unwrap_or(Val::Null) })
            }
            _ => Err(format!("tipo de dato desconocido ({t:#x}) en {}", self.r.p)),
        }
    }

    fn object(&mut self, t: u8, h32: Option<Tag>) -> Result<Val, String> {
        match t {
            0x30 => {
                let f = self.fields(false)?;
                Ok(Val::Obj(Rc::new(Obj { id: 0, classes: Vec::new(), fields: f })))
            }
            0x31 => match self.r.u8()? {
                0 => Ok(Val::Null),
                2 => Ok(Val::Link(self.r.u32()?)),
                1 => {
                    let id = self.r.u32()?;
                    let mut o = Obj { id, ..Default::default() };
                    loop {
                        match self.r.u8()? {
                            0 => {
                                let tg = read_tag(&mut self.r)?;
                                self.r.u16()?;
                                o.classes.push(tg);
                                let base = self.fields(true)?;
                                o.fields.extend(base);
                            }
                            1 => {
                                o.classes.push(read_tag(&mut self.r)?);
                                break;
                            }
                            2 => break,
                            f => return Err(format!("objeto dañado ({f}) en {}", self.r.p)),
                        }
                    }
                    let f = self.fields(true)?;
                    o.fields.extend(f);
                    let rc = Rc::new(o);
                    self.shared.insert(id, rc.clone());
                    Ok(Val::Obj(rc))
                }
                f => Err(format!("objeto dañado ({f}) en {}", self.r.p)),
            },
            _ => match self.r.u8()? {
                0 => Ok(Val::Null),
                1 => {
                    let tg = match h32 {
                        Some(t) => t,
                        None => {
                            let t = read_tag(&mut self.r)?;
                            self.r.u16()?;
                            t
                        }
                    };
                    let f = self.fields(true)?;
                    Ok(Val::Obj(Rc::new(Obj { id: 0, classes: vec![tg], fields: f })))
                }
                f => Err(format!("estructura dañada ({f}) en {}", self.r.p)),
            },
        }
    }
}
