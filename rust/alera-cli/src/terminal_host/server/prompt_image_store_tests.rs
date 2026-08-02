use std::path::Path;
use std::time::{Duration, SystemTime};

use super::*;

fn complete_png(store: &PromptImageStore, size: u64) -> (PromptImageReservation, String) {
    let reservation = store.start("png", size).unwrap();
    let mut bytes = vec![0_u8; size as usize];
    bytes[..8].copy_from_slice(b"\x89PNG\r\n\x1a\n");
    store
        .append_chunk(&reservation.upload_id, 0, &bytes)
        .unwrap();
    let path = store.complete(&reservation.upload_id).unwrap();
    (reservation, path)
}

#[test]
fn generates_private_uuid_paths_and_host_owned_extensions() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::in_runtime_dir(runtime.path());
    let (reservation, path) = complete_png(&store, 8);

    assert!(Uuid::parse_str(&reservation.upload_id).is_ok());
    assert!(Path::new(&path).is_absolute());
    assert!(path.ends_with(".png"));
    assert!(!path.contains("caller"));
    assert!(!store.partial_path(&reservation.upload_id).exists());
    assert!(store.metadata_path(&reservation.upload_id).is_file());
}

#[test]
fn jpeg_uses_a_host_generated_jpg_extension() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::in_runtime_dir(runtime.path());
    let reservation = store.start("jpeg", 3).unwrap();
    store
        .append_chunk(&reservation.upload_id, 0, &[0xff, 0xd8, 0xff])
        .unwrap();

    let path = store.complete(&reservation.upload_id).unwrap();

    assert!(path.ends_with(".jpg"));
}

#[test]
fn enforces_sequential_offsets_and_chunk_limits() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::with_limits(runtime.path(), 8, 16);
    let reservation = store.start("gif", 6).unwrap();

    assert_eq!(store.append_chunk(&reservation.upload_id, 0, b"GIF"), Ok(3));
    assert_eq!(
        store.append_chunk(&reservation.upload_id, 0, b"89a"),
        Err(PromptImageStoreError::InvalidOffset {
            offset: 0,
            actual: 3
        })
    );
    assert_eq!(
        store.append_chunk(
            &reservation.upload_id,
            3,
            &vec![0_u8; MAX_PROMPT_IMAGE_CHUNK_BYTES + 1],
        ),
        Err(PromptImageStoreError::ChunkTooLarge {
            size_bytes: MAX_PROMPT_IMAGE_CHUNK_BYTES + 1,
            max_bytes: MAX_PROMPT_IMAGE_CHUNK_BYTES,
        })
    );
    assert_eq!(store.append_chunk(&reservation.upload_id, 3, b"bad"), Ok(6));
    assert_eq!(
        store.complete(&reservation.upload_id),
        Err(PromptImageStoreError::FormatMismatch)
    );
    assert!(!store.metadata_path(&reservation.upload_id).exists());
    assert!(!store.partial_path(&reservation.upload_id).exists());
}

#[test]
fn rejects_empty_oversized_and_declared_length_overflow() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::with_limits(runtime.path(), 4, 16);

    assert_eq!(store.start("png", 0), Err(PromptImageStoreError::Empty));
    assert_eq!(
        store.start("png", 5),
        Err(PromptImageStoreError::FileTooLarge {
            size_bytes: 5,
            max_bytes: 4,
        })
    );
    let reservation = store.start("png", 4).unwrap();
    assert_eq!(
        store.append_chunk(&reservation.upload_id, 0, b"12345"),
        Err(PromptImageStoreError::DeclaredLengthExceeded)
    );
}

#[test]
fn declared_partial_bytes_count_against_the_store_quota() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::with_limits(runtime.path(), 8, 10);
    let first = store.start("png", 6).unwrap();

    assert_eq!(
        store.start("png", 5),
        Err(PromptImageStoreError::StoreQuotaExceeded {
            size_bytes: 11,
            max_bytes: 10,
        })
    );
    store.cancel(&first.upload_id).unwrap();
    let replacement = store.start("png", 8).unwrap();
    assert_ne!(first.upload_id, replacement.upload_id);
}

#[test]
fn completion_validates_supported_magic_and_failed_completion_cleans_state() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::in_runtime_dir(runtime.path());
    let reservation = store.start("webp", 12).unwrap();
    store
        .append_chunk(&reservation.upload_id, 0, b"RIFF0000WEBP")
        .unwrap();

    assert!(store.complete(&reservation.upload_id).is_ok());

    let malformed = store.start("png", 8).unwrap();
    store
        .append_chunk(&malformed.upload_id, 0, b"badmagic")
        .unwrap();
    assert_eq!(
        store.complete(&malformed.upload_id),
        Err(PromptImageStoreError::FormatMismatch)
    );
    assert!(!store.metadata_path(&malformed.upload_id).exists());
    assert!(!store.partial_path(&malformed.upload_id).exists());
}

#[test]
fn cancel_removes_partial_metadata_and_final_state() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::in_runtime_dir(runtime.path());
    let (reservation, _) = complete_png(&store, 8);

    store.cancel(&reservation.upload_id).unwrap();

    assert!(!store.metadata_path(&reservation.upload_id).exists());
    assert!(!store.partial_path(&reservation.upload_id).exists());
    assert!(!store
        .final_path(&reservation.upload_id, PromptImageFormat::Png)
        .exists());
}

#[test]
fn ttl_cleanup_removes_partial_and_completed_files() {
    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::with_limits(runtime.path(), 8, 16);
    let partial = store.start("png", 8).unwrap();
    let (completed, _) = complete_png(&store, 8);

    store.sweep_expired(SystemTime::now() + IMAGE_TTL + Duration::from_secs(1));

    assert!(!store.metadata_path(&partial.upload_id).exists());
    assert!(!store.partial_path(&partial.upload_id).exists());
    assert!(!store.metadata_path(&completed.upload_id).exists());
    assert!(!store
        .final_path(&completed.upload_id, PromptImageFormat::Png)
        .exists());
}

#[cfg(unix)]
#[test]
fn directory_metadata_and_partial_files_are_owner_only() {
    use std::os::unix::fs::PermissionsExt as _;

    let runtime = tempfile::tempdir().unwrap();
    let store = PromptImageStore::in_runtime_dir(runtime.path());
    let reservation = store.start("png", 8).unwrap();
    let directory_mode = std::fs::metadata(&store.directory)
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    let partial_mode = std::fs::metadata(store.partial_path(&reservation.upload_id))
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    let metadata_mode = std::fs::metadata(store.metadata_path(&reservation.upload_id))
        .unwrap()
        .permissions()
        .mode()
        & 0o777;

    assert_eq!(directory_mode, 0o700);
    assert_eq!(partial_mode, 0o600);
    assert_eq!(metadata_mode, 0o600);
}

#[cfg(unix)]
#[test]
fn never_follows_a_partial_symlink() {
    use std::os::unix::fs::symlink;

    let runtime = tempfile::tempdir().unwrap();
    let outside = runtime.path().join("outside");
    std::fs::write(&outside, b"keep").unwrap();
    let store = PromptImageStore::in_runtime_dir(runtime.path());
    let reservation = store.start("png", 8).unwrap();
    let partial = store.partial_path(&reservation.upload_id);
    std::fs::remove_file(&partial).unwrap();
    symlink(&outside, &partial).unwrap();

    assert_eq!(
        store.append_chunk(&reservation.upload_id, 0, b"changed"),
        Err(PromptImageStoreError::Missing)
    );
    assert_eq!(std::fs::read(&outside).unwrap(), b"keep");
}
