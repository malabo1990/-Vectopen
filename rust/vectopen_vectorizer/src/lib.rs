use std::path::Path;
use std::sync::{Arc, Mutex};

use godot::classes::RefCounted;
use godot::prelude::*;
use image::imageops::FilterType;
use image::{GrayImage, Luma, Rgba, RgbaImage};
use ndarray::{Array4, Axis};
use ort::inputs;
use ort::session::Session;
use ort::value::TensorRef;

struct VectopenVectorizerExtension;

#[gdextension]
unsafe impl ExtensionLibrary for VectopenVectorizerExtension {}

/// Vectoriza imágenes raster (PNG/JPG) a SVG mediante vtracer y las deja
/// listas para importar como VectorPath. Expuesta a GDScript como
/// "ImageVectorizer" (RefCounted, `ImageVectorizer.new()`).
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct ImageVectorizer {
    base: Base<RefCounted>,
}

#[godot_api]
impl ImageVectorizer {
    /// Vectoriza `input_path` (ruta de sistema de archivos, ya resuelta con
    /// ProjectSettings.globalize_path — no acepta "res://") y escribe el SVG
    /// resultante en `output_path`. Devuelve "" en éxito, o un mensaje de
    /// error legible en caso contrario.
    ///
    /// - filter_speckle: área mínima de mancha a conservar (ruido pequeño se
    ///   descarta); 4 es el valor por defecto de vtracer.
    /// - corner_threshold: ángulo (grados) bajo el cual un vértice se trata
    ///   como esquina dura en vez de curva; 60 es el valor por defecto.
    /// - color_mode_binary: true = blanco/negro (para trazos/logos), false =
    ///   color (para fotos/ilustraciones).
    #[func]
    fn vectorize_to_file(
        &self,
        input_path: GString,
        output_path: GString,
        filter_speckle: i64,
        corner_threshold: i64,
        color_mode_binary: bool,
    ) -> GString {
        let mut config = vtracer::Config::from_preset(vtracer::Preset::Photo);
        config.filter_speckle = filter_speckle.max(0) as usize;
        config.corner_threshold = corner_threshold as i32;
        config.color_mode = if color_mode_binary {
            vtracer::ColorMode::Binary
        } else {
            vtracer::ColorMode::Color
        };

        let result = vtracer::convert_image_to_svg(
            Path::new(&input_path.to_string()),
            Path::new(&output_path.to_string()),
            config,
        );

        match result {
            Ok(()) => GString::new(),
            Err(e) => GString::from(&e),
        }
    }

    /// Igual que vectorize_to_file pero con TODAS las opciones de vtracer en
    /// un Dictionary (las que falten usan el preajuste "Photo"):
    ///   color_mode: "color" | "binary"     hierarchical: "stacked" | "cutout"
    ///   mode: "spline" (Bézier) | "polygon" | "pixel"
    ///   filter_speckle, color_precision (1-8), layer_difference (0-255),
    ///   corner_threshold (°), length_threshold (3.5-10), max_iterations,
    ///   splice_threshold (°), path_precision (decimales)
    #[func]
    fn vectorize_ex(&self, input_path: GString, output_path: GString, opts: VarDictionary) -> GString {
        match vectorize_impl(&input_path.to_string(), &output_path.to_string(), config_from(&opts)) {
            Ok(()) => GString::new(),
            Err(e) => GString::from(&e),
        }
    }
}

