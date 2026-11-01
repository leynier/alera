//! Reads one piece of an image a provider generated, from the path its
//! stored item recorded. The path must be absolute and name a regular file
//! no larger than 16 MiB whose bytes are PNG, JPEG, GIF or WEBP; the file
//! is opened without following a final symlink and checked to be the one
//! the path names, and a file that changes mid-read is refused.

use std::fs::{File, Metadata};
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

pub(crate) const MAX_GENERATED_IMAGE_BYTES: u64 = 16 * 1024 * 1024;
/// One piece; base64 keeps it inside the phone relay's 1 MiB envelope.
pub(crate) const MAX_GENERATED_IMAGE_PIECE: u64 = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ImageReadError {
    InvalidPath,
    NotFound,
    NotRegularFile,
    ImageTooLarge,
    UnsupportedImage,
    ChangedDuringRead,
    ReadFailed,
}

impl ImageReadError {
    pub(crate) fn code(self) -> &'static str {
        match self {
            Self::InvalidPath => "invalidPath",
            Self::NotFound => "notFound",
            Self::NotRegularFile => "notRegularFile",
            Self::ImageTooLarge => "imageTooLarge",
            Self::UnsupportedImage => "unsupportedImage",
            Self::ChangedDuringRead => "changedDuringRead",
            Self::ReadFailed => "readFailed",
        }
    }

    pub(crate) fn message(self) -> &'static str {
        match self {
            Self::InvalidPath => "The generated image path is not absolute.",
            Self::NotFound => "The generated image is no longer on disk.",
            Self::NotRegularFile => "The generated image path is not a regular file.",
            Self::ImageTooLarge => "The generated image is larger than 16 MiB.",
            Self::UnsupportedImage => "The generated image is not a PNG, JPEG, GIF or WEBP file.",
            Self::ChangedDuringRead => "The generated image changed while it was read.",
            Self::ReadFailed => "The generated image could not be read.",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ImagePiece {
    pub(crate) mime_type: &'static str,
    pub(crate) size_bytes: u64,
    pub(crate) offset: u64,
    pub(crate) next_offset: u64,
    /// Names the file's version, so pieces of different versions never mix.
    pub(crate) content_token: String,
    pub(crate) bytes: Vec<u8>,
}

/// Up to [length] bytes of the image at [path] from [offset]. Blocking.
pub(crate) fn read_image_piece(
    path: &Path,
    offset: u64,
    length: u64,
) -> Result<ImagePiece, ImageReadError> {
    if !path.is_absolute() {
        return Err(ImageReadError::InvalidPath);
    }
    let canonical = std::fs::canonicalize(path).map_err(io_error)?;
    let named = std::fs::symlink_metadata(&canonical).map_err(io_error)?;
    if !named.file_type().is_file() {
        return Err(ImageReadError::NotRegularFile);
    }
    if named.len() > MAX_GENERATED_IMAGE_BYTES {
        return Err(ImageReadError::ImageTooLarge);
    }
    let mut file = open_no_follow(&canonical)?;
    let opened = file.metadata().map_err(io_error)?;
    if !opened.is_file() || !same_file(&named, &opened) {
        return Err(ImageReadError::ChangedDuringRead);
    }
    let size = opened.len();
    let mut magic = [0_u8; 12];
    let read = read_up_to(&mut file, &mut magic)?;
    let mime_type = image_mime_type(&magic[..read]).ok_or(ImageReadError::UnsupportedImage)?;
    let offset = offset.min(size);
    let length = length
        .clamp(1, MAX_GENERATED_IMAGE_PIECE)
        .min(size - offset);
    file.seek(SeekFrom::Start(offset)).map_err(io_error)?;
    let mut bytes = vec![0_u8; length as usize];
    file.read_exact(&mut bytes)
        .map_err(|_| ImageReadError::ChangedDuringRead)?;
    let after = file.metadata().map_err(io_error)?;
    if version(&after) != version(&opened) {
        return Err(ImageReadError::ChangedDuringRead);
    }
    Ok(ImagePiece {
        mime_type,
        size_bytes: size,
        offset,
        next_offset: offset + length,
        content_token: version(&opened),
        bytes,
    })
}

pub(crate) fn image_mime_type(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        Some("image/jpeg")
    } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        Some("image/gif")
    } else if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("image/webp")
    } else {
        None
    }
}

fn read_up_to(file: &mut File, buffer: &mut [u8]) -> Result<usize, ImageReadError> {
    let mut read = 0;
    while read < buffer.len() {
        match file.read(&mut buffer[read..]).map_err(io_error)? {
            0 => break,
            count => read += count,
        }
    }
    Ok(read)
}

fn io_error(error: std::io::Error) -> ImageReadError {
    match error.kind() {
        std::io::ErrorKind::NotFound => ImageReadError::NotFound,
        _ => ImageReadError::ReadFailed,
    }
}

#[cfg(unix)]
fn open_no_follow(path: &Path) -> Result<File, ImageReadError> {
    use std::os::unix::fs::OpenOptionsExt;
    std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)
        .map_err(|error| match error.raw_os_error() {
            Some(libc::ELOOP) => ImageReadError::NotRegularFile,
            _ => io_error(error),
        })
}

#[cfg(not(unix))]
fn open_no_follow(path: &Path) -> Result<File, ImageReadError> {
    File::open(path).map_err(io_error)
}

#[cfg(unix)]
fn same_file(named: &Metadata, opened: &Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;
    named.dev() == opened.dev() && named.ino() == opened.ino()
}

#[cfg(not(unix))]
fn same_file(named: &Metadata, opened: &Metadata) -> bool {
    named.len() == opened.len() && named.modified().ok() == opened.modified().ok()
}

fn version(metadata: &Metadata) -> String {
    let modified = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |since| since.as_nanos());
    #[cfg(unix)]
    let inode = {
        use std::os::unix::fs::MetadataExt;
        metadata.ino()
    };
    #[cfg(not(unix))]
    let inode = 0_u64;
    format!("{}-{modified}-{inode}", metadata.len())
}

#[cfg(test)]
#[path = "generated_image_files_tests.rs"]
mod tests;
