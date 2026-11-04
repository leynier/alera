//! What the chat tools tell an agent about waiting: a bound chat is woken
//! by its delegated tasks, so it ends its turn; a terminal or CLI caller is
//! never woken, so it keeps waiting.

use super::find_chat_tool;
use super::stdio_server::{CHAT_INSTRUCTIONS, INSTRUCTIONS};

fn description(name: &str) -> String {
    find_chat_tool(name)
        .unwrap_or_else(|| panic!("{name} is a chat tool"))
        .to_json()["description"]
        .as_str()
        .unwrap()
        .to_owned()
}

#[test]
fn bound_instructions_say_to_end_the_turn_instead_of_polling() {
    assert!(!CHAT_INSTRUCTIONS.contains("at most 50 seconds"));
    assert!(CHAT_INSTRUCTIONS.contains("follow next and end your turn"));
    assert!(CHAT_INSTRUCTIONS.contains("Never poll"));
    assert!(description("chat_delegate").contains("end your turn"));
    assert!(description("chat_task_wait").contains("only when this turn cannot go on"));
    assert!(!description("chat_task_wait").contains("call again"));
}

#[test]
fn unbound_callers_still_wait_and_call_again() {
    assert!(INSTRUCTIONS.contains("call them again to keep waiting"));
    let query = super::find_tool("chat_task_query").unwrap().to_json();
    assert!(query["description"]
        .as_str()
        .unwrap()
        .contains("wait again to keep waiting"));
}
