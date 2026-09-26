//! One spelling for Windows paths that leave this machine.
//!
//! `std::fs::canonicalize` answers in the verbatim form on Windows
//! (`\\?\C:\Users\...`). That form is valid for file APIs but not as a process
//! working directory, so a checkout reported that way gives a remote terminal
//! that silently opens in the user's home instead of the workspace, which is
//! what the first real Windows run showed. Paths that are reported to a hub or
//! stored as a workspace location go through [`canonicalize`], which keeps the
//! legacy form whenever the path can be written that way.
//!
//! Records written before this existed hold the verbatim spelling, so identity
//! checks compare with [`same_path`] instead of `==`: the same folder must not
//! read as "a different directory" because it was spelled the other way.

use std::path::{Path, PathBuf};

pub(crate) fn canonicalize(path: impl AsRef<Path>) -> std::io::Result<PathBuf> {
    dunce::canonicalize(path)
}

/// `path` without the verbatim prefix, when it has one that can be dropped.
/// A verbatim UNC path keeps its meaning as `\\server\share`.
pub(crate) fn plain(path: &str) -> std::borrow::Cow<'_, str> {
    if let Some(rest) = path.strip_prefix(r"\\?\UNC\") {
        return std::borrow::Cow::Owned(format!(r"\\{rest}"));
    }
    match path.strip_prefix(r"\\?\") {
        Some(rest) => std::borrow::Cow::Borrowed(rest),
        None => std::borrow::Cow::Borrowed(path),
    }
}

pub(crate) fn same_path(left: &str, right: &str) -> bool {
    left == right || plain(left) == plain(right)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_folder_is_the_same_folder_in_either_spelling() {
        assert!(same_path(r"\\?\C:\Users\me\repo", r"C:\Users\me\repo"));
        assert!(same_path(r"C:\Users\me\repo", r"\\?\C:\Users\me\repo"));
        assert!(same_path(
            r"\\?\UNC\server\share\repo",
            r"\\server\share\repo"
        ));
        assert!(same_path("/home/me/repo", "/home/me/repo"));
        assert!(!same_path(r"\\?\C:\Users\me\repo", r"C:\Users\me\other"));
        assert!(!same_path("/home/me/repo", "/home/me/repo2"));
    }

    #[test]
    fn posix_paths_are_left_alone() {
        assert_eq!(plain("/home/me/repo"), "/home/me/repo");
        assert_eq!(plain(r"C:\Users\me"), r"C:\Users\me");
    }
}
