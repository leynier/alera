//! Cursor Agent Skills found by scanning the folders Cursor loads them from,
//! without opening an agent and starting its MCP servers (T3 Code's
//! `packages/provider-cursor/src/server/skills.ts`).

use alera_provider_protocol::compare_skill_names;
use alera_provider_protocol::{
    parse_skill_frontmatter_yaml, skill_frontmatter_block, skill_frontmatter_flag,
    skill_frontmatter_text, ProviderSkill,
};
use serde_json::Value;
use std::collections::HashSet;
use std::ffi::OsString;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

const MAX_SKILL_DEPTH: usize = 10;
const MAX_SKILL_BYTES: u64 = 1_000_000;
const MAX_SKILL_SCAN_ENTRIES: usize = 10_000;
const MAX_SKILL_SCAN_BYTES: u64 = 8_000_000;
const SKILL_ROOT_FOLDERS: [&str; 4] = [".cursor", ".agents", ".codex", ".claude"];

/// The skills a person can invoke in Cursor for [cwd], sorted by name. `Err`
/// carries T3 Code's message when the scan budget ran out or a filesystem
/// error left the list incomplete.
pub fn discover_skills(cwd: Option<&Path>, home: &Path) -> Result<Vec<ProviderSkill>, String> {
    let inspection = inspect_skills(cwd, Some(home));
    match inspection.failure_reason {
        None => Ok(inspection.skills),
        Some(reason) => {
            let location = cwd
                .map(|cwd| format!(" for '{}'", cwd.display()))
                .unwrap_or_default();
            Err(format!(
                "Cursor skill discovery{location} was incomplete ({reason})."
            ))
        }
    }
}

/// [`discover_skills`] keeping whatever the scan found when it was incomplete,
/// as the adapter does before it rewrites mentions.
/// Without a [home] only the project roots are scanned.
pub fn discover_skills_lenient(cwd: Option<&Path>, home: Option<&Path>) -> Vec<ProviderSkill> {
    inspect_skills(cwd, home).skills
}

/// The home Cursor resolves user skills under: `HOME`, then `USERPROFILE`,
/// then the platform home directory.
pub fn skill_home_directory() -> Option<PathBuf> {
    ["HOME", "USERPROFILE"]
        .into_iter()
        .filter_map(std::env::var_os)
        .find(|value| !value.to_string_lossy().trim().is_empty())
        .map(|value| PathBuf::from(value.to_string_lossy().trim()))
        .or_else(std::env::home_dir)
}

struct Inspection {
    skills: Vec<ProviderSkill>,
    failure_reason: Option<&'static str>,
}

struct ScanBudget {
    remaining_entries: usize,
    remaining_bytes: u64,
    exhausted: bool,
    incomplete: bool,
}

impl ScanBudget {
    /// The value, or `None` with a failure other than a missing file recorded.
    fn present<T>(&mut self, result: io::Result<T>) -> Option<T> {
        match result {
            Ok(value) => Some(value),
            Err(error) => {
                if error.kind() != io::ErrorKind::NotFound {
                    self.incomplete = true;
                }
                None
            }
        }
    }
}

fn inspect_skills(cwd: Option<&Path>, home: Option<&Path>) -> Inspection {
    let roots_below = |base: &Path, scope: &'static str| {
        SKILL_ROOT_FOLDERS
            .into_iter()
            .map(move |folder| (base.join(folder).join("skills"), scope))
            .collect::<Vec<_>>()
    };
    let mut roots = cwd
        .map(|cwd| roots_below(cwd, "project"))
        .unwrap_or_default();
    if let Some(home) = home {
        roots.extend(roots_below(home, "user"));
        // Cursor syncs its built-in skills here; same-named user and project skills win.
        roots.push((home.join(".cursor").join("skills-cursor"), "system"));
    }

    let mut budget = ScanBudget {
        remaining_entries: MAX_SKILL_SCAN_ENTRIES,
        remaining_bytes: MAX_SKILL_SCAN_BYTES,
        exhausted: false,
        incomplete: false,
    };
    let mut scanned_roots = HashSet::new();
    let mut skills: Vec<ProviderSkill> = Vec::new();
    for (directory, scope) in roots {
        if budget.exhausted {
            break;
        }
        for skill in scan_root(&directory, scope, &mut budget, &mut scanned_roots) {
            if !skills.iter().any(|existing| existing.name == skill.name) {
                skills.push(skill);
            }
        }
    }
    skills.sort_by(|left, right| compare_skill_names(&left.name, &right.name));
    Inspection {
        skills,
        failure_reason: if budget.exhausted {
            Some("scan-budget-exhausted")
        } else if budget.incomplete {
            Some("filesystem-error")
        } else {
            None
        },
    }
}

struct RootScan<'a> {
    root: PathBuf,
    scope: &'static str,
    budget: &'a mut ScanBudget,
    visited: HashSet<PathBuf>,
    skills: Vec<ProviderSkill>,
}

