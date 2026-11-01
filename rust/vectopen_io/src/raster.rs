//! Imágenes raster → RGBA8. Lee lo que Godot no sabe leer, sobre todo JPEG en
//! CMYK / YCCK (los que incrustan Affinity, Illustrator y Photoshop).

use crate::guard::MAX_IMAGE_PIXELS;

pub struct Rgba8 {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

pub fn decode(bytes: &[u8]) -> Result<Rgba8, String> {
    let mut r = image::ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|e| e.to_string())?;
    let mut limits = image::Limits::default();
    limits.max_alloc = Some(MAX_IMAGE_PIXELS * 4);
    r.limits(limits);
    let (w, h) = r.into_dimensions().map_err(|e| e.to_string())?;
    if (w as u64) * (h as u64) > MAX_IMAGE_PIXELS {
        return Err(format!("imagen demasiado grande ({w}×{h})"));
    }
    let mut r = image::ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|e| e.to_string())?;
    let mut limits = image::Limits::default();
    limits.max_alloc = Some(MAX_IMAGE_PIXELS * 4);
    r.limits(limits);
    let img = r.decode().map_err(|e| e.to_string())?.to_rgba8();
    Ok(Rgba8 { width: img.width(), height: img.height(), data: img.into_raw() })
}

/// Para la clase ImageDecoder: cualquier imagen → PNG.
pub fn to_png(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let im = decode(bytes)?;
    let buf = image::RgbaImage::from_raw(im.width, im.height, im.data).ok_or("datos inválidos")?;
    let mut out = std::io::Cursor::new(Vec::new());
    buf.write_to(&mut out, image::ImageFormat::Png).map_err(|e| e.to_string())?;
    Ok(out.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn png_minimo_se_lee() {
        let mut out = std::io::Cursor::new(Vec::new());
        image::RgbaImage::from_pixel(3, 2, image::Rgba([255, 0, 0, 255]))
            .write_to(&mut out, image::ImageFormat::Png)
            .unwrap();
        let im = decode(out.get_ref()).unwrap();
        assert_eq!((im.width, im.height, im.data.len()), (3, 2, 24));
    }

    #[test]
    fn basura_da_error_no_panic() {
        assert!(decode(b"esto no es una imagen").is_err());
    }

    /// Con un JPEG CMYK real: CMYK_JPEG=/ruta/foto.jpg cargo test
    #[test]
    fn jpeg_cmyk_real() {
        let Ok(p) = std::env::var("CMYK_JPEG") else { return };
        let im = decode(&std::fs::read(p).unwrap()).unwrap();
        assert!(im.width > 0);
        if let Ok(out) = std::env::var("CMYK_OUT") {
            image::RgbaImage::from_raw(im.width, im.height, im.data).unwrap().save(out).unwrap();
        }
    }
}
