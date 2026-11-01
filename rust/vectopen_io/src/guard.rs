//! Protecciones comunes: un archivo dañado o malicioso NUNCA debe colgar ni
//! tumbar Vectopen. Cada importación corre en un hilo propio (pila grande,
//! *panics* capturados) con tiempo máximo; los límites cortan antes de reservar
//! memoria absurda.

use std::sync::mpsc;
use std::time::Duration;

/// Igual que io_guard.gd: más que esto no se intenta.
pub const MAX_FILE_BYTES: u64 = 512 * 1024 * 1024;
/// Píxeles máximos de una imagen incrustada o importada (≈ 16384 × 6100).
pub const MAX_IMAGE_PIXELS: u64 = 100_000_000;
/// Tiempo máximo de una importación.
pub const TIMEOUT: Duration = Duration::from_secs(90);
/// Pila del hilo de trabajo: los SVG muy anidados recurren mucho.
const STACK: usize = 256 * 1024 * 1024;

/// Ejecuta `job` aislado. Devuelve su resultado o un mensaje de error legible.
pub fn run_isolated<T: Send + 'static>(
    job: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    let (tx, rx) = mpsc::channel();
    let spawned = std::thread::Builder::new()
        .name("vectopen_io".into())
        .stack_size(STACK)
        .spawn(move || {
            let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(job));
            let _ = tx.send(r);
        });
    if let Err(e) = spawned {
        return Err(format!("no se pudo iniciar la importación: {e}"));
    }
    match rx.recv_timeout(TIMEOUT) {
        Ok(Ok(r)) => r,
        Ok(Err(p)) => Err(format!("el archivo está dañado o no es compatible ({})", panic_text(&p))),
        // El hilo sigue suelto hasta acabar, pero la app no se queda esperando.
        Err(mpsc::RecvTimeoutError::Timeout) => {
            Err(format!("se canceló: tardaba más de {} s", TIMEOUT.as_secs()))
        }
        Err(mpsc::RecvTimeoutError::Disconnected) => Err("la importación se interrumpió".into()),
    }
}

fn panic_text(p: &Box<dyn std::any::Any + Send>) -> String {
    if let Some(s) = p.downcast_ref::<&str>() {
        s.to_string()
    } else if let Some(s) = p.downcast_ref::<String>() {
        s.clone()
    } else {
        "error interno".into()
    }
}

/// Lee el archivo comprobando antes su tamaño.
pub fn read_file(path: &str) -> Result<Vec<u8>, String> {
    let name = file_name(path);
    let meta = std::fs::metadata(path).map_err(|e| format!("no se puede leer «{name}» ({e})"))?;
    if !meta.is_file() {
        return Err(format!("«{name}» no es un archivo"));
    }
    if meta.len() == 0 {
        return Err(format!("«{name}» está vacío"));
    }
    if meta.len() > MAX_FILE_BYTES {
        return Err(format!("«{name}» ocupa demasiado (máximo {} MB)", MAX_FILE_BYTES / 1024 / 1024));
    }
    std::fs::read(path).map_err(|e| format!("no se puede leer «{name}» ({e})"))
}

pub fn file_name(path: &str) -> String {
    std::path::Path::new(path)
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string())
}

/// Tipo real por los primeros bytes (como IoGuard.sniff).
pub fn sniff(b: &[u8]) -> &'static str {
    if b.starts_with(&[0xC5, 0xD0, 0xD3, 0xC6]) {
        return "eps_dos";
    }
    if b.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        return "png";
    }
    if b.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return "jpg";
    }
    if b.len() >= 12 && &b[0..4] == b"RIFF" && &b[8..12] == b"WEBP" {
        return "webp";
    }
    if b.starts_with(b"8BPS") {
        return "psd";
    }
    if b.starts_with(&[0x1F, 0x8B]) {
        return "gzip"; // .svgz
    }
    let head = &b[..b.len().min(4096)];
    let txt: String = head.iter().map(|&c| if c == 0 { ' ' } else { c as char }).collect();
    if txt.contains("%PDF") {
        return "pdf";
    }
    if txt.trim_start_matches('\u{feff}').trim_start().starts_with("%!") {
        return "ps";
    }
    if txt.contains("<svg") {
        return "svg";
    }
    ""
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sniff_reconoce_formatos() {
        assert_eq!(sniff(b"\x89PNG\r\n\x1a\nxxxx"), "png");
        assert_eq!(sniff(b"%PDF-1.7"), "pdf");
        assert_eq!(sniff(b"%!PS-Adobe-3.0 EPSF-3.0"), "ps");
        assert_eq!(sniff(b"<?xml version='1.0'?><svg>"), "svg");
        assert_eq!(sniff(b"8BPS\0\x01"), "psd");
        assert_eq!(sniff(b"hola"), "");
    }

    #[test]
    fn panic_se_convierte_en_error() {
        let r: Result<(), String> = run_isolated(|| panic!("roto"));
        assert!(r.unwrap_err().contains("roto"));
    }

    #[test]
    fn archivo_inexistente_da_error_legible() {
        assert!(read_file("/no/existe.svg").unwrap_err().contains("existe.svg"));
    }
}
