use serde_json::json;

use super::{
    PromptWorkspaceOperation, PromptWorkspaceRequest, SectionPolicy, StartMode, CANCELLED,
    COMPLETED, FAILED,
};

fn operation() -> PromptWorkspaceOperation {
    PromptWorkspaceOperation::new(
        "op-1".to_owned(),
        Some("req-1".to_owned()),
        "Fix the login screen".to_owned(),
        PromptWorkspaceRequest::default(),
        None,
    )
}

#[test]
fn section_policy_accepts_the_four_forms() {
    assert_eq!(SectionPolicy::parse(None).unwrap(), SectionPolicy::Auto);
    assert_eq!(
        SectionPolicy::parse(Some(&json!("none"))).unwrap(),
        SectionPolicy::None
    );
    assert_eq!(
        SectionPolicy::parse(Some(&json!({ "id": "s-1" }))).unwrap(),
        SectionPolicy::Id("s-1".to_owned())
    );
    assert_eq!(
        SectionPolicy::parse(Some(&json!({ "name": " Alera " }))).unwrap(),
        SectionPolicy::Name("Alera".to_owned())
    );
    assert!(SectionPolicy::parse(Some(&json!("Alera"))).is_err());
    assert!(SectionPolicy::parse(Some(&json!({ "id": "a", "name": "b" }))).is_err());
}

#[test]
fn requests_default_to_auto_mode_and_section() {
    let request: PromptWorkspaceRequest = serde_json::from_value(json!({})).unwrap();
    assert_eq!(request.mode, StartMode::Auto);
    assert_eq!(request.section, SectionPolicy::Auto);
    let checkout: PromptWorkspaceRequest =
        serde_json::from_value(json!({ "mode": "projectCheckout" })).unwrap();
    assert_eq!(checkout.mode, StartMode::ProjectCheckout);
}

#[test]
fn public_values_never_carry_the_prompt() {
    let operation = operation();
    assert!(operation.to_value().get("prompt").is_some());
    let public = operation.public_value();
    assert!(public.get("prompt").is_none());
    assert_eq!(public["promptHash"].as_str().unwrap().len(), 64);
    assert_eq!(public["clientMutationId"], "prompt-workspace-op-1");
}

#[test]
fn finished_operations_drop_the_prompt_unless_a_launch_retry_needs_it() {
    let mut done = operation();
    done.finish(COMPLETED);
    assert!(done.prompt.is_none());
    assert_eq!(done.phase, "done");

    let mut before_creation = operation();
    before_creation.fail("failed", "boom", false);
    assert!(before_creation.prompt.is_none());

    let mut after_creation = operation();
    after_creation.workspace = Some(json!({ "id": "w-1" }));
    after_creation.fail("failed", "launch failed", true);
    assert_eq!(after_creation.status, FAILED);
    assert!(after_creation.can_retry_launch());
    assert!(after_creation.prompt.is_some());

    let mut cancelled = operation();
    cancelled.workspace = Some(json!({ "id": "w-1" }));
    cancelled.finish(CANCELLED);
    assert!(cancelled.can_retry_launch());
}