/// Opciones de la interfaz (Dictionary) → vtracer::Config. Se hace en el
/// hilo principal: el Config resultante es Rust puro y viaja a otro hilo.
fn config_from(opts: &VarDictionary) -> vtracer::Config {
        let mut config = vtracer::Config::from_preset(vtracer::Preset::Photo);
        let gi = |k: &str| opts.get(k).and_then(|v| v.try_to::<i64>().ok());
        let gf = |k: &str| opts.get(k).and_then(|v| v.try_to::<f64>().ok());
        let gs = |k: &str| opts.get(k).and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string());
        if let Some(s) = gs("color_mode") {
            config.color_mode = if s == "binary" { vtracer::ColorMode::Binary } else { vtracer::ColorMode::Color };
        }
        if let Some(s) = gs("hierarchical") {
            config.hierarchical = if s == "cutout" { vtracer::Hierarchical::Cutout } else { vtracer::Hierarchical::Stacked };
        }
        if let Some(s) = gs("mode") {
            config.mode = match s.as_str() {
                "polygon" => visioncortex::PathSimplifyMode::Polygon,
                "pixel" => visioncortex::PathSimplifyMode::None,
                _ => visioncortex::PathSimplifyMode::Spline,
            };
        }
        if let Some(v) = gi("filter_speckle") { config.filter_speckle = v.max(0) as usize; }
        if let Some(v) = gi("color_precision") { config.color_precision = v.clamp(1, 8) as i32; }
        if let Some(v) = gi("layer_difference") { config.layer_difference = v.clamp(0, 255) as i32; }
        if let Some(v) = gi("corner_threshold") { config.corner_threshold = v.clamp(0, 180) as i32; }
        if let Some(v) = gf("length_threshold") { config.length_threshold = v.clamp(3.5, 10.0); }
        if let Some(v) = gi("max_iterations") { config.max_iterations = v.clamp(1, 50) as usize; }
        if let Some(v) = gi("splice_threshold") { config.splice_threshold = v.clamp(0, 180) as i32; }
        if let Some(v) = gi("path_precision") { config.path_precision = Some(v.clamp(0, 8) as u32); }
        config
}

fn vectorize_impl(input_path: &str, output_path: &str, config: vtracer::Config) -> Result<(), String> {
    vtracer::convert_image_to_svg(Path::new(input_path), Path::new(output_path), config)
}

/// Trabajo en SEGUNDO PLANO (hilo de Rust): GDScript no puede llamar a la
/// extensión desde un hilo propio (godot-rust lo prohíbe), así que el hilo
/// lo crea Rust y el hilo no toca la API de Godot. GDScript lanza un
/// trabajo y consulta is_done() / get_error() cada frame.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct VectorizerJob {
    base: Base<RefCounted>,
    state: Arc<Mutex<Option<Result<(), String>>>>,
}

#[godot_api]
impl VectorizerJob {
    /// [quitar fondo] → [×4] → vtracer. Los intermedios van a `tmp_dir`
    /// (ruta de sistema) y se borran al terminar.
    #[func]
    fn start_vectorize(&mut self, input_path: GString, output_svg: GString, opts: VarDictionary,
            remove_bg: bool, upscale: bool, tmp_dir: GString) {
        let config = config_from(&opts);
        let (input, output, tmp) = (input_path.to_string(), output_svg.to_string(), tmp_dir.to_string());
        self.spawn(move || {
            let mut cur = input;
            let mut temps: Vec<String> = Vec::new();
            let result = (|| {
                if remove_bg {
                    let t = format!("{}/vtj_nobg_{}.png", tmp, std::process::id());
                    remove_background_impl(&cur, &t)?;
                    temps.push(t.clone());
                    cur = t;
                }
                if upscale {
                    let t = format!("{}/vtj_x4_{}.png", tmp, std::process::id());
                    upscale_impl(&cur, &t)?;
                    temps.push(t.clone());
                    cur = t;
                }
                vectorize_impl(&cur, &output, config)
            })();
            for t in temps {
                let _ = std::fs::remove_file(t);
            }
            result
        });
    }

    #[func]
    fn start_remove_background(&mut self, input_path: GString, output_path: GString) {
        let (i, o) = (input_path.to_string(), output_path.to_string());
        self.spawn(move || remove_background_impl(&i, &o));
    }

    #[func]
    fn start_upscale(&mut self, input_path: GString, output_path: GString) {
        let (i, o) = (input_path.to_string(), output_path.to_string());
        self.spawn(move || upscale_impl(&i, &o));
    }

