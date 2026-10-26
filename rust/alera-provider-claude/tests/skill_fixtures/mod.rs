#![allow(dead_code)]

use alera_provider_claude::{ClaudeAgentOptions, ClaudeProviderConfig};
use std::path::{Path, PathBuf};

/// A scratch directory outside any repository, removed on drop, so the
/// repository-root lookups of discovery only see what a test creates.
pub(crate) struct TempDir(PathBuf);

impl TempDir {
    pub(crate) fn new() -> Self {
        let path = std::env::temp_dir().join(format!("alera-claude-skills-{}", uuid_like()));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    pub(crate) fn path(&self) -> &Path {
        &self.0
    }

    pub(crate) fn join(&self, part: &str) -> PathBuf {
        self.0.join(part)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn uuid_like() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!(
        "{}-{nanos}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::SeqCst)
    )
}

pub(crate) fn write(path: &Path, contents: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, contents).unwrap();
}

pub(crate) fn write_skill(skills_dir: &Path, directory_name: &str, contents: &str) {
    write(&skills_dir.join(directory_name).join("SKILL.md"), contents);
}

pub(crate) fn mkdir(path: &Path) {
    std::fs::create_dir_all(path).unwrap();
}

pub(crate) fn skill_path(root: &Path, name: &str) -> String {
    root.join(name)
        .join("SKILL.md")
        .to_string_lossy()
        .into_owned()
}

/// Options whose environment points Claude's config and home at [config_dir]
/// and clears an inherited plugin cache override.
pub(crate) fn options(config_dir: &Path, cwd: Option<&Path>) -> ClaudeAgentOptions {
    let mut options = ClaudeAgentOptions::default();
    let config = config_dir.to_string_lossy().into_owned();
    options
        .env
        .insert("CLAUDE_CONFIG_DIR".into(), config.clone());
    options.env.insert("HOME".into(), config);
    options
        .env
        .insert("CLAUDE_CODE_PLUGIN_CACHE_DIR".into(), String::new());
    options.cwd = cwd.map(Path::to_path_buf);
    options
}

pub(crate) fn config(config_dir: &Path, cwd: Option<&Path>) -> ClaudeProviderConfig {
    ClaudeProviderConfig {
        options: options(config_dir, cwd),
        ..ClaudeProviderConfig::default()
    }
}
