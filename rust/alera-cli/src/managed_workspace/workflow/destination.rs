use super::*;

// Resolve existing ancestors without creating directories before approval.
// Match libgit2's canonical, forward-slash Windows paths before freezing them.
pub(super) fn canonical_destination(path: &str) -> Result<String> {
    let mut ancestor = Path::new(path);
    let mut missing = Vec::new();
    let resolved = loop {
        match dunce::canonicalize(ancestor) {
            Ok(path) => break path,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                missing.push(
                    ancestor
                        .file_name()
                        .ok_or_else(|| anyhow!("invalid workflow destination"))?,
                );
                ancestor = ancestor
                    .parent()
                    .ok_or_else(|| anyhow!("invalid workflow destination"))?;
            }
            Err(error) => return Err(error.into()),
        }
    };
    let mut resolved = resolved;
    for component in missing.into_iter().rev() {
        resolved.push(component);
    }
    let path = resolved.to_string_lossy().into_owned();
    Ok(if cfg!(windows) {
        path.replace('\\', "/")
    } else {
        path
    })
}