    #[func]
    fn is_done(&self) -> bool {
        self.state.lock().map(|s| s.is_some()).unwrap_or(true)
    }

    /// "" si terminó bien (o aún no terminó); el mensaje si falló.
    #[func]
    fn get_error(&self) -> GString {
        match self.state.lock() {
            Ok(s) => match &*s {
                Some(Err(e)) => GString::from(e),
                _ => GString::new(),
            },
            Err(_) => GString::from("estado del trabajo corrupto"),
        }
    }
}

impl VectorizerJob {
    fn spawn<F>(&mut self, work: F)
    where
        F: FnOnce() -> Result<(), String> + Send + 'static,
    {
        let state = Arc::new(Mutex::new(None));
        self.state = state.clone();
        std::thread::spawn(move || {
            let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(work))
                .unwrap_or_else(|_| Err("fallo interno del trabajo nativo".to_string()));
            if let Ok(mut s) = state.lock() {
                *s = Some(r);
            }
        });
    }
}

/// Quita el fondo de una imagen con el modelo U²-Net-p (ONNX, embebido en el
/// binario — ver rust/vectopen_vectorizer/models/u2netp.onnx, Apache-2.0,
/// bajado de la release oficial de rembg con checksum verificado). Expuesta
/// a GDScript como "BackgroundRemover" (RefCounted, `BackgroundRemover.new()`).
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct BackgroundRemover {
    base: Base<RefCounted>,
}

#[godot_api]
impl BackgroundRemover {
    /// Quita el fondo de `input_path` (ruta de sistema de archivos, ya
    /// resuelta con ProjectSettings.globalize_path) y escribe un PNG con
    /// canal alfa en `output_path`. Devuelve "" en éxito, o un mensaje de
    /// error legible en caso contrario.
    ///
    /// Composición "naive" (alfa = máscara del modelo tal cual, sin refinar
    /// bordes de pelo/semitransparencias vía alpha matting) — suficiente
    /// para recortes de producto/icono/logo; retratos con pelo suelto
    /// quedarán con un borde algo duro.
    #[func]
    fn remove_background_to_file(&self, input_path: GString, output_path: GString) -> GString {
        match remove_background_impl(&input_path.to_string(), &output_path.to_string()) {
            Ok(()) => GString::new(),
            Err(e) => GString::from(&e),
        }
    }
}

const U2NETP_MODEL: &[u8] = include_bytes!("../models/u2netp.onnx");
const MODEL_INPUT_SIZE: u32 = 320;
// Normalización idéntica a rembg (BaseSession.normalize): ImageNet mean/std,
// pero el escalado previo es (pixel / max_pixel_de_la_imagen), no /255 —
// ver rembg/sessions/base.py. Replicarlo tal cual, no es un typo.
const IMAGENET_MEAN: [f32; 3] = [0.485, 0.456, 0.406];
const IMAGENET_STD: [f32; 3] = [0.229, 0.224, 0.225];

