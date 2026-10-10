use serde_json::json;

use super::*;

#[test]
fn clone_folders_follow_git_clone_naming() {
    for (url, name) in [
        ("https://github.com/acme/widgets.git", "widgets"),
        ("https://github.com/acme/widgets/", "widgets"),
        ("git@github.com:acme/widgets.git", "widgets"),
        ("/srv/repos/tools", "tools"),
    ] {
        assert_eq!(repository_name(url).unwrap(), name, "{url}");
    }
    for url in ["", "  ", "/", "https://example.com/.git"] {
        assert!(repository_name(url).is_err(), "{url}");
    }
}

#[test]
fn settings_changes_replace_only_their_sections() {
    let current = json!({
        "worktree": {"copy": [{"from": ".env", "overwrite": false}], "setup": ["npm ci"]},
        "newWorkspace": {"promptAppend": "Be brief", "sourceBranch": "main"},
        "gitHostingProvider": "github",
    });
    let changes = parse_config_changes(
        r#"{"newWorkspace": {"promptAppend": "", "sourceBranch": "develop"}, "gitHostingProvider": "auto"}"#,
    )
    .unwrap();
    let merged = merge_config(current, changes);
    assert_eq!(merged["worktree"]["setup"], json!(["npm ci"]));
    assert_eq!(merged["newWorkspace"]["sourceBranch"], "develop");
    assert!(merged.get("gitHostingProvider").is_none());
    let config: alera_core::runtime::ProjectConfig = serde_json::from_value(merged).unwrap();
    assert_eq!(config.new_workspace.source_branch, "develop");
}

#[test]
fn settings_reject_unknown_keys_and_non_objects() {
    assert!(parse_config_changes(r#"{"theme": "dark"}"#)
        .unwrap_err()
        .to_string()
        .contains("Unknown project setting `theme`"));
    assert!(parse_config_changes("[]").is_err());
    assert!(parse_config_changes(&"x".repeat(MAX_CONFIG_BYTES + 1)).is_err());
}
