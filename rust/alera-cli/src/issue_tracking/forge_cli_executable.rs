use std::path::{Path, PathBuf};

pub(super) fn resolve(program: &str, windows: bool, directories: &[PathBuf]) -> PathBuf {
    let path = Path::new(program);
    if !windows || path.extension().is_some() || path.components().count() != 1 {
        return path.to_path_buf();
    }
    // Rust handles explicit .cmd/.bat paths, but bare-name lookup only adds .exe.
    for directory in directories
        .iter()
        .filter(|directory| directory.is_absolute())
    {
        for extension in ["exe", "cmd", "bat"] {
            let candidate = directory.join(format!("{program}.{extension}"));
            if candidate.is_file() {
                return candidate;
            }
        }
    }
    path.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn windows_finds_command_shims_without_changing_posix_execution() {
        let root = tempfile::tempdir().unwrap();
        let shim = root.path().join("az.cmd");
        std::fs::write(&shim, "@echo off\n").unwrap();
        let directories = [root.path().to_path_buf()];
        assert_eq!(resolve("az", true, &directories), shim);
        assert_eq!(resolve("az", false, &directories), PathBuf::from("az"));
        let exe = root.path().join("az.exe");
        std::fs::write(&exe, "").unwrap();
        assert_eq!(resolve("az", true, &directories), exe);
    }
}