fn remove_background_impl(input_path: &str, output_path: &str) -> Result<(), String> {
    let mut session = Session::builder()
        .map_err(|e| e.to_string())?
        .commit_from_memory(U2NETP_MODEL)
        .map_err(|e| e.to_string())?;

    let original = image::open(input_path).map_err(|e| e.to_string())?;
    let (orig_w, orig_h) = (original.width(), original.height());

    let resized_rgb = image::imageops::resize(
        &original.to_rgb8(),
        MODEL_INPUT_SIZE,
        MODEL_INPUT_SIZE,
        FilterType::Lanczos3,
    );

    let max_val = resized_rgb
        .pixels()
        .flat_map(|p| p.0)
        .map(|v| v as f32)
        .fold(0.0f32, f32::max)
        .max(1e-6);

    let mut input = Array4::<f32>::zeros((1, 3, MODEL_INPUT_SIZE as usize, MODEL_INPUT_SIZE as usize));
    for (x, y, pixel) in resized_rgb.enumerate_pixels() {
        for c in 0..3 {
            let v = pixel.0[c] as f32 / max_val;
            input[[0, c, y as usize, x as usize]] = (v - IMAGENET_MEAN[c]) / IMAGENET_STD[c];
        }
    }

    let outputs = session
        .run(inputs![TensorRef::from_array_view(input.view()).map_err(|e| e.to_string())?])
        .map_err(|e| e.to_string())?;
    let raw = outputs[0].try_extract_array::<f32>().map_err(|e| e.to_string())?;

    // La forma exacta del tensor de salida (1,1,H,W) no está garantizada por
    // fuentes que pude verificar al 100%; colapsamos cualquier eje inicial
    // de tamaño 1 hasta quedarnos con el plano 2D H×W, en vez de asumir rank.
    let mut view = raw;
    while view.ndim() > 2 {
        view = view.index_axis_move(Axis(0), 0);
    }
    let view2 = view
        .into_dimensionality::<ndarray::Ix2>()
        .map_err(|e| e.to_string())?;
    let (mh, mw) = (view2.shape()[0], view2.shape()[1]);

    let mut min_v = f32::MAX;
    let mut max_v = f32::MIN;
    for &v in view2.iter() {
        if v < min_v {
            min_v = v;
        }
        if v > max_v {
            max_v = v;
        }
    }
    let range = (max_v - min_v).max(1e-6);

    let mut mask_small = GrayImage::new(mw as u32, mh as u32);
    for y in 0..mh {
        for x in 0..mw {
            let v = view2[[y, x]];
            let norm = (((v - min_v) / range) * 255.0).round().clamp(0.0, 255.0) as u8;
            mask_small.put_pixel(x as u32, y as u32, Luma([norm]));
        }
    }

    let mask = image::imageops::resize(&mask_small, orig_w, orig_h, FilterType::Lanczos3);

    let original_rgba = original.to_rgba8();
    let mut out = RgbaImage::new(orig_w, orig_h);
    for (x, y, px) in original_rgba.enumerate_pixels() {
        let alpha = mask.get_pixel(x, y).0[0];
        out.put_pixel(x, y, Rgba([px.0[0], px.0[1], px.0[2], alpha]));
    }

    out.save(output_path).map_err(|e| e.to_string())
}

/// Escala 4x una imagen con Real-ESRGAN-General-x4v3 (ONNX, conversión
/// oficial de Qualcomm AI Hub — pesos originales de xinntao/Real-ESRGAN,
/// BSD-3-Clause; ver rust/vectopen_vectorizer/models/real_esrgan_general_x4v3.*).
/// Expuesta a GDScript como "ImageUpscaler" (RefCounted, `ImageUpscaler.new()`).
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct ImageUpscaler {
    base: Base<RefCounted>,
}

#[godot_api]
impl ImageUpscaler {
    /// Escala 4x `input_path` y escribe el resultado en `output_path`.
    ///
    /// El modelo solo acepta tiles fijos de 128x128 -> 512x512 (limitación
    /// de esta conversión de Qualcomm AI Hub, no del algoritmo en sí), así
    /// que la imagen se divide en una rejilla de tiles — rellenando el
    /// borde con repetición del último píxel — y se reensambla después.
    /// Sin blending de solapes entre tiles: en imágenes grandes pueden
    /// notarse costuras sutiles en los límites de cada tile de 128px; sería
    /// el siguiente paso de calidad si hace falta.
    /// Devuelve "" en éxito, o un mensaje de error legible.
    #[func]
    fn upscale_to_file(&self, input_path: GString, output_path: GString) -> GString {
        match upscale_impl(&input_path.to_string(), &output_path.to_string()) {
            Ok(()) => GString::new(),
            Err(e) => GString::from(&e),
        }
    }
}

const ESRGAN_ONNX: &[u8] = include_bytes!("../models/real_esrgan_general_x4v3.onnx");
const ESRGAN_DATA: &[u8] = include_bytes!("../models/real_esrgan_general_x4v3.data");
const TILE_IN: u32 = 128;
const SCALE: u32 = 4;