fn scan_root(
    directory: &Path,
    scope: &'static str,
    budget: &mut ScanBudget,
    scanned_roots: &mut HashSet<PathBuf>,
) -> Vec<ProviderSkill> {
    if budget.exhausted {
        return Vec::new();
    }
    let Some(root) = budget.present(fs::canonicalize(directory)) else {
        return Vec::new();
    };
    // Symlinked roots may share a tree; do not charge its scan budget twice.
    if !scanned_roots.insert(root.clone()) {
        return Vec::new();
    }
    let mut scan = RootScan {
        root: root.clone(),
        scope,
        budget,
        visited: HashSet::new(),
        skills: Vec::new(),
    };
    scan.visit(&root, 0);
    scan.skills
}

impl RootScan<'_> {
    fn visit(&mut self, directory: &Path, depth: usize) {
        if self.budget.exhausted {
            return;
        }
        let Some(resolved) = self.budget.present(fs::canonicalize(directory)) else {
            return;
        };
        if !self.visited.insert(resolved.clone()) {
            return;
        }
        // Outside-root symlinks expose only their own SKILL.md; never traverse the target tree.
        let inside_root = resolved.starts_with(&self.root);
        self.read_skill(directory);
        if !inside_root {
            return;
        }
        let Some(entries) = self.budget.present(directory_entries(directory)) else {
            return;
        };
        for entry in entries {
            if self.budget.remaining_entries == 0 {
                self.budget.exhausted = true;
                return;
            }
            self.budget.remaining_entries -= 1;
            // Installed dependencies can exhaust the shared budget and hide unrelated skills.
            if entry == "node_modules" {
                continue;
            }
            let child = directory.join(&entry);
            let Some(info) = self.budget.present(fs::metadata(&child)) else {
                continue;
            };
            if !info.is_dir() || depth >= MAX_SKILL_DEPTH {
                continue;
            }
            self.visit(&child, depth + 1);
        }
    }

    fn read_skill(&mut self, directory: &Path) {
        let skill_path = directory.join("SKILL.md");
        let Some(info) = self.budget.present(fs::metadata(&skill_path)) else {
            return;
        };
        if !info.is_file() {
            return;
        }
        let mut frontmatter = Some(CursorSkillFrontmatter::visible());
        if info.len() <= MAX_SKILL_BYTES && info.len() <= self.budget.remaining_bytes {
            // A file that cannot be read still lists, as Cursor lists it.
            if let Ok(bytes) = fs::read(&skill_path) {
                self.budget.remaining_bytes =
                    self.budget.remaining_bytes.saturating_sub(info.len());
                frontmatter = parse_skill_frontmatter(&String::from_utf8_lossy(&bytes));
            }
        }
        let Some(frontmatter) = frontmatter.filter(|frontmatter| frontmatter.cli_visible) else {
            return;
        };
        let name = directory
            .file_name()
            .map(|name| name.to_string_lossy().trim().to_owned())
            .unwrap_or_default();
        let Some(skill) = ProviderSkill::from_native(&name, &skill_path.to_string_lossy(), true)
        else {
            return;
        };
        let display_name = frontmatter
            .display_name
            .as_deref()
            .filter(|display_name| *display_name != name);
        self.skills.push(
            skill
                .with_scope(Some(self.scope))
                .with_display_name(display_name)
                .with_description(frontmatter.description.as_deref())
                .with_invocation(frontmatter.user_invocation_only, frontmatter.user_invocable),
        );
    }
}

fn directory_entries(directory: &Path) -> io::Result<Vec<OsString>> {
    let mut entries = fs::read_dir(directory)?
        .map(|entry| entry.map(|entry| entry.file_name()))
        .collect::<io::Result<Vec<_>>>()?;
    entries.sort();
    Ok(entries)
}

struct CursorSkillFrontmatter {
    cli_visible: bool,
    description: Option<String>,
    display_name: Option<String>,
    user_invocation_only: bool,
    user_invocable: bool,
}

impl CursorSkillFrontmatter {
    fn visible() -> Self {
        Self {
            cli_visible: true,
            description: None,
            display_name: None,
            user_invocation_only: false,
            user_invocable: true,
        }
    }
}

/// `None` hides the skill: frontmatter that does not parse or is not a map.
fn parse_skill_frontmatter(contents: &str) -> Option<CursorSkillFrontmatter> {
    let Some(block) = skill_frontmatter_block(contents) else {
        return Some(CursorSkillFrontmatter::visible());
    };
    let record = parse_skill_frontmatter_yaml(block).ok()?;
    // A YAML list is an object to the reference's `typeof` check.
    if !record.is_object() && !record.is_array() {
        return None;
    }
    let surfaces: Vec<String> = match record.get("metadata").and_then(|meta| meta.get("surfaces")) {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect(),
        Some(Value::String(text)) => text.split(',').map(str::to_owned).collect(),
        _ => Vec::new(),
    };
    Some(CursorSkillFrontmatter {
        cli_visible: surfaces.is_empty()
            || surfaces
                .iter()
                .any(|surface| surface.trim().to_lowercase() == "cli"),
        description: skill_frontmatter_text(&record, "description"),
        display_name: skill_frontmatter_text(&record, "name"),
        user_invocation_only: skill_frontmatter_flag(record.get("disable-model-invocation"), false)
            == Some(true),
        user_invocable: skill_frontmatter_flag(record.get("user-invocable"), false) != Some(false),
    })
}
