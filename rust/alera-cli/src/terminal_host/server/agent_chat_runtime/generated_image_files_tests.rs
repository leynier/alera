use super::*;

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n0123456789";

fn image(dir: &Path, name: &str, bytes: &[u8]) -> std::path::PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, bytes).unwrap();
    path
}

#[test]
fn an_image_is_read_in_pieces_with_one_version() {
    let dir = tempfile::tempdir().unwrap();
    let path = image(dir.path(), "a.png", PNG);
    let first = read_image_piece(&path, 0, 10).unwrap();
    assert_eq!(first.mime_type, "image/png");
    assert_eq!(first.size_bytes, PNG.len() as u64);
    assert_eq!(first.bytes, &PNG[..10]);
    assert_eq!(first.next_offset, 10);
    let second = read_image_piece(&path, first.next_offset, 1024).unwrap();
    assert_eq!(second.bytes, &PNG[10..]);
    assert_eq!(second.next_offset, second.size_bytes);
    assert_eq!(first.content_token, second.content_token);
}

#[test]
fn unsafe_or_unexpected_files_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    assert_eq!(
        read_image_piece(Path::new("relative.png"), 0, 10),
        Err(ImageReadError::InvalidPath)
    );
    assert_eq!(
        read_image_piece(&dir.path().join("gone.png"), 0, 10),
        Err(ImageReadError::NotFound)
    );
    assert_eq!(
        read_image_piece(dir.path(), 0, 10),
        Err(ImageReadError::NotRegularFile)
    );
    let text = image(dir.path(), "a.txt", b"not an image at all");
    assert_eq!(
        read_image_piece(&text, 0, 10),
        Err(ImageReadError::UnsupportedImage)
    );
    let big = dir.path().join("big.png");
    let file = std::fs::File::create(&big).unwrap();
    file.set_len(MAX_GENERATED_IMAGE_BYTES + 1).unwrap();
    assert_eq!(
        read_image_piece(&big, 0, 10),
        Err(ImageReadError::ImageTooLarge)
    );
}

#[test]
fn image_types_are_read_from_their_bytes() {
    assert_eq!(image_mime_type(b"\xff\xd8\xff\xe0"), Some("image/jpeg"));
    assert_eq!(image_mime_type(b"GIF89a.."), Some("image/gif"));
    assert_eq!(image_mime_type(b"RIFF\0\0\0\0WEBPVP8 "), Some("image/webp"));
    assert_eq!(image_mime_type(b"<svg"), None);
}