fn upscale_impl(input_path: &str, output_path: &str) -> Result<(), String> {
    // El grafo referencia sus pesos externos por nombre relativo
    // ("real_esrgan_general_x4v3.data"): ONNX Runtime no resuelve
    // external_data desde commit_from_memory, así que hay que escribir
    // ambos archivos juntos a disco antes de abrir la sesión.
    let tmp_dir = std::env::temp_dir().join(format!("vectopen_esrgan_{}", std::process::id()));
    std::fs::create_dir_all(&tmp_dir).map_err(|e| e.to_string())?;
    let onnx_path = tmp_dir.join("real_esrgan_general_x4v3.onnx");
    let data_path = tmp_dir.join("real_esrgan_general_x4v3.data");
    std::fs::write(&onnx_path, ESRGAN_ONNX).map_err(|e| e.to_string())?;
    std::fs::write(&data_path, ESRGAN_DATA).map_err(|e| e.to_string())?;

    let mut session = Session::builder()
        .map_err(|e| e.to_string())?
        .commit_from_file(&onnx_path)
        .map_err(|e| e.to_string())?;

    let original = image::open(input_path).map_err(|e| e.to_string())?.to_rgb8();
    let (orig_w, orig_h) = (original.width(), original.height());

    let tiles_x = orig_w.div_ceil(TILE_IN);
    let tiles_y = orig_h.div_ceil(TILE_IN);
    let tile_out = TILE_IN * SCALE;

    let mut out = RgbaImage::new(orig_w * SCALE, orig_h * SCALE);

    for ty in 0..tiles_y {
        for tx in 0..tiles_x {
            let (x0, y0) = (tx * TILE_IN, ty * TILE_IN);
            let tile = extract_padded_tile(&original, x0, y0, TILE_IN, TILE_IN);

            let mut input = Array4::<f32>::zeros((1, 3, TILE_IN as usize, TILE_IN as usize));
            for (x, y, pixel) in tile.enumerate_pixels() {
                for c in 0..3 {
                    input[[0, c, y as usize, x as usize]] = pixel.0[c] as f32 / 255.0;
                }
            }

            let outputs = session
                .run(inputs![TensorRef::from_array_view(input.view()).map_err(|e| e.to_string())?])
                .map_err(|e| e.to_string())?;
            let raw = outputs[0].try_extract_array::<f32>().map_err(|e| e.to_string())?;

            let mut view = raw;
            while view.ndim() > 3 {
                view = view.index_axis_move(Axis(0), 0);
            }
            let view3 = view
                .into_dimensionality::<ndarray::Ix3>()
                .map_err(|e| e.to_string())?;

            let valid_w = (orig_w - x0).min(TILE_IN) * SCALE;
            let valid_h = (orig_h - y0).min(TILE_IN) * SCALE;
            let (base_x, base_y) = (x0 * SCALE, y0 * SCALE);

            for y in 0..valid_h.min(tile_out) {
                for x in 0..valid_w.min(tile_out) {
                    let r = (view3[[0, y as usize, x as usize]] * 255.0).round().clamp(0.0, 255.0) as u8;
                    let g = (view3[[1, y as usize, x as usize]] * 255.0).round().clamp(0.0, 255.0) as u8;
                    let b = (view3[[2, y as usize, x as usize]] * 255.0).round().clamp(0.0, 255.0) as u8;
                    out.put_pixel(base_x + x, base_y + y, Rgba([r, g, b, 255]));
                }
            }
        }
    }

    let _ = std::fs::remove_file(&onnx_path);
    let _ = std::fs::remove_file(&data_path);
    let _ = std::fs::remove_dir(&tmp_dir);

    out.save(output_path).map_err(|e| e.to_string())
}

