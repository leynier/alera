//! Antigravity skills found in the folders its native loader reads (T3 Code's
//! `apps/server/src/provider/Drivers/AntigravitySkills.ts`). Antigravity
//! expands mentions itself, so prompts are sent unchanged.

use crate::AntigravityProviderConfig;
use alera_provider_protocol::compare_skill_names;
use alera_provider_protocol::{parse_skill_frontmatter_yaml, ProviderSkill};
use serde_json::Value;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

const MAX_SKILL_BYTES: u64 = 1_000_000;
const MAX_SCAN_BYTES: u64 = 8_000_000;
const MAX_SCAN_ENTRIES: usize = 10_000;

/// The skills Antigravity loads for `config.cwd` (the process directory when
/// unset), sorted by name. The user home comes from the config environment,
/// then the process environment. `Err` means the list would be incomplete.
pub fn discover_skills(config: &AntigravityProviderConfig) -> Result<Vec<ProviderSkill>, String> {
    let cwd = match &config.cwd {
        Some(cwd) if cwd.is_absolute() => cwd.clone(),
        relative => std::env::current_dir()
            .map(|process_cwd| process_cwd.join(relative.as_deref().unwrap_or(Path::new(""))))
            .map_err(|_| "Antigravity could not resolve the working directory.".to_owned())?,
    };
    let user_home = antigravity_user_home(config)
        .ok_or_else(|| "Antigravity could not resolve the user home directory.".to_owned())?;
    discover_skills_at(&cwd, &user_home)
}

/// [`discover_skills`] for an explicit project directory and user home.
///
/// User skills are always read from `<user_home>/.gemini`, never from
/// `GEMINI_HOME`: a private profile links its skill folders back there.
pub fn discover_skills_at(cwd: &Path, user_home: &Path) -> Result<Vec<ProviderSkill>, String> {
    let gemini = user_home.join(".gemini");
    let roots = [
        (gemini.join("config").join("skills"), "user"),
        (cwd.join(".gemini").join("skills"), "project"),
        (gemini.join("antigravity-cli").join("skills"), "user"),
        (cwd.join(".agents").join("skills"), "project"),
        (cwd.join(".agent").join("skills"), "project"),
    ];
    let mut scan = Scan {
        remaining_bytes: MAX_SCAN_BYTES,
        remaining_entries: MAX_SCAN_ENTRIES,
        skills: Vec::new(),
    };
    for (directory, scope) in roots {
        scan.directory(&directory, scope, true)?;
    }
    let mut skills = scan.skills;
    skills.sort_by(|left, right| compare_skill_names(&left.name, &right.name));
    Ok(skills)
}

/// Python's `os.path.expanduser`, which the native loader uses: `USERPROFILE`,
/// then `HOMEDRIVE` plus `HOMEPATH` on Windows; `HOME` elsewhere; then the
/// platform home directory.
pub fn antigravity_user_home(config: &AntigravityProviderConfig) -> Option<PathBuf> {
    let variable = |name: &str| {
        config
            .env
            .get(OsStr::new(name))
            .cloned()
            .or_else(|| std::env::var_os(name))
            .filter(|value| !value.is_empty())
    };
    if cfg!(windows) {
        if let Some(profile) = variable("USERPROFILE") {
            return Some(PathBuf::from(profile));
        }
        if let (Some(drive), Some(path)) = (variable("HOMEDRIVE"), variable("HOMEPATH")) {
            let mut home = drive;
            home.push(path);
            return Some(PathBuf::from(home));
        }
    } else if let Some(home) = variable("HOME") {
        return Some(PathBuf::from(home));
    }
    std::env::home_dir()
}

fn budget_exhausted(path: &Path) -> String {
    format!(
        "Antigravity skill discovery exceeded its scan limit at '{}'.",
        path.display()
    )
}

/// The value, `None` for a missing path, or `Err` for any other failure.
fn present<T>(result: io::Result<T>, path: &Path) -> Result<Option<T>, String> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(format!(
            "Antigravity could not read skills at '{}'.",
            path.display()
        )),
    }
}

struct Scan {
    remaining_bytes: u64,
    remaining_entries: usize,
    skills: Vec<ProviderSkill>,
}

