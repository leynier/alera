//! Skill roots of the enabled Claude Code plugins, from the install registry
//! and each plugin manifest (T3 Code's `discoverPluginSkillRoots`).

use super::discovery::SkillRoot;
use super::environment::SkillEnvironment;
use super::paths::{exists, is_inside, join, read_text, real_path, resolve, utf16_order};
use super::settings::find_repository_root;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

struct InstallRecord {
    shared: bool,
    install_path: String,
    project_path: Option<String>,
}

pub(crate) fn plugin_skill_roots(
    config_dir: &Path,
    environment: &SkillEnvironment,
    enabled_plugins: &HashMap<String, bool>,
) -> Vec<SkillRoot> {
    let cwd = environment.cwd();
    let plugins_path = match environment
        .var("CLAUDE_CODE_PLUGIN_CACHE_DIR")
        .filter(|directory| !directory.is_empty())
    {
        Some(directory) => resolve(cwd, &environment.expand_home(&directory)),
        None => join(config_dir, &["plugins"]),
    };
    let Some(installed) = read_installed_plugins(&plugins_path.join("installed_plugins.json"))
    else {
        return Vec::new();
    };
    // The CLI's process.cwd() resolves symlinks; registry projectPath values remain lexical.
    let workspace = cwd.map(|cwd| real_path(cwd).unwrap_or_else(|| resolve(None, cwd)));
    let repository_root = workspace.as_deref().and_then(plugin_repository_root);
    let mut roots = Vec::new();
    for (key, entries) in installed {
        if enabled_plugins.get(&key) != Some(&true) {
            continue;
        }
        let applicable: Vec<InstallRecord> = entries
            .iter()
            .filter_map(decode_install_record)
            .filter(|record| {
                if record.shared {
                    return true;
                }
                let (Some(project), Some(workspace)) = (&record.project_path, &workspace) else {
                    return false;
                };
                if &resolve(None, Path::new(project)) == workspace {
                    return true;
                }
                repository_root.is_some()
                    && plugin_repository_root(Path::new(project)) == repository_root
            })
            .collect();
        // The native loader keeps registry order, preferring the first install that exists.
        let Some(install) = applicable
            .iter()
            .find(|record| exists(&resolve(cwd, Path::new(&record.install_path))))
            .or_else(|| applicable.first())
        else {
            continue;
        };
        let scope = if install.shared { "user" } else { "project" };
        let install_path = resolve(cwd, Path::new(&install.install_path));
        let manifest = read_manifest(&join(&install_path, &[".claude-plugin", "plugin.json"]));
        let prefix = manifest
            .as_ref()
            .and_then(|manifest| manifest.name.clone())
            .unwrap_or_else(|| key.split('@').next().unwrap_or_default().to_string());
        if prefix.is_empty() {
            continue;
        }
        let root = |directory: PathBuf| SkillRoot {
            directory,
            scope,
            prefix: Some(prefix.clone()),
        };
        let default_directory = install_path.join("skills");
        let has_default_directory = exists(&default_directory);
        if has_default_directory {
            roots.push(root(default_directory));
        }
        let declared = manifest.and_then(|manifest| manifest.skills);
        if declared.is_none() && !has_default_directory && exists(&install_path.join("SKILL.md")) {
            roots.push(root(install_path.clone()));
        }
        let canonical_install_path = real_path(&install_path);
        for relative in declared.unwrap_or_default() {
            let directory = resolve(Some(&install_path), Path::new(&relative));
            let Some(canonical_install_path) = canonical_install_path
                .as_deref()
                .filter(|_| is_inside(&install_path, &directory))
            else {
                continue;
            };
            // The native loader rejects manifest roots that escape through a symlink, too.
            if real_path(&directory)
                .is_some_and(|canonical| is_inside(canonical_install_path, &canonical))
            {
                roots.push(root(directory));
            }
        }
    }
    roots
}

/// `{ plugins: Record<string, unknown[]> }`, sorted by key the way
/// `Object.entries(...).sort()` orders `key,entries` strings.
fn read_installed_plugins(path: &Path) -> Option<Vec<(String, Vec<Value>)>> {
    let Value::Object(mut root) = serde_json::from_str(&read_text(path)?).ok()? else {
        return None;
    };
    let Value::Object(plugins) = root.remove("plugins")? else {
        return None;
    };
    let mut installed = plugins
        .into_iter()
        .map(|(key, entries)| match entries {
            Value::Array(entries) => Some((key, entries)),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()?;
    installed
        .sort_by(|(left, _), (right, _)| utf16_order(&format!("{left},"), &format!("{right},")));
    Some(installed)
}

fn decode_install_record(entry: &Value) -> Option<InstallRecord> {
    let shared = match entry.get("scope")?.as_str()? {
        "user" | "managed" => true,
        "project" | "local" => false,
        _ => return None,
    };
    let install_path = non_empty_text(entry.get("installPath")?)?;
    let project_path = match entry.get("projectPath") {
        None => None,
        Some(value) => Some(non_empty_text(value)?),
    };
    entry.is_object().then_some(InstallRecord {
        shared,
        install_path,
        project_path,
    })
}

struct PluginManifest {
    name: Option<String>,
    skills: Option<Vec<String>>,
}

/// An invalid manifest counts as none, dropping its name and skills alike.
fn read_manifest(path: &Path) -> Option<PluginManifest> {
    let manifest: Value = serde_json::from_str(&read_text(path)?).ok()?;
    if !manifest.is_object() {
        return None;
    }
    let name = match manifest.get("name") {
        None => None,
        Some(value) => Some(non_empty_text(value)?),
    };
    let skills = match manifest.get("skills") {
        None => None,
        Some(Value::String(skill)) => Some(vec![skill.clone()]),
        Some(Value::Array(skills)) => Some(
            skills
                .iter()
                .map(|skill| skill.as_str().map(str::to_owned))
                .collect::<Option<Vec<_>>>()?,
        ),
        Some(_) => return None,
    };
    Some(PluginManifest { name, skills })
}

fn non_empty_text(value: &Value) -> Option<String> {
    value
        .as_str()
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

/// The repository whose plugin records apply to [cwd]. Claude shares plugin
/// install records across linked worktrees, using their common repository.
fn plugin_repository_root(cwd: &Path) -> Option<PathBuf> {
    let root = find_repository_root(cwd)?;
    let git_path = root.join(".git");
    let git_file = read_text(&git_path).unwrap_or_default();
    let Some(git_directory) = git_file.trim().strip_prefix("gitdir:") else {
        return Some(root);
    };
    let git_directory = resolve(Some(&root), Path::new(git_directory.trim()));
    let common_file = read_text(&git_directory.join("commondir")).unwrap_or_default();
    let worktree_file = read_text(&git_directory.join("gitdir")).unwrap_or_default();
    if common_file.trim().is_empty() || worktree_file.trim().is_empty() {
        return Some(root);
    }
    let common_directory = resolve(Some(&git_directory), Path::new(common_file.trim()));
    let backlink = real_path(&resolve(
        Some(&git_directory),
        Path::new(worktree_file.trim()),
    ));
    let worktree_git_path = real_path(&git_path);
    if git_directory.parent() != Some(common_directory.join("worktrees").as_path())
        || backlink.is_none()
        || backlink != worktree_git_path
    {
        return Some(root);
    }
    if common_directory
        .file_name()
        .is_some_and(|name| name == ".git")
    {
        return common_directory.parent().map(Path::to_path_buf);
    }
    Some(common_directory)
}
