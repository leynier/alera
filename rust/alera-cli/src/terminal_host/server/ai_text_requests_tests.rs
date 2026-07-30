use super::*;

#[test]
fn custom_command_uses_stdin_without_placeholder() {
    let plan = plan_custom_command("agent --quiet", "hello").unwrap();
    assert_eq!(plan.binary, "agent");
    assert_eq!(plan.arguments, ["--quiet"]);
    assert_eq!(plan.stdin_payload.as_deref(), Some("hello"));
}
