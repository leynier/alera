//! The Alera skills coding agents use in Alera terminals (`skills/` in the
//! repository): where they are installed from and whether the copies on this
//! machine match this runtime.

use std::path::Path;

use serde::Serialize;
use serde_json::{json, Value};

use crate::host_tools::SkillKind;
use crate::terminal_host::protocol::{
    AGENT_PROFILES_SKILL_VERSION, AUTOMATIONS_SKILL_VERSION, CLI_SKILL_VERSION,
    ORCHESTRATION_SKILL_VERSION,
};

const SKILL_REPOSITORY: &str = "https://github.com/leynier/alera";

impl SkillKind {
    /// The version of the skill this runtime documents and expects.
    pub(crate) fn contract_version(self) -> i64 {
        match self {
            Self::Cli => CLI_SKILL_VERSION,
            Self::Orchestration => ORCHESTRATION_SKILL_VERSION,
            Self::Automations => AUTOMATIONS_SKILL_VERSION,
            Self::AgentProfiles => AGENT_PROFILES_SKILL_VERSION,
        }
    }
}

/// The commit this binary was built from. A release is built from its tag's
/// commit, so installing at it pins the skills to this runtime's release.
fn build_commit() -> Option<&'static str> {
    pinned_commit(option_env!("ALERA_BUILD_COMMIT"))
}

