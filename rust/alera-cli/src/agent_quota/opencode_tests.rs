#[test]
fn parses_assistant_usage_for_supported_open_code_providers() {
    let entry = parse_opencode_usage_entry(
        1_000,
        r#"{"role":"assistant","providerID":"opencode-go","cost":1.25}"#,
    )
    .expect("entry");
    assert_eq!(entry.provider, OPENCODE_GO_PROVIDER);
    assert_eq!(entry.cost, 1.25);
}

#[test]
fn ignores_user_messages_and_other_providers() {
    assert!(
        parse_opencode_usage_entry(
            1_000,
            r#"{"role":"user","providerID":"opencode-go","cost":1.25}"#,
        )
        .is_none()
    );
    assert!(
        parse_opencode_usage_entry(
            1_000,
            r#"{"role":"assistant","providerID":"anthropic","cost":1.25}"#,
        )
        .is_none()
    );
}

#[test]
fn parses_authoritative_go_usage_windows() {
    let windows = parse_opencode_go_usage(&json!({
        "usage": {
            "rolling": { "percent": 2, "resetsAt": "2026-08-12T20:56:23.133Z" },
            "weekly": { "percent": 0, "resetsAt": "2026-08-17T00:00:00.133Z" },
            "monthly": { "percent": 101, "resetsAt": "2026-09-07T15:23:19.133Z" }
        }
    }))
    .expect("usage windows");
    assert_eq!(windows.len(), 3);
    assert_eq!(windows[0].label, "5 Hour");
    assert_eq!(windows[0].used_percent, 2.0);
    assert_eq!(windows[2].used_percent, 100.0);
    assert!(windows[0].resets_at.is_some());
}

#[test]
fn parses_opencode_api_credentials_without_exposing_other_auth_types() {
    let auth = json!({
        "opencode-go": { "type": "api", "key": "go-secret" },
        "opencode": { "type": "oauth", "access": "oauth-secret" }
    });
    assert_eq!(
        parse_opencode_auth_key(&auth, OPENCODE_GO_PROVIDER).as_deref(),
        Some("go-secret")
    );
    assert!(parse_opencode_auth_key(&auth, OPENCODE_ZEN_PROVIDER).is_none());
}

#[test]
fn parses_current_session_message_usage_shape() {
    let entry = parse_session_message_usage_entry(
        1_000,
        r#"{"type":"assistant","model":{"providerID":"opencode","id":"gpt-5.5"},"cost":2.5}"#,
    )
    .expect("entry");
    assert_eq!(entry.provider, OPENCODE_ZEN_PROVIDER);
    assert_eq!(entry.cost, 2.5);
}

#[test]
fn prefers_current_opencode_path_and_keeps_platform_fallbacks() {
    let paths = opencode_data_dir_candidates(
        None,
        Some("xdg"),
        Some(std::path::Path::new("home")),
        Some(std::path::Path::new("platform")),
    );
    assert_eq!(
        paths,
        vec![
            PathBuf::from("xdg/opencode"),
            PathBuf::from("home/.local/share/opencode"),
            PathBuf::from("platform/opencode"),
        ]
    );
}

#[test]
fn explicit_data_directory_disables_fallback_search() {
    let paths = opencode_data_dir_candidates(
        Some(" custom "),
        Some("xdg"),
        Some(std::path::Path::new("home")),
        Some(std::path::Path::new("platform")),
    );
    assert_eq!(paths, vec![PathBuf::from("custom")]);
}

#[test]
fn duplicate_home_platform_paths_are_removed() {
    let paths = opencode_data_dir_candidates(
        None,
        None,
        Some(std::path::Path::new("home")),
        Some(std::path::Path::new("home/.local/share")),
    );
    assert_eq!(paths, vec![PathBuf::from("home/.local/share/opencode")]);
}
