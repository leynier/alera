#[cfg(any(not(target_os = "linux"), test))]
use std::fs;
#[cfg(any(not(target_os = "linux"), test))]
use std::io::{BufWriter, Write};
#[cfg(not(target_os = "linux"))]
use std::path::Path;
#[cfg(any(not(target_os = "linux"), test))]
use std::path::PathBuf;
#[cfg(not(target_os = "linux"))]
use std::time::{Duration, SystemTime};

#[cfg(not(target_os = "linux"))]
use arboard::{Clipboard, Error as ArboardError};
#[cfg(any(not(target_os = "linux"), test))]
use tempfile::Builder;

#[cfg(any(not(target_os = "linux"), test))]
const CLIPBOARD_IMAGE_MAX_PIXELS: usize = 32 * 1024 * 1024;
#[cfg(any(not(target_os = "linux"), test))]
const CLIPBOARD_IMAGE_MAX_PNG_BYTES: u64 = 18 * 1024 * 1024;
#[cfg(not(target_os = "linux"))]
const CLIPBOARD_IMAGE_MAX_AGE: Duration = Duration::from_secs(24 * 60 * 60);
#[cfg(any(not(target_os = "linux"), test))]
const CLIPBOARD_IMAGE_PREFIX: &str = "alera-paste-";

/// Saves an image-only clipboard payload as a private temporary PNG.
///
/// Returns `Ok(None)` when the clipboard has no image representation. The
/// bridge runs this synchronous function off the Flutter UI isolate.
pub fn save_clipboard_image_as_temp_file() -> Result<Option<String>, String> {
    #[cfg(target_os = "linux")]
    {
        Err("Linux clipboard images are handled by the GTK runner.".to_string())
    }
    #[cfg(not(target_os = "linux"))]
    {
        let mut clipboard = Clipboard::new().map_err(clipboard_error)?;
        let image = match clipboard.get_image() {
            Ok(image) => image,
            Err(ArboardError::ContentNotAvailable) => return Ok(None),
            Err(error) => return Err(clipboard_error(error)),
        };
        cleanup_expired_clipboard_images();
        let path = write_clipboard_png(image.width, image.height, image.bytes.as_ref())?;
        Ok(Some(path.to_string_lossy().into_owned()))
    }
}

#[cfg(not(target_os = "linux"))]
fn clipboard_error(error: ArboardError) -> String {
    format!("Clipboard image unavailable: {error}")
}

#[cfg(any(not(target_os = "linux"), test))]
fn write_clipboard_png(width: usize, height: usize, bytes: &[u8]) -> Result<PathBuf, String> {
    let pixel_count = width
        .checked_mul(height)
        .ok_or_else(|| "Clipboard image is too large.".to_string())?;
    if width == 0 || height == 0 || pixel_count > CLIPBOARD_IMAGE_MAX_PIXELS {
        return Err("Clipboard image is too large.".to_string());
    }
    let expected_bytes = pixel_count
        .checked_mul(4)
        .ok_or_else(|| "Clipboard image is too large.".to_string())?;
    if bytes.len() != expected_bytes {
        return Err("Clipboard image data is invalid.".to_string());
    }

    let mut file = Builder::new()
        .prefix(CLIPBOARD_IMAGE_PREFIX)
        .suffix(".png")
        .tempfile()
        .map_err(|error| format!("Could not create clipboard image: {error}"))?;
    {
        let mut encoder = png::Encoder::new(
            BufWriter::new(file.as_file_mut()),
            width as u32,
            height as u32,
        );
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder
            .write_header()
            .map_err(|error| format!("Could not encode clipboard image: {error}"))?;
        writer
            .write_image_data(bytes)
            .map_err(|error| format!("Could not encode clipboard image: {error}"))?;
        writer
            .finish()
            .map_err(|error| format!("Could not encode clipboard image: {error}"))?;
    }
    file.as_file_mut()
        .flush()
        .map_err(|error| format!("Could not save clipboard image: {error}"))?;
    let encoded_bytes = file
        .as_file()
        .metadata()
        .map_err(|error| format!("Could not inspect clipboard image: {error}"))?
        .len();
    if encoded_bytes > CLIPBOARD_IMAGE_MAX_PNG_BYTES {
        return Err("Clipboard image is too large.".to_string());
    }
    file.into_temp_path()
        .keep()
        .map_err(|error| format!("Could not retain clipboard image: {error}"))
}

#[cfg(not(target_os = "linux"))]
fn cleanup_expired_clipboard_images() {
    let Ok(entries) = fs::read_dir(std::env::temp_dir()) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !is_expired_clipboard_image(&path) {
            continue;
        }
        let _ = fs::remove_file(path);
    }
}

#[cfg(not(target_os = "linux"))]
fn is_expired_clipboard_image(path: &Path) -> bool {
    let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
        return false;
    };
    if !name.starts_with(CLIPBOARD_IMAGE_PREFIX) || !name.ends_with(".png") {
        return false;
    }
    let Ok(modified) = path.metadata().and_then(|metadata| metadata.modified()) else {
        return false;
    };
    SystemTime::now()
        .duration_since(modified)
        .is_ok_and(|age| age > CLIPBOARD_IMAGE_MAX_AGE)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_private_png_temp_file() {
        let path = write_clipboard_png(1, 1, &[255, 0, 0, 255]).expect("png");
        let bytes = fs::read(&path).expect("read png");
        assert_eq!(&bytes[..8], b"\x89PNG\r\n\x1a\n");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(fs::metadata(&path).unwrap().permissions().mode() & 0o077, 0);
        }
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn rejects_invalid_or_oversized_images() {
        assert!(write_clipboard_png(1, 1, &[0, 0, 0]).is_err());
        assert!(write_clipboard_png(CLIPBOARD_IMAGE_MAX_PIXELS + 1, 1, &[]).is_err());
    }
}
