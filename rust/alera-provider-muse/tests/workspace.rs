mod support;

use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{Provider, SessionStartInput};
use std::path::{Path, PathBuf};
use support::{initialize_response, session_response, ScriptedTransport};

async fn session_start_root(cwd: &Path) -> String {
    let transport =
        ScriptedTransport::new([initialize_response(), session_response(2, "muse-session")]);
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.cwd = Some(cwd.to_path_buf());
    let session = provider.start_session(input).await.unwrap();
    assert_eq!(session.cwd.as_deref(), Some(cwd));
    provider.close().await.unwrap();
    let frame = writes.lock().unwrap()[2].clone();
    assert_eq!(frame["method"], "session/start");
    frame["params"]["workspaceRoot"]
        .as_str()
        .expect("workspaceRoot")
        .to_owned()
}

fn scratch_dir(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("{name}-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&path).unwrap();
    path
}

#[tokio::test]
async fn session_root_is_the_canonical_directory() {
    let root = scratch_dir("MuseRoot");
    let nested = root.join("Project");
    std::fs::create_dir(&nested).unwrap();
    let indirect = nested.join("..").join("Project");
    let canonical = std::fs::canonicalize(&nested).unwrap();
    assert_eq!(
        session_start_root(&indirect).await,
        canonical.to_string_lossy()
    );
    #[cfg(unix)]
    {
        let link = root.join("link");
        std::os::unix::fs::symlink(&nested, &link).unwrap();
        assert_eq!(session_start_root(&link).await, canonical.to_string_lossy());
    }
    // Only a case-insensitive volume resolves a miscased path; Muse takes the disk's case.
    let miscased = PathBuf::from(nested.to_string_lossy().to_uppercase());
    if miscased != nested && miscased.exists() {
        let root = session_start_root(&miscased).await;
        assert_eq!(Path::new(&root).file_name().unwrap(), "Project");
    }
    std::fs::remove_dir_all(&root).unwrap();
}

#[cfg(not(windows))]
#[tokio::test]
async fn session_root_it_cannot_resolve_is_kept_as_given() {
    let missing = std::env::temp_dir()
        .join(format!("muse-missing-{}", uuid::Uuid::new_v4()))
        .join("repo");
    assert_eq!(
        session_start_root(&missing).await,
        missing.to_string_lossy()
    );
}

#[cfg(windows)]
#[tokio::test]
async fn session_root_it_cannot_resolve_is_kept_in_verbatim_form() {
    assert_eq!(
        session_start_root(Path::new("C:/definitely-missing/repo")).await,
        r"\\?\C:\definitely-missing\repo"
    );
}
