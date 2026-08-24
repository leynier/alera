/// Retarget a workspace-relative path when a file or directory is moved.
///
/// Exact matches and descendants are rewritten. Similar sibling names are
/// deliberately ignored so moving `src` cannot retarget `src-old`.
pub fn replace_workspace_path_prefix(path: &str, old_path: &str, new_path: &str) -> Option<String> {
    let path = path.trim_matches('/');
    let old_path = old_path.trim_matches('/');
    let new_path = new_path.trim_matches('/');
    if old_path.is_empty() || new_path.is_empty() {
        return None;
    }
    if path == old_path {
        return Some(new_path.to_string());
    }
    path.strip_prefix(old_path)
        .and_then(|suffix| suffix.strip_prefix('/'))
        .map(|suffix| format!("{new_path}/{suffix}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_move_retargets_exact_paths_and_descendants_only() {
        assert_eq!(
            replace_workspace_path_prefix("src", "src", "lib"),
            Some("lib".to_string())
        );
        assert_eq!(
            replace_workspace_path_prefix("src/app/main.rs", "/src/", "/lib/"),
            Some("lib/app/main.rs".to_string())
        );
        assert_eq!(
            replace_workspace_path_prefix("src-old/main.rs", "src", "lib"),
            None
        );
        assert_eq!(replace_workspace_path_prefix("src", "", "lib"), None);
    }
}
