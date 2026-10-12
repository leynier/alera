use std::sync::OnceLock;

use super::WorkflowRecipeV1;

pub fn builtin_workflow_recipes() -> &'static [WorkflowRecipeV1] {
    static RECIPES: OnceLock<Vec<WorkflowRecipeV1>> = OnceLock::new();
    RECIPES.get_or_init(|| {
        [
            include_str!("recipes/quick-fix.yaml"),
            include_str!("recipes/feature-delivery.yaml"),
            include_str!("recipes/freeform.yaml"),
        ]
        .iter()
        .map(|source| {
            WorkflowRecipeV1::from_yaml(source).expect("built-in workflow recipe must compile")
        })
        .collect()
    })
}
