//! The workspace root Muse validates: canonical, in the disk's own case.

use std::path::Path;

/// Native canonicalization fixes the case of case-insensitive volumes as
/// well as resolving symlinks. On Windows Muse takes only the verbatim
/// `\\?\` form, which `canonicalize` already returns. A root that cannot be
/// resolved is kept as given.
pub(crate) async fn workspace_root(path: &Path) -> String {
    match tokio::fs::canonicalize(path).await {
        Ok(canonical) => canonical.to_string_lossy().into_owned(),
        Err(_) => unresolved_root(&path.to_string_lossy()),
    }
}

#[cfg(windows)]
fn unresolved_root(path: &str) -> String {
    // A verbatim path takes `/` literally, so it needs Windows separators.
    verbatim_path(&path.replace('/', "\\"))
}

#[cfg(not(windows))]
fn unresolved_root(path: &str) -> String {
    path.to_owned()
}

#[cfg_attr(not(any(windows, test)), allow(dead_code))]
fn verbatim_path(path: &str) -> String {
    if path.starts_with(r"\\?\") {
        path.to_owned()
    } else if let Some(share) = path.strip_prefix(r"\\") {
        format!(r"\\?\UNC\{share}")
    } else {
        format!(r"\\?\{path}")
    }
}

#[cfg(test)]
mod tests {
    use super::verbatim_path;

    #[test]
    fn writes_windows_paths_in_their_verbatim_form() {
        assert_eq!(
            verbatim_path(r"C:\Users\Person\repo"),
            r"\\?\C:\Users\Person\repo"
        );
        assert_eq!(
            verbatim_path(r"\\server\share\repo"),
            r"\\?\UNC\server\share\repo"
        );
        assert_eq!(verbatim_path(r"\\?\C:\repo"), r"\\?\C:\repo");
    }
}