fn pinned_commit(commit: Option<&'static str>) -> Option<&'static str> {
    commit.filter(|value| value.len() == 40 && value.chars().all(|c| c.is_ascii_hexdigit()))
}

/// What `skills add` installs from: the repository at this build's commit,
/// or its default branch for a build without one.
pub(crate) fn install_source() -> String {
    source_for(build_commit())
}

fn source_for(commit: Option<&str>) -> String {
    match commit {
        Some(commit) => format!("{SKILL_REPOSITORY}/tree/{commit}"),
        None => SKILL_REPOSITORY.to_owned(),
    }
}

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AgentSkillStatus {
    pub(crate) skill: &'static str,
    pub(crate) name: &'static str,
    /// `current`, `outdated`, `newer`, or `missing`.
    pub(crate) state: &'static str,
    pub(crate) expected_version: i64,
    pub(crate) installed_version: Option<i64>,
    /// The commit the installed copy came from, when the installer recorded it.
    pub(crate) installed_ref: Option<String>,
    pub(crate) updated_at: Option<String>,
    pub(crate) path: String,
}

/// The state of every agent skill under `<home>/.agents/skills`, where the
/// `skills` installer puts global skills for every agent.
pub(crate) fn status(home: &Path) -> Value {
    status_with_commit(home, build_commit())
}

fn status_with_commit(home: &Path, commit: Option<&str>) -> Value {
    let lock = std::fs::read_to_string(home.join(".agents").join(".skill-lock.json"))
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .unwrap_or(Value::Null);
    let skills = SkillKind::ALL
        .iter()
        .map(|kind| skill_status(home, *kind, &lock))
        .collect::<Vec<_>>();
    let ready = skills.iter().all(|skill| skill.state == "current");
    json!({
        "ready": ready,
        "source": source_for(commit),
        "pinnedRef": commit,
        "skills": skills,
    })
}

fn skill_status(home: &Path, kind: SkillKind, lock: &Value) -> AgentSkillStatus {
    let folder = home
        .join(".agents")
        .join("skills")
        .join(kind.package_name());
    let installed = std::fs::read_to_string(folder.join("SKILL.md")).ok();
    let installed_version = installed.as_deref().and_then(frontmatter_version);
    let expected_version = kind.contract_version();
    let state = match (&installed, installed_version) {
        (None, _) => "missing",
        (Some(_), Some(version)) if version == expected_version => "current",
        (Some(_), Some(version)) if version > expected_version => "newer",
        // A copy without a version predates versioned skills.
        (Some(_), _) => "outdated",
    };
    let entry = &lock["skills"][kind.package_name()];
    AgentSkillStatus {
        skill: kind.id(),
        name: kind.package_name(),
        state,
        expected_version,
        installed_version,
        installed_ref: entry["ref"].as_str().map(str::to_owned),
        updated_at: entry["updatedAt"].as_str().map(str::to_owned),
        path: folder.to_string_lossy().into_owned(),
    }
}

/// `metadata.version` from the leading frontmatter block.
fn frontmatter_version(contents: &str) -> Option<i64> {
    let mut lines = contents.lines();
    if lines.next()?.trim() != "---" {
        return None;
    }
    lines
        .take_while(|line| line.trim() != "---")
        .find_map(|line| line.trim().strip_prefix("version:"))
        .and_then(|value| value.trim().parse().ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    const COMMIT: &str = "c8b3d3984f850a7b0b9a0692e70c7501ba4f7d1c";

    fn write_skill(home: &Path, name: &str, frontmatter: &str) {
        let folder = home.join(".agents/skills").join(name);
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(
            folder.join("SKILL.md"),
            format!("---\n{frontmatter}---\n# Body\n"),
        )
        .unwrap();
    }

    #[test]
    fn a_release_commit_pins_the_install_and_a_dev_build_does_not() {
        assert_eq!(pinned_commit(Some(COMMIT)), Some(COMMIT));
        assert_eq!(pinned_commit(Some("unknown")), None);
        assert_eq!(pinned_commit(None), None);
        assert_eq!(
            source_for(Some(COMMIT)),
            format!("https://github.com/leynier/alera/tree/{COMMIT}")
        );
        assert_eq!(source_for(None), "https://github.com/leynier/alera");
    }

    #[test]
    fn install_arguments_never_prompt_and_name_every_skill() {
        let arguments =
            crate::host_tools::skill_install_arguments(&[SkillKind::Cli, SkillKind::AgentProfiles]);
        assert_eq!(&arguments[..2], ["skills", "add"]);
        assert_eq!(
            &arguments[3..],
            [
                "--skill",
                "alera-cli",
                "--skill",
                "alera-agent-profiles",
                "--agent",
                "codex",
                "--global",
                "--yes"
            ]
        );
    }

    #[test]
    fn status_compares_each_installed_version_with_the_runtime() {
        let home = tempfile::tempdir().unwrap();
        write_skill(
            home.path(),
            "alera-cli",
            &format!("name: alera-cli\nmetadata:\n  version: {CLI_SKILL_VERSION}\n"),
        );
        write_skill(
            home.path(),
            "alera-orchestration",
            "name: alera-orchestration\nmetadata:\n  version: 1\n",
        );
        write_skill(
            home.path(),
            "alera-automations",
            "name: alera-automations\n",
        );
        let lock = json!({ "skills": { "alera-cli": { "ref": COMMIT, "updatedAt": "2026-10-10T00:00:00Z" } } });
        std::fs::write(
            home.path().join(".agents/.skill-lock.json"),
            lock.to_string(),
        )
        .unwrap();

        let report = status_with_commit(home.path(), Some(COMMIT));

        let states = report["skills"]
            .as_array()
            .unwrap()
            .iter()
            .map(|skill| {
                (
                    skill["name"].as_str().unwrap(),
                    skill["state"].as_str().unwrap(),
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            states,
            [
                ("alera-cli", "current"),
                ("alera-orchestration", "outdated"),
                ("alera-automations", "outdated"),
                ("alera-agent-profiles", "missing"),
            ]
        );
        assert_eq!(report["ready"], false);
        assert_eq!(report["pinnedRef"], COMMIT);
        assert_eq!(report["skills"][0]["installedRef"], COMMIT);
        assert_eq!(report["skills"][1]["installedVersion"], 1);
        assert_eq!(report["skills"][3]["installedVersion"], Value::Null);
    }

    #[test]
    fn a_copy_ahead_of_the_runtime_is_newer() {
        let home = tempfile::tempdir().unwrap();
        for kind in SkillKind::ALL {
            let version = kind.contract_version() + i64::from(kind == SkillKind::Cli);
            write_skill(
                home.path(),
                kind.package_name(),
                &format!("metadata:\n  version: {version}\n"),
            );
        }
        let report = status_with_commit(home.path(), None);
        assert_eq!(report["skills"][0]["state"], "newer");
        assert_eq!(report["skills"][1]["state"], "current");
        assert_eq!(report["ready"], false);
        assert_eq!(report["source"], "https://github.com/leynier/alera");
    }
}
