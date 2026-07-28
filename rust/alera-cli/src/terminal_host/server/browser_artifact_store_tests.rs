use super::*;

const REQUEST_1: &str = "00000000-0000-4000-8000-000000000001";
const REQUEST_2: &str = "00000000-0000-4000-8000-000000000002";
const REQUEST_3: &str = "00000000-0000-4000-8000-000000000003";
const REQUEST_4: &str = "00000000-0000-4000-8000-000000000004";

#[test]
fn reserves_private_ttl_artifacts_under_the_runtime_directory() {
    let runtime = tempfile::tempdir().unwrap();
    let store = BrowserArtifactStore::in_runtime_dir(runtime.path());
    let artifact = store.reserve(REQUEST_1, "png").unwrap();
    let marker = store.reservation_marker_path(&artifact.reservation_id, artifact.format);

    assert!(Path::new(&artifact.path).ends_with(format!("browser/artifacts/{REQUEST_1}.png")));
    assert!(!Path::new(&artifact.path).exists());
    assert!(marker.is_file());
    assert!(artifact.expires_at > Utc::now());
    std::fs::write(&artifact.path, b"png").unwrap();
    let completed = store.completed(artifact).unwrap();
    assert_eq!(completed.size_bytes, 3);
    assert_eq!(completed.mime_type, "image/png");
    assert_eq!(
        completed.suggested_file_name,
        format!("browser-screenshot-{REQUEST_1}.png")
    );
}

#[test]
fn reservation_names_are_exclusive() {
    let runtime = tempfile::tempdir().unwrap();
    let store = BrowserArtifactStore::in_runtime_dir(runtime.path());
    let artifact = store.reserve(REQUEST_1, "png").unwrap();

    let error = store.reserve(REQUEST_1, "png").unwrap_err();

    assert_eq!(error.kind(), std::io::ErrorKind::AlreadyExists);
    assert!(!Path::new(&artifact.path).exists());
    assert!(store
        .reservation_marker_path(&artifact.reservation_id, artifact.format)
        .is_file());
}

#[cfg(unix)]
#[test]
fn reserved_files_and_directory_are_owner_only() {
    use std::io::Write as _;
    use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};
    let runtime = tempfile::tempdir().unwrap();
    let store = BrowserArtifactStore::in_runtime_dir(runtime.path());
    let artifact = store.reserve(REQUEST_1, "pdf").unwrap();
    let path = Path::new(&artifact.path);
    let marker = store.reservation_marker_path(&artifact.reservation_id, artifact.format);
    assert!(!path.exists());
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
        .unwrap();
    file.write_all(b"pdf").unwrap();
    drop(file);

    let file_mode = std::fs::metadata(path).unwrap().permissions().mode() & 0o777;
    let dir_mode = std::fs::metadata(&store.directory)
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    let marker_mode = std::fs::metadata(marker).unwrap().permissions().mode() & 0o777;
    assert_eq!(file_mode, 0o600);
    assert_eq!(dir_mode, 0o700);
    assert_eq!(marker_mode, 0o600);
}

#[test]
fn exact_file_limit_is_accepted_and_excess_is_removed_immediately() {
    let runtime = tempfile::tempdir().unwrap();
    let store = BrowserArtifactStore::with_limits(runtime.path(), 4, 16);
    let exact = store.reserve(REQUEST_1, "png").unwrap();
    write_sparse_artifact(&exact, 4);

    assert_eq!(store.completed(exact).unwrap().size_bytes, 4);

    let oversized = store.reserve(REQUEST_2, "pdf").unwrap();
    let marker = store.reservation_marker_path(&oversized.reservation_id, oversized.format);
    write_sparse_artifact(&oversized, 5);
    assert_eq!(
        store.completed(oversized.clone()).unwrap_err(),
        BrowserArtifactCompletionError::FileTooLarge {
            size_bytes: 5,
            max_bytes: 4,
        }
    );
    assert!(!Path::new(&oversized.path).exists());
    assert!(!marker.exists());
}

#[test]
fn accumulated_quota_rejects_only_the_new_artifact_and_releases_capacity() {
    let runtime = tempfile::tempdir().unwrap();
    let store = BrowserArtifactStore::with_limits(runtime.path(), 8, 10);
    let first = store.reserve(REQUEST_1, "png").unwrap();
    write_sparse_artifact(&first, 6);
    store.completed(first.clone()).unwrap();

    let over_quota = store.reserve(REQUEST_2, "pdf").unwrap();
    let over_quota_marker =
        store.reservation_marker_path(&over_quota.reservation_id, over_quota.format);
    write_sparse_artifact(&over_quota, 5);
    assert_eq!(
        store.completed(over_quota.clone()).unwrap_err(),
        BrowserArtifactCompletionError::StoreQuotaExceeded {
            store_size_bytes: 11,
            max_bytes: 10,
        }
    );
    assert!(Path::new(&first.path).exists());
    assert!(!Path::new(&over_quota.path).exists());
    assert!(!over_quota_marker.exists());

    let exact_total = store.reserve(REQUEST_3, "png").unwrap();
    write_sparse_artifact(&exact_total, 4);
    assert_eq!(store.completed(exact_total).unwrap().size_bytes, 4);
    assert_eq!(
        store.reserve(REQUEST_4, "png").unwrap_err().kind(),
        std::io::ErrorKind::QuotaExceeded
    );

    store.remove(&first);
    let after_release = store.reserve(REQUEST_4, "png").unwrap();
    write_sparse_artifact(&after_release, 6);
    assert_eq!(store.completed(after_release).unwrap().size_bytes, 6);
}

#[test]
fn ttl_cleanup_removes_artifacts_and_releases_their_reservations() {
    let runtime = tempfile::tempdir().unwrap();
    let store = BrowserArtifactStore::with_limits(runtime.path(), 10, 10);
    let artifact = store.reserve(REQUEST_1, "png").unwrap();
    let marker = store.reservation_marker_path(&artifact.reservation_id, artifact.format);
    write_sparse_artifact(&artifact, 10);
    store.completed(artifact.clone()).unwrap();

    store.sweep_expired(SystemTime::now() + ARTIFACT_TTL + Duration::from_secs(1));

    assert!(!Path::new(&artifact.path).exists());
    assert!(!marker.exists());
    let replacement = store.reserve(REQUEST_2, "png").unwrap();
    write_sparse_artifact(&replacement, 10);
    assert_eq!(store.completed(replacement).unwrap().size_bytes, 10);
}

#[test]
fn removal_never_follows_an_artifact_path_outside_the_reservation() {
    let runtime = tempfile::tempdir().unwrap();
    let store = BrowserArtifactStore::in_runtime_dir(runtime.path());
    let artifact = store.reserve(REQUEST_1, "png").unwrap();
    let outside = runtime.path().join("outside.png");
    std::fs::write(&outside, b"keep").unwrap();
    let mut forged = artifact.clone();
    forged.path = outside.to_string_lossy().into_owned();

    store.remove(&forged);

    assert_eq!(std::fs::read(&outside).unwrap(), b"keep");
    assert!(store
        .reservation_marker_path(&artifact.reservation_id, artifact.format)
        .exists());
}

fn write_sparse_artifact(artifact: &BrowserArtifact, size_bytes: u64) {
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&artifact.path)
        .unwrap();
    file.set_len(size_bytes).unwrap();
}
