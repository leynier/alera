//! Cursor invokes Agent Skills with `/name` while composers insert `$name`;
//! known mentions are rewritten just before the prompt reaches the bridge.

use super::CursorProvider;
use crate::skills::{discover_skills_lenient, skill_home_directory};
use alera_provider_protocol::{rewrite_skill_mentions, skill_mentions};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// [prompt] with each `$name` naming one of [skill_names] written as `/name`.
pub fn rewrite_cursor_skill_mentions(prompt: &str, skill_names: &HashSet<String>) -> String {
    rewrite_skill_mentions(prompt, |name| skill_names.contains(name).then_some('/'))
}

impl CursorProvider {
    /// The names are read once per session, on the first prompt with a
    /// mention, as T3 Code's Cursor adapter does.
    pub(super) async fn skill_invocation_text(
        &mut self,
        text: String,
        cwd: Option<&Path>,
    ) -> String {
        if self.skill_names.is_none() && !skill_mentions(&text).is_empty() {
            self.skill_names = invocable_skill_names(cwd.map(Path::to_path_buf)).await;
        }
        match &self.skill_names {
            Some(names) => rewrite_cursor_skill_mentions(&text, names),
            None => text,
        }
    }
}

async fn invocable_skill_names(cwd: Option<PathBuf>) -> Option<HashSet<String>> {
    tokio::task::spawn_blocking(move || {
        let home = skill_home_directory();
        discover_skills_lenient(cwd.as_deref(), home.as_deref())
            .into_iter()
            .filter(|skill| skill.is_user_invocable())
            .map(|skill| skill.name)
            .collect()
    })
    .await
    .ok()
}
