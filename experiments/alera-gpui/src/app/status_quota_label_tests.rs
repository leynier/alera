use super::{provider_label, QuotaSnapshot};

#[test]
fn quota_opencode_labels_prefix_account_names_only_once() {
    for (display_name, expected) in [
        ("Go", "OpenCode Go"),
        ("Zen", "OpenCode Zen"),
        ("OpenCode Go", "OpenCode Go"),
        ("OpenCode Zen", "OpenCode Zen"),
        (" OpenCode Go ", "OpenCode Go"),
        ("OpenCode", "OpenCode"),
        ("", "OpenCode"),
    ] {
        let snapshot = QuotaSnapshot {
            provider: "opencode".to_owned(),
            account_id: "review".to_owned(),
            display_name: display_name.to_owned(),
            status: "unconfigured".to_owned(),
            error: None,
            readings: vec![],
            data_quality: None,
            reset_credits: None,
        };
        assert_eq!(provider_label(&snapshot), expected);
    }
}
