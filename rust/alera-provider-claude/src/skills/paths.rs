//! Node `path` semantics the skill loader relies on: `join` and `resolve`
//! normalize lexically, `realpath` follows links, and text files decode the
//! way `TextDecoder` does (lossy, leading byte order mark dropped).

use alera_provider_protocol::is_mention_space;
use std::cmp::Ordering;
use std::path::{Component, Path, PathBuf};

/// [path] without `.` segments and with `..` applied, as `path.normalize`.
pub(crate) fn normalize(path: &Path) -> PathBuf {
    let mut normalized = PathBuf::new();
    let mut depth = 0usize;
    for component in path.components() {
        match component {
            Component::Prefix(_) | Component::RootDir => normalized.push(component),
            Component::CurDir => {}
            Component::ParentDir if depth > 0 => {
                normalized.pop();
                depth -= 1;
            }
            Component::ParentDir if path.has_root() => {}
            Component::ParentDir => normalized.push(".."),
            Component::Normal(part) => {
                normalized.push(part);
                depth += 1;
            }
        }
    }
    normalized
}

/// `path.join(base, ...parts)`.
pub(crate) fn join(base: &Path, parts: &[&str]) -> PathBuf {
    let mut joined = base.to_path_buf();
    for part in parts {
        joined.push(part);
    }
    normalize(&joined)
}

/// `path.resolve(base ?? ".", path)`: absolute, against the process cwd last.
pub(crate) fn resolve(base: Option<&Path>, path: &Path) -> PathBuf {
    let mut resolved = base.unwrap_or(Path::new(".")).join(path);
    if !resolved.is_absolute() {
        if let Ok(current) = std::env::current_dir() {
            resolved = current.join(resolved);
        }
    }
    normalize(&resolved)
}

/// `fs.realpath`, or `None` when the path does not exist.
pub(crate) fn real_path(path: &Path) -> Option<PathBuf> {
    let canonical = std::fs::canonicalize(path).ok()?;
    // Windows answers with a verbatim `\\?\C:\` path that never equals a lexical one.
    let text = canonical.to_string_lossy();
    if let Some(rest) = text.strip_prefix(r"\\?\") {
        if rest.as_bytes().get(1) == Some(&b':') {
            return Some(PathBuf::from(rest));
        }
    }
    Some(canonical)
}

/// Whether [candidate] is [directory] or below it.
pub(crate) fn is_inside(directory: &Path, candidate: &Path) -> bool {
    candidate.starts_with(directory)
}

pub(crate) fn read_text(path: &Path) -> Option<String> {
    let bytes = std::fs::read(path).ok()?;
    let text = String::from_utf8_lossy(&bytes);
    Some(text.strip_prefix('\u{feff}').unwrap_or(&text).to_string())
}

pub(crate) fn exists(path: &Path) -> bool {
    path.exists()
}

/// JavaScript's `String.prototype.trim`.
pub(crate) fn js_trim(text: &str) -> &str {
    text.trim_matches(is_mention_space)
}

pub(crate) fn js_trim_end(text: &str) -> &str {
    text.trim_end_matches(is_mention_space)
}

/// The default `Array.prototype.sort` order for strings: UTF-16 code units.
pub(crate) fn utf16_order(left: &str, right: &str) -> Ordering {
    left.encode_utf16().cmp(right.encode_utf16())
}
