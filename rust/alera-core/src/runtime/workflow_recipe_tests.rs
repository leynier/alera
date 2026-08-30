use serde_json::json;

use super::{
    builtin_workflow_recipes, WorkflowHumanGate, WorkflowRecipeSnapshot, WorkflowRecipeSource,
    WorkflowRecipeV1,
};

#[test]
fn workflow_builtins_compile_with_portable_contracts_and_human_feature_gates() {
    let recipes = builtin_workflow_recipes();
    assert_eq!(recipes.len(), 2);
    assert_eq!(recipes[0].name, "Quick Fix");
    assert_eq!(recipes[0].stage_order().unwrap(), ["fix", "verify"]);
    assert_eq!(recipes[1].name, "Feature Delivery");
    assert_eq!(
        recipes[1].stages[0].gate,
        Some(WorkflowHumanGate::Foundation)
    );
    assert_eq!(recipes[1].stages[2].gate, Some(WorkflowHumanGate::Product));
    for recipe in recipes {
        recipe.validate().unwrap();
        assert_eq!(
            &WorkflowRecipeV1::from_yaml(&recipe.portable_document().unwrap()).unwrap(),
            recipe
        );
        let serialized = serde_json::to_value(recipe).unwrap();
        for key in ["profileId", "model", "provider", "command", "credentials"] {
            assert!(serialized.get(key).is_none());
        }
    }
}

#[test]
fn workflow_recipe_compilation_rejects_unknown_fields_and_executable_extensions() {
    for path in [
        vec!["hooks"],
        vec!["include"],
        vec!["provider"],
        vec!["roles", "0", "profileId"],
        vec!["stages", "0", "autoApprove"],
        vec!["contracts", "0", "command"],
    ] {
        let mut value = serde_json::to_value(&builtin_workflow_recipes()[0]).unwrap();
        let mut cursor = &mut value;
        for part in &path[..path.len() - 1] {
            cursor = if let Ok(index) = part.parse::<usize>() {
                &mut cursor[index]
            } else {
                &mut cursor[*part]
            };
        }
        cursor[*path.last().unwrap()] = json!("forbidden");
        assert!(
            WorkflowRecipeV1::from_yaml(&value.to_string()).is_err(),
            "{path:?}"
        );
    }
    let mut value = serde_json::to_value(&builtin_workflow_recipes()[1]).unwrap();
    value["stages"][0]["gate"] = json!("automatic");
    assert!(WorkflowRecipeV1::from_yaml(&value.to_string()).is_err());
}

#[test]
fn workflow_recipe_compilation_rejects_missing_references_duplicates_and_cycles() {
    let recipe = builtin_workflow_recipes()[0].clone();
    let mut variants = Vec::new();
    let mut value = recipe.clone();
    value.roles[0].contract_revision += 1;
    variants.push(value);
    let mut value = recipe.clone();
    value.roles[0].contract_id = "absent".into();
    variants.push(value);
    let mut value = recipe.clone();
    value.stages[0].roles = vec!["absent".into()];
    variants.push(value);
    let mut value = recipe.clone();
    value.stages[0].depends_on = vec!["absent".into()];
    variants.push(value);
    let mut value = recipe.clone();
    value.stages[0].depends_on = vec!["verify".into()];
    variants.push(value);
    let mut value = recipe.clone();
    value.stages[0].depends_on = vec!["fix".into()];
    variants.push(value);
    let mut value = recipe.clone();
    value.stages.push(value.stages[0].clone());
    variants.push(value);
    let mut value = recipe.clone();
    value.roles.push(value.roles[0].clone());
    variants.push(value);
    let mut value = recipe.clone();
    value.contracts.push(value.contracts[0].clone());
    variants.push(value);
    let mut value = recipe.clone();
    value.stages[0].roles.clear();
    variants.push(value);
    let mut value = recipe.clone();
    value.stages.clear();
    variants.push(value);
    let mut value = recipe.clone();
    value.contracts[0].required_artifacts = vec!["../secret".into()];
    variants.push(value);
    let mut value = recipe.clone();
    value.contracts[0].input_schema["$ref"] = json!("https://example.invalid/schema");
    variants.push(value);
    let mut value = recipe.clone();
    value.version = 2;
    variants.push(value);
    let mut value = recipe.clone();
    value.revision = 0;
    variants.push(value);
    let mut value = recipe.clone();
    value.stages[0].roles.push("implementer".into());
    variants.push(value);
    let mut value = recipe;
    value.stages[1].depends_on.push("fix".into());
    variants.push(value);
    for (index, recipe) in variants.iter().enumerate() {
        assert!(recipe.validate().is_err(), "variant {index}");
    }
}

#[test]
fn workflow_recipe_product_gate_cannot_exclude_a_stage_or_be_duplicated() {
    let recipe = builtin_workflow_recipes()[1].clone();
    let mut changed = recipe.clone();
    changed.stages[2].depends_on = vec!["foundation".into()];
    assert!(changed.validate().is_err());
    let mut changed = recipe;
    changed.stages[1].gate = Some(WorkflowHumanGate::Product);
    assert!(changed.validate().is_err());
}

#[test]
fn workflow_recipe_snapshots_bind_exact_source_contracts_and_recipe_contents() {
    let recipe = builtin_workflow_recipes()[0].clone();
    let source = WorkflowRecipeSource::BuiltIn {
        id: recipe.id.clone(),
    };
    let frozen = WorkflowRecipeSnapshot::freeze(source, recipe).unwrap();
    frozen.validate().unwrap();
    let mut changed = frozen.clone();
    changed.recipe.contracts[0]
        .instructions
        .push_str(" changed");
    assert!(changed.validate().is_err());
    let mut changed = frozen.clone();
    changed.source = WorkflowRecipeSource::Personal {
        id: changed.recipe.id.clone(),
    };
    assert!(changed.validate().is_err());
    let restored: WorkflowRecipeSnapshot =
        serde_json::from_str(&serde_json::to_string(&frozen).unwrap()).unwrap();
    assert_eq!(frozen, restored);
    for path in [
        "../escape.yaml",
        ".alera/workflows/nested/recipe.yaml",
        ".alera/workflows/x.yml",
        ".alera/workflows/../../escape.yaml",
    ] {
        assert!(WorkflowRecipeSnapshot::freeze(
            WorkflowRecipeSource::Project {
                workspace_id: "workspace".into(),
                path: path.into()
            },
            frozen.recipe.clone()
        )
        .is_err());
    }
}
