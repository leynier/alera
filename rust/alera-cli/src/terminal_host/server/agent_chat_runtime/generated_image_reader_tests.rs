use super::*;

#[test]
fn only_a_generated_image_item_names_a_file() {
    let item = json!({
        "type": "image_generation",
        "normalized": {"imagePath": "/codex/a.png"},
        "data": {"savedPath": "/codex/b.png"},
    });
    assert_eq!(generated_image_path(&item).unwrap(), "/codex/a.png");
    let saved = json!({"type": "image_generation", "data": {"savedPath": "/codex/b.png"}});
    assert_eq!(generated_image_path(&saved).unwrap(), "/codex/b.png");
    let code = |item: Value| generated_image_path(&item).unwrap_err().to_string();
    assert!(
        code(json!({"type": "image_view", "normalized": {"imagePath": "/x.png"}}))
            .contains("not a generated image")
    );
    assert!(code(json!({"type": "image_generation", "data": {}})).contains("no saved file"));
}
