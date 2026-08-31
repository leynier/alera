use chrono::Utc;
use std::io::{self, Read};

use super::*;
use crate::cli::{AgentProfileRevisionSelectorArgs, AgentProfileSelectorArgs};

fn profile() -> AgentProfile {
    AgentProfile {
        id: "prof_1".to_string(),
        name: "Codex".to_string(),
        sort_order: 0,
        agent_type: "codex".to_string(),
        command: "codex".to_string(),
        launch_mode: AgentProfileLaunchMode::Managed,
        managed_config: Some(json!({"model": "gpt-5.6-sol"})),
        custom_prompt: "Original".to_string(),
        description: "Implementation".to_string(),
        quota_group: Some("personal".to_string()),
        revision: 3,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    }
}

fn update_args() -> AgentProfileUpdateArgs {
    AgentProfileUpdateArgs {
        target: AgentProfileRevisionSelectorArgs {
            selector: AgentProfileSelectorArgs {
                profile_id: Some("prof_1".to_string()),
                profile_name: None,
            },
            expected_revision: None,
        },
        name: None,
        agent_type: None,
        launch_mode: None,
        command: None,
        managed: ManagedConfigInputArgs {
            managed_config: None,
            managed_config_file: None,
            managed_config_stdin: false,
        },
        custom_prompt: None,
        clear_custom_prompt: false,
        description: None,
        clear_description: false,
        quota_group: None,
        clear_quota_group: false,
        confirm_reduced_protections: false,
    }
}

fn create_args() -> AgentProfileCreateArgs {
    AgentProfileCreateArgs {
        name: "Codex".to_string(),
        agent_type: "codex".to_string(),
        launch_mode: AgentProfileLaunchModeArg::Command,
        command: Some("codex".to_string()),
        managed: ManagedConfigInputArgs {
            managed_config: None,
            managed_config_file: None,
            managed_config_stdin: false,
        },
        custom_prompt: None,
        description: None,
        quota_group: None,
        confirm_reduced_protections: false,
    }
}

struct PanicRead;

impl Read for PanicRead {
    fn read(&mut self, _buffer: &mut [u8]) -> io::Result<usize> {
        panic!("stdin must not be read before launch input validation");
    }
}

#[test]
fn update_preserves_unspecified_fields_and_clears_explicit_fields() {
    let existing = profile();
    let mut args = update_args();
    args.name = Some("Codex Sol".to_string());
    args.clear_custom_prompt = true;
    args.clear_quota_group = true;

    let draft = draft_for_update(&existing, &args, None).unwrap();

    assert_eq!(draft.name, "Codex Sol");
    assert_eq!(draft.managed_config, existing.managed_config);
    assert_eq!(draft.description, existing.description);
    assert_eq!(draft.custom_prompt, "");
    assert_eq!(draft.quota_group, None);
}

#[test]
fn changing_to_command_mode_requires_an_explicit_command() {
    let existing = profile();
    let mut args = update_args();
    args.launch_mode = Some(AgentProfileLaunchModeArg::Command);

    let error = draft_for_update(&existing, &args, None).unwrap_err();

    assert!(error.to_string().contains("--command is required"));
}

#[test]
fn create_validates_launch_inputs_before_reading_managed_config_stdin() {
    let mut args = create_args();
    args.managed.managed_config_stdin = true;

    let error = managed_config_for_create(&args, &mut PanicRead).unwrap_err();

    assert!(error.to_string().contains("--launch-mode managed"));
}

#[test]
fn update_validates_launch_inputs_before_reading_managed_config_stdin() {
    let existing = profile();
    let mut args = update_args();
    args.launch_mode = Some(AgentProfileLaunchModeArg::Command);
    args.command = Some("codex".to_string());
    args.managed.managed_config_stdin = true;

    let error = managed_config_for_update(&existing, &args, &mut PanicRead).unwrap_err();

    assert!(error.to_string().contains("--launch-mode managed"));
}

#[test]
fn changing_managed_agent_type_requires_explicit_managed_config() {
    let existing = profile();
    let mut args = update_args();
    args.agent_type = Some("claude".to_string());

    let error = draft_for_update(&existing, &args, None).unwrap_err();

    assert!(error
        .to_string()
        .contains("requires explicit managed configuration"));
    let draft = draft_for_update(&existing, &args, Some(json!({"model": "opus"}))).unwrap();
    assert_eq!(draft.agent_type, "claude");
    assert_eq!(draft.managed_config, Some(json!({"model": "opus"})));
}

#[test]
fn managed_config_must_be_a_json_object() {
    let args = ManagedConfigInputArgs {
        managed_config: Some("[]".to_string()),
        managed_config_file: None,
        managed_config_stdin: false,
    };

    let error = read_managed_config(&args, &mut std::io::empty()).unwrap_err();

    assert!(error.to_string().contains("JSON object"));
}

#[test]
fn newly_reduced_protections_require_confirmation() {
    let mut draft = draft_from_profile(&profile());
    draft.managed_config = Some(json!({"sandbox": "danger-full-access"}));

    let error = ensure_risk_confirmation(Some(&profile()), &draft, false).unwrap_err();

    assert!(error.to_string().contains("--confirm-reduced-protections"));
    ensure_risk_confirmation(Some(&profile()), &draft, true).unwrap();
}

#[test]
fn existing_risk_does_not_require_confirmation_for_other_edits() {
    let mut existing = profile();
    existing.managed_config = Some(json!({"approvalPolicy": "never"}));
    let mut draft = draft_from_profile(&existing);
    draft.description = "Updated".to_string();

    ensure_risk_confirmation(Some(&existing), &draft, false).unwrap();
}

#[test]
fn revision_overrides_reject_duplicates_and_negative_values() {
    assert!(parse_revision_overrides(&["prof_1=-1".to_string()]).is_err());
    assert!(parse_revision_overrides(&["prof_1=1".to_string(), "prof_1=2".to_string()]).is_err());
}
