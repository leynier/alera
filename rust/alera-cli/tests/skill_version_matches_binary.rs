use std::path::PathBuf;

/// The shipped skill guide declares a version, and so does the binary that runs
/// the commands it documents. Nothing kept the two in step.
///
/// `alera version --json` reports both `skillVersion` and
/// `runtimeHostSkillVersion` so a CLI/host mismatch is detectable, and the
/// guide tells agents to consult it. All of that is built on the guide's own
/// number being true. Bump one side and forget the other and the command
/// reports a compatibility that does not hold, confidently.
/// Each skill folder and the constant in `protocol.rs` holding its version.
const SKILLS: &[(&str, &str)] = &[
    ("alera-cli", "CLI_SKILL_VERSION"),
    ("alera-orchestration", "ORCHESTRATION_SKILL_VERSION"),
    ("alera-automations", "AUTOMATIONS_SKILL_VERSION"),
    ("alera-agent-profiles", "AGENT_PROFILES_SKILL_VERSION"),
];

/// `alera skill status` calls an installed skill current when its version
/// equals the runtime's, so a content change must come with a version bump.
/// Update a digest here only together with that bump.
const DIGESTS: &[(&str, i64, &str)] = &[
    (
        "alera-cli",
        1,
        "39b86b4ca69b899f5134037d528898d19ee431493dac011c131eb6c875668ca9",
    ),
    (
        "alera-orchestration",
        3,
        "20e5f07928eb4875e44778eba2a35ea50d76e5b1b6a7aaedeb15c1c67c3efe0f",
    ),
    (
        "alera-automations",
        1,
        "757e9bfbfd48efa751bcb458f4d528b9781e4db03d2bd1f979e31a639614fff7",
    ),
    (
        "alera-agent-profiles",
        1,
        "84ed0aebcdf7b00cba2132ee714ef0d3f405d94f9d3f63d6b6b4144c82472a23",
    ),
];

#[test]
fn every_skill_guide_declares_the_version_the_binary_ships() {
    for (folder, constant) in SKILLS {
        let guide = repository_path(&["skills", folder, "SKILL.md"]);
        let contents = std::fs::read_to_string(&guide)
            .unwrap_or_else(|error| panic!("cannot read {}: {error}", guide.display()));

        let declared = frontmatter_version(&contents).unwrap_or_else(|| {
            panic!(
                "{} has no `version:` in its frontmatter, so nothing pins it to the binary",
                guide.display()
            )
        });

        assert_eq!(
            declared,
            binary_skill_version(constant),
            "{} declares version {declared} but the binary ships {constant} {}. Bump both \
             together: `alera version --json` and `alera skill status` report the binary's \
             number, so a one-sided bump makes them lie.",
            guide.display(),
            binary_skill_version(constant),
        );
    }
}

#[test]
fn a_skill_whose_content_changed_bumps_its_version() {
    for (folder, version, digest) in DIGESTS {
        let declared = frontmatter_version(
            &std::fs::read_to_string(repository_path(&["skills", folder, "SKILL.md"])).unwrap(),
        );
        let actual = folder_digest(&repository_path(&["skills", folder]));
        assert!(
            declared == Some(*version) && actual == *digest,
            "skills/{folder} changed. Bump its metadata.version and the matching constant in \
             protocol.rs, then record version {} and digest {actual} in DIGESTS.",
            declared.unwrap_or_default(),
        );
    }
}

/// SHA-256 over every file's relative path and content, with CRLF read as LF.
fn folder_digest(folder: &std::path::Path) -> String {
    use sha2::{Digest, Sha256};
    let mut files = Vec::new();
    collect_files(folder, folder, &mut files);
    files.sort();
    let mut hasher = Sha256::new();
    for relative in files {
        let bytes = std::fs::read(folder.join(&relative)).unwrap();
        let text = String::from_utf8(bytes).unwrap().replace("\r\n", "\n");
        hasher.update(relative.as_bytes());
        hasher.update([0]);
        hasher.update(text.as_bytes());
        hasher.update([0]);
    }
    hex::encode(hasher.finalize())
}

fn collect_files(root: &std::path::Path, folder: &std::path::Path, files: &mut Vec<String>) {
    for entry in std::fs::read_dir(folder).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            collect_files(root, &path, files);
        } else {
            let relative = path.strip_prefix(root).unwrap();
            let parts = relative
                .iter()
                .map(|part| part.to_string_lossy())
                .collect::<Vec<_>>();
            files.push(parts.join("/"));
        }
    }
}

/// Read the constant from its source rather than linking the binary crate,
/// which an integration test cannot import.
fn binary_skill_version(constant: &str) -> i64 {
    let protocol = repository_path(&["rust", "alera-cli", "src", "terminal_host", "protocol.rs"]);
    let contents = std::fs::read_to_string(&protocol)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", protocol.display()));
    let prefix = format!("pub const {constant}: i64 = ");
    let declaration = contents
        .lines()
        .find_map(|line| line.trim().strip_prefix(prefix.as_str()))
        .unwrap_or_else(|| {
            panic!(
                "{constant} is no longer declared as expected in {}",
                protocol.display()
            )
        });
    declaration
        .trim_end_matches(';')
        .trim()
        .parse()
        .unwrap_or_else(|error| panic!("unreadable {constant}: {error}"))
}

/// The first `version:` inside the leading `---` frontmatter block.
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

fn repository_path(segments: &[&str]) -> PathBuf {
    // CARGO_MANIFEST_DIR is <repo>/rust/alera-cli.
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop();
    path.pop();
    path.extend(segments);
    path
}

#[test]
fn the_frontmatter_reader_only_trusts_a_leading_block() {
    // A `version:` further down the document describes something else, and
    // reading it would let the real one drift unnoticed.
    assert_eq!(frontmatter_version("---\nversion: 7\n---\nbody\n"), Some(7));
    assert_eq!(frontmatter_version("---\nname: x\n---\nversion: 9\n"), None);
    assert_eq!(frontmatter_version("version: 9\n"), None);
    assert_eq!(frontmatter_version("---\nname: x\n---\n"), None);
}