fn extract_padded_tile(img: &image::RgbImage, x0: u32, y0: u32, w: u32, h: u32) -> image::RgbImage {
    let (iw, ih) = (img.width(), img.height());
    let mut tile = image::RgbImage::new(w, h);
    for ty in 0..h {
        for tx in 0..w {
            let sx = (x0 + tx).min(iw - 1);
            let sy = (y0 + ty).min(ih - 1);
            tile.put_pixel(tx, ty, *img.get_pixel(sx, sy));
        }
    }
    tile
}

/// Lee una imagen bitmap del portapapeles del sistema (copiada desde un
/// navegador, un visor/editor de imágenes, una captura de pantalla, etc.) y
/// la escribe como PNG. NO cubre "copiar un archivo" en el explorador de
/// Windows (formato CF_HDROP, distinto del bitmap CF_DIB/PNG que sí lee
/// arboard) — para eso hay que usar el diálogo de importar normal.
/// Expuesta a GDScript como "ClipboardImage" (RefCounted, `ClipboardImage.new()`).
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct ClipboardImage {
    base: Base<RefCounted>,
}

#[godot_api]
impl ClipboardImage {
    /// Escribe la imagen del portapapeles en `output_path` (PNG). Devuelve
    /// "" en éxito, "EMPTY" si el portapapeles no tiene una imagen (no es
    /// un error — el llamador debería entonces probar su propio portapapeles
    /// interno de formas/texto), o un mensaje de error legible en cualquier
    /// otro fallo.
    #[func]
    fn paste_image_to_file(&self, output_path: GString) -> GString {
        match paste_image_impl(&output_path.to_string()) {
            Ok(true) => GString::new(),
            Ok(false) => GString::from("EMPTY"),
            Err(e) => GString::from(&e),
        }
    }
}

fn paste_image_impl(output_path: &str) -> Result<bool, String> {
    let mut clipboard = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    let img = match clipboard.get_image() {
        Ok(img) => img,
        Err(arboard::Error::ContentNotAvailable) => return Ok(false),
        Err(e) => return Err(e.to_string()),
    };

    let buf: RgbaImage = RgbaImage::from_raw(img.width as u32, img.height as u32, img.bytes.into_owned())
        .ok_or_else(|| "Dimensiones de imagen del portapapeles inválidas".to_string())?;

    buf.save(output_path).map_err(|e| e.to_string())?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Toca el portapapeles REAL del sistema (lo sobrescribe con una imagen
    /// de prueba y lo deja así al terminar) — no es apto para correr en CI
    /// desatendido junto a otros procesos que también usen el portapapeles.
    /// Verificación manual deliberada de paste_image_impl, no parte de la
    /// suite de gdUnit4 (esa cubre solo que la clase se registre y no crashee).
    #[test]
    fn paste_image_impl_lee_lo_que_se_puso_en_el_portapapeles() {
        let mut clipboard = arboard::Clipboard::new().expect("no se pudo abrir el portapapeles");
        let pixels: Vec<u8> = vec![
            255, 0, 0, 255, // rojo
            0, 255, 0, 255, // verde
            0, 0, 255, 255, // azul
            255, 255, 0, 255, // amarillo
        ];
        clipboard
            .set_image(arboard::ImageData {
                width: 2,
                height: 2,
                bytes: std::borrow::Cow::from(pixels),
            })
            .expect("no se pudo escribir la imagen de prueba en el portapapeles");

        let tmp = std::env::temp_dir().join("vectopen_clipboard_test.png");
        let tmp_str = tmp.to_str().unwrap();

        let result = paste_image_impl(tmp_str).expect("paste_image_impl falló");
        assert!(result, "se esperaba encontrar una imagen en el portapapeles");

        let loaded = image::open(&tmp).expect("no se pudo releer el PNG escrito");
        assert_eq!(loaded.width(), 2);
        assert_eq!(loaded.height(), 2);
        assert_eq!(loaded.to_rgba8().get_pixel(0, 0).0, [255, 0, 0, 255]);

        let _ = std::fs::remove_file(&tmp);
    }
}
