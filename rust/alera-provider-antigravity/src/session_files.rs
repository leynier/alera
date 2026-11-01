//! Removes the files a model probe's session leaves in the Antigravity
//! profile, after T3 Code's `removeAntigravitySessionFiles`.

use crate::{antigravity_user_home, AntigravityProviderConfig, GEMINI_HOME_ENV};
use std::ffi::OsStr;
use std::path::{Path, PathBuf};

/// The profile root the runtime keeps sessions under: the configured profile
/// directory, else `GEMINI_HOME`, else `~/.gemini`.
pub fn profile_root(config: &AntigravityProviderConfig) -> Option<PathBuf> {
    if let Some(profile) = &config.profile_dir {
        return Some(profile.clone());
    }
    let gemini_home = config
        .env
        .get(OsStr::new(GEMINI_HOME_ENV))
        .cloned()
        .or_else(|| std::env::var_os(GEMINI_HOME_ENV))
        .filter(|value| !value.is_empty());
    if let Some(home) = gemini_home {
        return Some(PathBuf::from(home));
    }
    antigravity_user_home(config).map(|home| home.join(".gemini"))
}

fn is_uuid_v4(id: &str) -> bool {
    let bytes = id.as_bytes();
    bytes.len() == 36
        && bytes.iter().enumerate().all(|(index, byte)| match index {
            8 | 13 | 18 | 23 => *byte == b'-',
            14 => *byte == b'4',
            _ => byte.is_ascii_hexdigit(),
        })
}

/// Removes session `id`'s conversation files and brain directory, only when
/// its `.meta` records `cwd`, the probe's private working directory, which
/// proves the probe owns it.
pub fn remove_session_files(root: &Path, id: &str, cwd: &Path) {
    if !is_uuid_v4(id) {
        return;
    }
    let acp = root.join("antigravity-acp");
    let base = acp.join("conversations").join(id);
    let meta = base.with_extension("meta");
    let Ok(text) = std::fs::read_to_string(&meta) else {
        return;
    };
    let recorded = serde_json::from_str::<serde_json::Value>(&text)
        .ok()
        .and_then(|meta| {
            meta.get("cwd")
                .and_then(|cwd| cwd.as_str())
                .map(PathBuf::from)
        });
    if recorded.as_deref() != Some(cwd) {
        return;
    }
    for suffix in ["db", "db-wal", "db-shm", "db-journal", "meta"] {
        let _ = std::fs::remove_file(base.with_extension(suffix));
    }
    let _ = std::fs::remove_dir_all(acp.join("brain").join(id));
}
