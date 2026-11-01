use super::*;

use serde_json::json;

#[test]
fn the_model_id_option_wins_over_an_earlier_model_category_option() {
    let options = vec![
        json!({"id":"provider","category":"model","type":"select","options":[{"value":"vercel"}]}),
        json!({"id":"model","type":"select","options":[{"value":"grok-4","name":"Grok 4"}]}),
    ];
    assert_eq!(option_id(model_option(&options).unwrap()), Some("model"));
    let only_category =
        vec![json!({"id":"llm","category":"model","type":"select","options":[{"value":"a"}]})];
    assert_eq!(
        option_id(model_option(&only_category).unwrap()),
        Some("llm")
    );
    let not_select = vec![json!({"id":"model","type":"boolean"})];
    assert!(model_option(&not_select).is_none());
}

#[test]
fn legacy_state_lists_unique_models_and_the_current_one() {
    let raw = json!({"models":{
        "availableModels":[
            {"modelId":"grok-4","name":"Grok 4"},
            {"modelId":"grok-4"},
            {"modelId":"grok-code"},
            {"name":"no id"}
        ],
        "currentModelId":"grok-4"
    }});
    let state = legacy_model_state(&raw).unwrap();
    assert_eq!(
        state.available,
        vec![
            ("grok-4".into(), "Grok 4".into()),
            ("grok-code".into(), "grok-code".into())
        ]
    );
    assert_eq!(state.current.as_deref(), Some("grok-4"));
    assert!(legacy_model_state(&json!({})).is_none());
}

#[test]
fn inventory_prefers_the_option_unless_grok_v1_keeps_its_legacy_state() {
    let options = vec![json!({"id":"model","type":"select","options":[{"value":"a"}]})];
    let legacy = LegacyModelState {
        available: vec![("b".into(), "B".into())],
        current: None,
    };
    assert_eq!(
        inventory(&options, Some(&legacy), false, false),
        ModelInventory::Option {
            id: "model".into(),
            values: vec!["a".into()]
        }
    );
    assert_eq!(
        inventory(&options, Some(&legacy), true, false),
        ModelInventory::Legacy(legacy.clone())
    );
    assert_eq!(
        inventory(&[], Some(&legacy), false, false),
        ModelInventory::Legacy(legacy.clone())
    );
    assert_eq!(
        inventory(&[], None, false, true),
        ModelInventory::Capability
    );
    assert_eq!(inventory(&[], None, false, false), ModelInventory::Unknown);
}

#[test]
fn choices_flatten_option_groups() {
    let options = vec![
        json!({"id":"model","type":"select","currentValue":"b","options":[
            {"value":"a","name":"A"},
            {"name":"group","options":[{"value":"b"},{"value":"a"}]}
        ]}),
    ];
    assert_eq!(
        session_model_choices(&options, None),
        vec![("a".into(), "A".into()), ("b".into(), "b".into())]
    );
    assert_eq!(current_model(&options, None).as_deref(), Some("b"));
}

#[test]
fn offered_models_gate_writes_and_family_variants_extend_listed_ids() {
    let offered = vec!["gemini-3.8-flash".to_owned(), "gemini-3.8".to_owned()];
    assert!(offers_model(&[], "anything", false));
    assert!(offers_model(&offered, "gemini-3.8", false));
    assert!(!offers_model(&offered, "gemini-3.8-flash-high", false));
    assert!(offers_model(&offered, "gemini-3.8-flash-high", true));
    assert!(!offers_model(&offered, "gemini-3.8-", true));
    assert!(!offers_model(&offered, "gemini-3.80", true));
    assert!(!offers_model(&offered, "claude-opus", true));
}
