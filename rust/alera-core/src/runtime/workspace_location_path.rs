/// Tab paths belong to the checkout's host, which may use a different path
/// syntax from the machine storing runtime state.
pub fn relocated_path(path: &str, source: &str, destination: &str) -> Option<String> {
    if is_windows_root(source) {
        let path = windows_path(path);
        let source = windows_path(source);
        let source = source.trim_end_matches('/');
        if path.len() < source.len()
            || !path.get(..source.len())?.eq_ignore_ascii_case(source)
            || (path.len() != source.len() && path.as_bytes()[source.len()] != b'/')
        {
            return None;
        }
        let relative = path[source.len()..].trim_start_matches('/');
        let destination = destination.trim_end_matches(['/', '\\']);
        if relative.is_empty() {
            return Some(destination.to_string());
        }
        let separator = if destination.contains('\\') {
            '\\'
        } else {
            '/'
        };
        return Some(format!(
            "{destination}{separator}{}",
            relative.replace('/', &separator.to_string())
        ));
    }
    let source = source.trim_end_matches('/');
    let relative = path.strip_prefix(source)?;
    if !relative.is_empty() && !relative.starts_with('/') {
        return None;
    }
    let relative = relative.trim_start_matches('/');
    if relative.is_empty() {
        Some(destination.to_string())
    } else {
        Some(format!("{}/{relative}", destination.trim_end_matches('/')))
    }
}

fn is_windows_root(path: &str) -> bool {
    let bytes = path.as_bytes();
    path.starts_with("\\\\")
        || (bytes.len() >= 3
            && bytes[0].is_ascii_alphabetic()
            && bytes[1] == b':'
            && matches!(bytes[2], b'/' | b'\\'))
}

fn windows_path(path: &str) -> String {
    let path = path.strip_prefix("\\\\?\\").unwrap_or(path);
    if let Some(unc) = path.strip_prefix("UNC\\") {
        return format!("//{}", unc.replace('\\', "/"));
    }
    path.replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::relocated_path;

    #[test]
    fn paths_follow_the_owning_host_and_component_boundaries() {
        for (path, source, destination, expected) in [
            (
                "/repo/src/file",
                "/repo",
                "/worktree",
                Some("/worktree/src/file"),
            ),
            ("/repo-sibling/file", "/repo", "/worktree", None),
            ("/REPO/file", "/repo", "/worktree", None),
            (
                r"C:\Repo\src\file",
                r"c:\repo",
                r"D:\Worktree",
                Some(r"D:\Worktree\src\file"),
            ),
            (
                "C:/REPO/src/file",
                r"\\?\C:\repo",
                "D:/worktree",
                Some("D:/worktree/src/file"),
            ),
            (r"C:\repo-other\file", r"C:\repo", r"D:\worktree", None),
            (
                r"\\server\share\repo\file",
                r"\\?\UNC\server\share\repo",
                r"\\server\share\worktree",
                Some(r"\\server\share\worktree\file"),
            ),
            (r"D:\repo\file", r"C:\repo", r"D:\worktree", None),
        ] {
            assert_eq!(
                relocated_path(path, source, destination).as_deref(),
                expected,
                "{path}"
            );
        }
    }
}
