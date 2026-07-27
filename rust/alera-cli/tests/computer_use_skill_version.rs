use std::path::PathBuf;

use alera_core::child_process::windowless_command;

/// The shipped computer-use guide declares a version, and so does the binary
/// whose commands it documents.
///
/// `alera version --json` reports the binary's number so an agent can tell a
/// stale installed skill from a current one. That only means anything while the
/// guide's own number is true: bump one side and forget the other and the
/// command reports a compatibility that does not hold.
#[test]
fn the_computer_use_skill_guide_declares_the_version_the_binary_ships() {
    let guide = repository_path(&["skills", "computer-use", "SKILL.md"]);
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
        binary_skill_version(),
        "{} declares version {declared} but the binary ships \
         COMPUTER_USE_SKILL_VERSION {}. Bump both together.",
        guide.display(),
        binary_skill_version(),
    );
}

/// The guide and the binary have to agree on the verbs.
///
/// Checked against the real `--help` rather than the source, because that is what
/// the agent will actually be able to run: a guide naming a verb the CLI does not
/// offer sends it into an argument error it cannot recover from, and a verb the
/// guide omits is one it will never try.
#[test]
fn the_guide_and_the_binary_offer_the_same_verbs() {
    let help = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args(["computer", "--help"])
        .output()
        .expect("the alera binary runs");
    let help = String::from_utf8_lossy(&help.stdout);
    let guide = std::fs::read_to_string(repository_path(&["skills", "computer-use", "SKILL.md"]))
        .expect("guide is readable");

    for verb in [
        "capabilities",
        "permissions",
        "list-apps",
        "list-windows",
        "get-app-state",
        "click",
        "set-value",
        "perform-secondary-action",
    ] {
        assert!(
            help.contains(verb),
            "`{verb}` is documented in the skill but `alera computer --help` does not offer it"
        );
        assert!(
            guide.contains(verb),
            "`alera computer` offers `{verb}` but the skill never mentions it"
        );
    }
}

/// Read the constant from its source rather than linking the binary crate,
/// which an integration test cannot import.
fn binary_skill_version() -> i64 {
    let protocol = repository_path(&["rust", "alera-cli", "src", "terminal_host", "protocol.rs"]);
    let contents = std::fs::read_to_string(&protocol)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", protocol.display()));
    let declaration = contents
        .lines()
        .find_map(|line| {
            line.trim()
                .strip_prefix("pub const COMPUTER_USE_SKILL_VERSION: i64 = ")
        })
        .unwrap_or_else(|| {
            panic!(
                "COMPUTER_USE_SKILL_VERSION is no longer declared as expected in {}",
                protocol.display()
            )
        });
    declaration
        .trim_end_matches(';')
        .trim()
        .parse()
        .unwrap_or_else(|error| panic!("unreadable COMPUTER_USE_SKILL_VERSION: {error}"))
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
