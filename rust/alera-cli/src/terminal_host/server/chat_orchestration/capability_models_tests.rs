use serde_json::{json, Value};

use super::{shorten_models, CallerModel, CAPABILITY_MODEL_LIMIT};

fn provider(kind: &str, count: usize) -> Value {
    let mut models: Vec<Value> = (0..count)
        .map(|index| json!({"id": format!("model-{index:02}"), "label": format!("Model {index:02}"), "isDefault": false}))
        .collect();
    models.push(json!({"id": "configured-one", "label": "configured-one", "source": "configured", "isDefault": false}));
    json!({"provider": kind, "providerInstanceId": kind, "models": models})
}

fn ids(provider: &Value) -> Vec<String> {
    provider["models"]
        .as_array()
        .unwrap()
        .iter()
        .map(|model| model["id"].as_str().unwrap_or("default").to_owned())
        .collect()
}

#[test]
fn a_long_catalog_lists_the_first_models_in_order_and_keeps_pinned_ones() {
    let preferences = json!({
        "models": {"opencode": {"hidden": ["model-00", "configured-one"], "order": ["model-11", "model-10"]}},
        "favorites": [{"providerInstanceId": "opencode", "model": "model-09"}],
    });
    let mut providers = vec![provider("opencode", 12)];
    providers[0]["models"][3]["isDefault"] = json!(true);
    let caller = CallerModel {
        provider_instance_id: "opencode",
        model: Some("model-08"),
    };
    shorten_models(&mut providers, &preferences, Some(&caller), None);
    let listed = ids(&providers[0]);
    assert_eq!(&listed[..2], ["model-11", "model-10"]);
    assert!(!listed.contains(&"model-00".to_owned()), "hidden");
    for pinned in ["configured-one", "model-03", "model-08", "model-09"] {
        assert!(listed.contains(&pinned.to_owned()), "{pinned} is pinned");
    }
    assert_eq!(
        providers[0]["omittedModels"].as_u64().unwrap() as usize + listed.len(),
        12
    );
}

#[test]
fn curated_providers_list_every_model_and_search_finds_the_rest() {
    let mut providers = vec![provider("codex", 12), provider("opencode", 12)];
    shorten_models(&mut providers, &json!({}), None, None);
    assert_eq!(providers[0]["models"].as_array().unwrap().len(), 13);
    assert!(providers[0].get("omittedModels").is_none());
    assert_eq!(
        providers[1]["models"].as_array().unwrap().len(),
        CAPABILITY_MODEL_LIMIT + 1
    );

    let mut searched = vec![provider("opencode", 12)];
    shorten_models(&mut searched, &json!({}), None, Some("model 1"));
    assert_eq!(ids(&searched[0]), ["model-01", "model-10", "model-11"]);
    assert!(searched[0].get("omittedModels").is_none());
    let mut broad = vec![provider("opencode", 12)];
    shorten_models(&mut broad, &json!({}), None, Some("MODEL"));
    assert_eq!(ids(&broad[0]).len(), CAPABILITY_MODEL_LIMIT);
    assert_eq!(broad[0]["omittedModels"], 4);
}

#[test]
fn the_provider_default_placeholder_is_never_hidden() {
    let mut providers = vec![json!({"provider": "pi", "providerInstanceId": "pi",
        "models": [{"id": null, "label": "Provider Default", "isDefault": true}]})];
    shorten_models(&mut providers, &json!({}), None, None);
    assert_eq!(providers[0]["models"].as_array().unwrap().len(), 1);
}
