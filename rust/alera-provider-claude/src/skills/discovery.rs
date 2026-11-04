//! The skills Claude Code loads for a workspace, scanned from disk the way
//! T3 Code's `discoverClaudeSkills` does: user skills, project skills, the
//! additional directories, then enabled plugins, the first name winning.

use super::environment::SkillEnvironment;
use super::frontmatter::{parse_frontmatter, SkillFrontmatter};
use super::paths::{exists, join, js_trim, read_text, resolve, utf16_order};
use super::plugins::plugin_skill_roots;
use super::settings::read_skill_settings;
use crate::ClaudeProviderConfig;
use alera_provider_protocol::compare_skill_names;
use alera_provider_protocol::{skill_mentions, ProviderSkill};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

pub(crate) struct SkillRoot {
    pub directory: PathBuf,
    pub scope: &'static str,
    /// Plugin skills are named `prefix:name`.
    pub prefix: Option<String>,
}

/// Every skill Claude Code would load for [config]'s cwd, sorted by name.
/// It reads the filesystem synchronously, so async callers should run it on
/// a blocking thread.
pub fn discover_skills(config: &ClaudeProviderConfig) -> Vec<ProviderSkill> {
    discover(&SkillEnvironment::new(
        &config.options,
        config.options.cwd.as_deref(),
    ))
}

pub(crate) fn discover(environment: &SkillEnvironment) -> Vec<ProviderSkill> {
    let Some(config_dir) = environment.config_dir() else {
        return Vec::new();
    };
    let settings = read_skill_settings(&config_dir, environment);
    let cwd = environment.cwd();
    let mut roots = vec![SkillRoot {
        directory: join(&config_dir, &["skills"]),
        scope: "user",
        prefix: None,
    }];
    if let Some(cwd) = cwd {
        roots.push(project_root(join(cwd, &[".claude", "skills"])));
    }
    for directory in environment.add_dirs() {
        if !directory.is_empty() && (cwd.is_some() || Path::new(directory).is_absolute()) {
            let resolved = resolve(cwd, Path::new(directory));
            roots.push(project_root(join(&resolved, &[".claude", "skills"])));
        }
    }
    roots.extend(plugin_skill_roots(
        &config_dir,
        environment,
        &settings.enabled_plugins,
    ));

    let mut names = HashSet::new();
    let mut skills = Vec::new();
    for root in &roots {
        let single_skill = root.prefix.is_some() && exists(&root.directory.join("SKILL.md"));
        let entries = if single_skill {
            root.directory
                .file_name()
                .map(|name| vec![name.to_string_lossy().into_owned()])
                .unwrap_or_default()
        } else {
            directory_entries(&root.directory)
        };
        for entry in entries {
            let skill_path = if single_skill {
                root.directory.join("SKILL.md")
            } else {
                join(&root.directory, &[&entry, "SKILL.md"])
            };
            let Some(contents) = read_text(&skill_path) else {
                continue;
            };
            let frontmatter = parse_frontmatter(&contents);
            if frontmatter == SkillFrontmatter::Malformed {
                continue;
            }
            let directory_name = js_trim(&entry);
            if directory_name.is_empty() {
                continue;
            }
            let name = match &root.prefix {
                None => directory_name.to_string(),
                Some(prefix) => match plugin_skill_name(prefix, &entry, single_skill, &frontmatter)
                {
                    Some(name) => name,
                    None => continue,
                },
            };
            if !names.insert(name.clone()) {
                continue;
            }
            let skill_override = root
                .prefix
                .is_none()
                .then(|| settings.skill_overrides.get(&name))
                .flatten();
            let metadata = frontmatter.metadata();
            let user_invocation_only = metadata
                .is_some_and(|metadata| metadata.user_invocation_only)
                || skill_override.is_some_and(|value| value.user_invocation_only);
            let enabled = skill_override.is_none_or(|value| value.enabled);
            let Some(skill) =
                ProviderSkill::from_native(&name, &skill_path.to_string_lossy(), enabled)
                    .filter(|skill| skill.name == name)
            else {
                continue;
            };
            skills.push(
                skill
                    .with_description(metadata.and_then(|metadata| metadata.description.as_deref()))
                    .with_scope(Some(root.scope))
                    .with_invocation(
                        user_invocation_only,
                        metadata.is_none_or(|metadata| metadata.user_invocable),
                    ),
            );
        }
    }
    skills.sort_by(|left, right| compare_skill_names(&left.name, &right.name));
    skills
}

fn project_root(directory: PathBuf) -> SkillRoot {
    SkillRoot {
        directory,
        scope: "project",
        prefix: None,
    }
}

fn directory_entries(directory: &Path) -> Vec<String> {
    let Ok(reader) = std::fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut entries: Vec<String> = reader
        .filter_map(Result::ok)
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    entries.sort_by(|left, right| utf16_order(left, right));
    entries
}

/// Native folder skills use their folder; only a single `SKILL.md` uses its
/// name field. `None` for a name the composer grammar cannot invoke.
fn plugin_skill_name(
    prefix: &str,
    entry: &str,
    single_skill: bool,
    frontmatter: &SkillFrontmatter,
) -> Option<String> {
    let declared = frontmatter
        .metadata()
        .filter(|_| single_skill)
        .and_then(|metadata| metadata.name.as_deref())
        .unwrap_or_default();
    let unprefixed = declared
        .strip_prefix(prefix)
        .and_then(|rest| rest.strip_prefix(':'))
        .unwrap_or(declared);
    let base = if unprefixed.is_empty() {
        entry
    } else {
        unprefixed
    };
    // The JavaScript replace works on UTF-16 code units.
    let sanitized: String = base
        .chars()
        .flat_map(|character| {
            let keep = character.is_ascii_alphanumeric() || matches!(character, '_' | '-');
            let replacement = if keep { character } else { '-' };
            std::iter::repeat_n(replacement, if keep { 1 } else { character.len_utf16() })
        })
        .collect();
    let name = format!("{prefix}:{sanitized}");
    let mention = skill_mentions(&format!("${name}")).into_iter().next()?;
    (mention.name == name).then_some(name)
}
