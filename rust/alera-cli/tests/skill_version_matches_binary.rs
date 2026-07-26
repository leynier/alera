use std::path::PathBuf;

/// The shipped skill guide declares a version, and so does the binary that runs
/// the commands it documents. Nothing kept the two in step.
///
/// `alera version --json` reports both `skillVersion` and
/// `runtimeHostSkillVersion` so a CLI/host mismatch is detectable, and the
/// guide tells agents to consult it. All of that is built on the guide's own
/// number being true. Bump one side and forget the other and the command
/// reports a compatibility that does not hold, confidently.
#[test]
fn the_orchestration_skill_guide_declares_the_version_the_binary_ships() {
    let guide = repository_path(&["skills", "alera-orchestration", "SKILL.md"]);
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
        alera_cli_orchestration_skill_version(),
        "{} declares version {declared} but the binary ships \
         ORCHESTRATION_SKILL_VERSION {}. Bump both together: `alera version --json` \
         reports the binary's number, so a one-sided bump makes it lie.",
        guide.display(),
        alera_cli_orchestration_skill_version(),
    );
}

/// Read the constant from its source rather than linking the binary crate,
/// which an integration test cannot import.
fn alera_cli_orchestration_skill_version() -> i64 {
    let protocol = repository_path(&["rust", "alera-cli", "src", "terminal_host", "protocol.rs"]);
    let contents = std::fs::read_to_string(&protocol)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", protocol.display()));
    let declaration = contents
        .lines()
        .find_map(|line| {
            line.trim()
                .strip_prefix("pub const ORCHESTRATION_SKILL_VERSION: i64 = ")
        })
        .unwrap_or_else(|| {
            panic!(
                "ORCHESTRATION_SKILL_VERSION is no longer declared as expected in {}",
                protocol.display()
            )
        });
    declaration
        .trim_end_matches(';')
        .trim()
        .parse()
        .unwrap_or_else(|error| panic!("unreadable ORCHESTRATION_SKILL_VERSION: {error}"))
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
