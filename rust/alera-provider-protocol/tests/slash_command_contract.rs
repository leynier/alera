use alera_provider_protocol::{
    normalize_slash_commands, EventKind, ProviderError, ProviderEvent, ProviderKind,
    ProviderSlashCommand, ProviderSlashCommandInput, ProviderSlashCommandsUpdate,
    MAX_PROVIDER_SLASH_COMMANDS,
};
use serde_json::json;

fn commands_event(payload: serde_json::Value) -> ProviderEvent {
    ProviderEvent::new(
        ProviderKind::Other("acp".into()),
        "acp-instance",
        "00000000-0000-4000-8000-000000000002",
        EventKind::SessionCommandsUpdated,
        payload,
        None,
    )
}

#[test]
fn the_event_kind_round_trips_on_the_wire() {
    assert_eq!(
        EventKind::SessionCommandsUpdated.as_str(),
        "session.commands.updated"
    );
    let parsed: EventKind = serde_json::from_value(json!("session.commands.updated")).unwrap();
    assert_eq!(parsed, EventKind::SessionCommandsUpdated);
}

#[test]
fn native_fields_are_trimmed_and_untypeable_names_are_dropped() {
    let command =
        ProviderSlashCommand::from_native(" /review ", Some("  Review a PR "), Some(" ")).unwrap();
    assert_eq!(
        command,
        ProviderSlashCommand {
            name: "review".into(),
            description: Some("Review a PR".into()),
            input: None,
        }
    );
    assert!(ProviderSlashCommand::from_native("  ", None, None).is_none());
    assert!(ProviderSlashCommand::from_native("/", None, None).is_none());
    assert!(ProviderSlashCommand::from_native("two words", None, None).is_none());
    assert!(ProviderSlashCommand::from_native(&"x".repeat(65), None, None).is_none());
    let long = ProviderSlashCommand::from_native("x", Some(&"d".repeat(900)), None).unwrap();
    assert_eq!(long.description.unwrap().chars().count(), 500);
}

#[test]
fn duplicates_merge_into_the_first_entry_without_case() {
    let commands = normalize_slash_commands([
        ProviderSlashCommand::from_native("Compact", None, None).unwrap(),
        ProviderSlashCommand::from_native("init", Some("Create AGENTS.md"), None).unwrap(),
        ProviderSlashCommand::from_native("compact", Some("Summarize"), Some("instructions"))
            .unwrap(),
    ]);
    assert_eq!(
        commands,
        vec![
            ProviderSlashCommand {
                name: "Compact".into(),
                description: Some("Summarize".into()),
                input: Some(ProviderSlashCommandInput {
                    hint: "instructions".into()
                }),
            },
            ProviderSlashCommand {
                name: "init".into(),
                description: Some("Create AGENTS.md".into()),
                input: None,
            },
        ]
    );
}

#[test]
fn the_list_is_bounded() {
    let update =
        ProviderSlashCommandsUpdate::new((0..MAX_PROVIDER_SLASH_COMMANDS + 20).map(|index| {
            ProviderSlashCommand::from_native(&format!("c{index}"), None, None).unwrap()
        }));
    assert_eq!(update.commands.len(), MAX_PROVIDER_SLASH_COMMANDS);
}

#[test]
fn the_payload_validates_and_serializes_in_camel_case() {
    let update = ProviderSlashCommandsUpdate::new([ProviderSlashCommand::from_native(
        "plan",
        Some("Draft a plan"),
        Some("goal"),
    )
    .unwrap()]);
    assert_eq!(
        update.payload(),
        json!({"commands": [{"name": "plan", "description": "Draft a plan", "input": {"hint": "goal"}}]})
    );
    commands_event(update.payload()).validate().unwrap();
    commands_event(json!({"commands": []})).validate().unwrap();
    for invalid in [
        json!({"commands": {}}),
        json!({"commands": [{"description": "no name"}]}),
        json!({"commands": [{"name": ""}]}),
    ] {
        assert!(matches!(
            commands_event(invalid).validate(),
            Err(ProviderError::Validation(_))
        ));
    }
}
