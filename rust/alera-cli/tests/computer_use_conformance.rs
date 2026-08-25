//! Invariants of the computer-use surface that are easy to break from far away.
//!
//! These read the source rather than call the code, because the properties are
//! about the shape of the surface: which verbs exist, what the skill promises,
//! and which guards are wired in. A unit test in the module would not notice a
//! guard being removed from its one call site.

use std::path::PathBuf;

/// Every error code the module defines has to appear in the skill, since the
/// guide is where an agent learns what to do about it.
#[test]
fn the_skill_documents_every_error_code() {
    let error_source = read(&["rust", "alera-cli", "src", "computer_use", "error.rs"]);
    let guide = read(&["skills", "alera-computer-use", "SKILL.md"]);

    let codes: Vec<&str> = error_source
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            let (_, rest) = line.split_once("=> \"")?;
            let (code, _) = rest.split_once('"')?;
            code.chars()
                .all(|c| c.is_ascii_lowercase() || c == '_')
                .then_some(code)
        })
        .collect();

    assert!(
        codes.len() >= 16,
        "expected the closed set of error codes, found {}: {codes:?}",
        codes.len()
    );
    for code in codes {
        if UNREACHABLE_IN_THIS_BUILD.contains(&code) {
            continue;
        }
        assert!(
            guide.contains(code),
            "error code `{code}` is not documented in the computer-use skill"
        );
    }
}

/// Codes the shipped surface cannot currently produce, so documenting them would
/// tell agents to recover from something they will never meet.
///
/// `window_not_focused` belongs to synthetic input, `window_stale` to platforms
/// with window handles, and `provider_incompatible` to a helper process. Each
/// arrives with the code path that emits it, and the test above starts requiring
/// its documentation the moment it leaves this list.
const UNREACHABLE_IN_THIS_BUILD: &[&str] = &[
    "window_not_focused",
    "window_stale",
    "provider_incompatible",
];

/// A paired phone must never drive the desktop. The mobile allowlist is a
/// whitelist, so this holds by omission; the test keeps a later addition from
/// quietly granting it.
#[test]
fn no_computer_verb_is_on_the_mobile_allowlist() {
    let allowlist = read(&[
        "rust",
        "alera-cli",
        "src",
        "terminal_host",
        "server",
        "mobile_terminal_requests.rs",
    ]);
    let listed: Vec<&str> = allowlist
        .lines()
        .filter(|line| line.trim().contains("\"computer."))
        .collect();
    assert!(
        listed.is_empty(),
        "computer-use verbs must stay off the mobile allowlist, found: {listed:?}"
    );
}

/// Adding a verb must not bump the wire version: a mismatch makes the app treat
/// a live host as unusable, and computer use is purely additive.
#[test]
fn the_protocol_version_is_unchanged_by_computer_use() {
    let protocol = read(&["rust", "alera-cli", "src", "terminal_host", "protocol.rs"]);
    let dart = read(&[
        "lib",
        "src",
        "features",
        "workbench",
        "infra",
        "terminal_host",
        "terminal_host_protocol.dart",
    ]);
    assert!(
        protocol.contains("pub const PROTOCOL_VERSION: i64 = 4;"),
        "computer use is additive and must not bump PROTOCOL_VERSION"
    );
    assert!(
        dart.contains("const int aleraTerminalHostProtocolVersion = 4;"),
        "the Dart mirror must stay in lockstep with the host"
    );
    assert!(
        protocol.contains("computerUseV1"),
        "the capability is how clients feature-check computer use"
    );
}

/// The blocked-app gate has to be applied on the paths that observe or act, not
/// merely defined.
#[test]
fn the_blocked_app_gate_is_wired_into_the_linux_provider() {
    let provider = read(&[
        "rust",
        "alera-cli",
        "src",
        "computer_use",
        "linux",
        "mod.rs",
    ]);
    let guarded = provider.matches("ensure_app_allowed").count();
    assert!(
        guarded >= 3,
        "expected list_windows, snapshot and act to check the blocked-app gate, \
         found {guarded} call(s)"
    );
}

/// Synthetic input cannot work without a route into the session, so it must not
/// be advertised while there is none. Advertising it would have agents plan
/// around verbs that fail.
#[test]
fn linux_does_not_advertise_synthetic_input() {
    let capabilities = read(&[
        "rust",
        "alera-cli",
        "src",
        "computer_use",
        "linux",
        "linux_capabilities.rs",
    ]);
    for flag in [
        "type_text: false",
        "press_key: false",
        "hotkey: false",
        "paste_text: false",
        "scroll: false",
        "drag: false",
    ] {
        assert!(
            capabilities.contains(flag),
            "expected `{flag}` while there is no synthetic input route on Linux"
        );
    }
}

fn read(segments: &[&str]) -> String {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop();
    path.pop();
    path.extend(segments);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", path.display()))
}
