use super::{orchestration_instruction_sections, INSTRUCTION_SECTION_MAX_BYTES};
use crate::mcp_tools::find_chat_tool;

const PROVIDERS: &[&str] = &[
    "codex",
    "claudeAgent",
    "cursor",
    "grok",
    "antigravity",
    "acpRegistry",
    "opencode",
    "pi",
    "muse",
];

fn named_tools(text: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut rest = text;
    while let Some(start) = rest.find("chat_") {
        let tail = &rest[start..];
        let end = tail
            .find(|c: char| !(c.is_ascii_lowercase() || c == '_'))
            .unwrap_or(tail.len());
        names.push(tail[..end].to_owned());
        rest = &tail[end..];
    }
    names
}

#[test]
fn every_section_fits_and_names_only_real_chat_tools() {
    for provider in PROVIDERS {
        let sections = orchestration_instruction_sections(provider);
        assert!(!sections.is_empty());
        for section in &sections {
            assert!(section.len() <= INSTRUCTION_SECTION_MAX_BYTES, "{provider}");
            for name in named_tools(section) {
                assert!(find_chat_tool(&name).is_some(), "{provider} names {name}");
            }
        }
    }
}

#[test]
fn the_rules_say_to_end_the_turn_and_never_to_poll() {
    let text = orchestration_instruction_sections("codex").join("\n");
    for rule in [
        "follow next and end your turn",
        "Do not poll",
        "chat_task_cancel, never chat_interrupt",
        "a new chat_delegate",
        "Call chat_capabilities once",
        "chat_respond",
        "start no chat_delegate unless your task says to",
    ] {
        assert!(text.contains(rule), "missing: {rule}");
    }
    assert!(!text.contains("at most 50 seconds"));
    assert!(!text.contains("call again"));
    assert!(text.contains("spawn_agent"));
}

#[test]
fn claude_learns_its_native_agent_and_how_to_load_the_tools() {
    let sections = orchestration_instruction_sections("claudeAgent");
    assert_eq!(sections.len(), 2);
    assert!(sections[0].contains("Agent with run_in_background:false"));
    assert!(sections[1].starts_with("The alera chat tools are deferred."));
    assert!(sections[1].contains("ToolSearch select:mcp__alera__chat_capabilities"));
    let cursor = orchestration_instruction_sections("cursor");
    assert_eq!(cursor.len(), 1);
    assert!(!cursor[0].contains("spawn_agent"));
}