impl Scan {
    /// A folder holding `SKILL.md` is one skill and its children are not
    /// read; a root's children are each scanned one level deep.
    fn directory(
        &mut self,
        directory: &Path,
        scope: &str,
        scan_children: bool,
    ) -> Result<(), String> {
        let Some(info) = present(fs::metadata(directory), directory)? else {
            return Ok(());
        };
        if !info.is_dir() {
            return Ok(());
        }
        let Some(mut entries) = present(directory_entries(directory), directory)? else {
            return Ok(());
        };
        if entries.len() > self.remaining_entries {
            return Err(budget_exhausted(directory));
        }
        self.remaining_entries -= entries.len();
        entries.sort();

        let skill_file = entries
            .iter()
            .find(|entry| entry.to_string_lossy().to_lowercase() == "skill.md");
        if let Some(skill_file) = skill_file {
            let file_name = skill_file.to_string_lossy().into_owned();
            if !file_name.ends_with(".md") {
                return Ok(());
            }
            let skill_path = directory.join(skill_file);
            let Some(contents) = self.read_skill(&skill_path)? else {
                return Ok(());
            };
            let Some((name, description)) = parse_skill_frontmatter(&contents, &file_name) else {
                return Ok(());
            };
            if self.skills.iter().any(|skill| skill.name == name) {
                return Ok(());
            }
            if let Some(skill) =
                ProviderSkill::from_native(&name, &skill_path.to_string_lossy(), true)
            {
                self.skills.push(
                    skill
                        .with_scope(Some(scope))
                        .with_description(description.as_deref()),
                );
            }
            return Ok(());
        }
        if scan_children {
            let mut children: Vec<(String, OsString)> = entries
                .into_iter()
                .map(|entry| (escaped_path_sort_key(&entry.to_string_lossy()), entry))
                .collect();
            children.sort_by(|left, right| left.0.cmp(&right.0));
            for (_, entry) in children {
                self.directory(&directory.join(entry), scope, false)?;
            }
        }
        Ok(())
    }

    fn read_skill(&mut self, skill_path: &Path) -> Result<Option<String>, String> {
        let Some(info) = present(fs::metadata(skill_path), skill_path)? else {
            return Ok(None);
        };
        if !info.is_file() {
            return Ok(None);
        }
        let byte_limit = MAX_SKILL_BYTES.min(self.remaining_bytes);
        if info.len() > byte_limit {
            return Err(budget_exhausted(skill_path));
        }
        let read = fs::File::open(skill_path).and_then(|file| {
            let mut bytes = Vec::new();
            file.take(byte_limit + 1).read_to_end(&mut bytes)?;
            Ok(bytes)
        });
        let Some(bytes) = present(read, skill_path)? else {
            return Ok(None);
        };
        if bytes.len() as u64 > byte_limit {
            return Err(budget_exhausted(skill_path));
        }
        self.remaining_bytes -= bytes.len() as u64;
        Ok(Some(String::from_utf8_lossy(&bytes).into_owned()))
    }
}

fn directory_entries(directory: &Path) -> io::Result<Vec<OsString>> {
    fs::read_dir(directory)?
        .map(|entry| entry.map(|entry| entry.file_name()))
        .collect()
}

/// The native loader splits on the first two `---` anywhere in the file, not
/// on delimiter lines, and names a skill after its file when the frontmatter
/// has no name.
fn parse_skill_frontmatter(contents: &str, file_name: &str) -> Option<(String, Option<String>)> {
    let start = contents.find("---")?;
    let end = start + 3 + contents[start + 3..].find("---")?;
    let parsed = parse_skill_frontmatter_yaml(contents[start + 3..end].trim()).ok()?;
    let record = match parsed {
        Value::Null => serde_json::Map::new(),
        Value::Object(record) => record,
        _ => return None,
    };
    let optional_text = |key: &str| match record.get(key) {
        None | Some(Value::Null) => Some(None),
        Some(Value::String(text)) => Some(Some(text.clone())),
        Some(_) => None,
    };
    let name = optional_text("name")?;
    let description = optional_text("description")?
        .map(|description| description.trim().to_owned())
        .filter(|description| !description.is_empty());
    let name = name
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| file_name[..file_name.len() - 3].to_owned());
    // Native names are not trimmed. Do not rename one to fit the picker contract.
    if name.is_empty() || name != name.trim() {
        return None;
    }
    Some((name, description))
}

/// The order of Go's `URL.EscapedPath`, which the native loader sorts child
/// paths by: JavaScript's `encodeURI` with `!'()*?#` also escaped.
fn escaped_path_sort_key(entry: &str) -> String {
    let mut key = String::with_capacity(entry.len());
    for byte in entry.bytes() {
        if byte.is_ascii_alphanumeric() || b";,/:@&=+$-_.~".contains(&byte) {
            key.push(byte as char);
        } else {
            key.push_str(&format!("%{byte:02X}"));
        }
    }
    key
}
