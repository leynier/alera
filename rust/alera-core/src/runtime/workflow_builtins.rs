use std::sync::OnceLock;

use super::WorkflowRecipeV1;

pub fn builtin_workflow_recipes() -> &'static [WorkflowRecipeV1] {
    static RECIPES: OnceLock<Vec<WorkflowRecipeV1>> = OnceLock::new();
    RECIPES.get_or_init(|| {
        [
            include_str!("workflows/quick-fix.yaml"),
            include_str!("workflows/feature-delivery.yaml"),
        ]
        .iter()
        .map(|source| {
            WorkflowRecipeV1::from_yaml(source).expect("built-in workflow recipe must compile")
        })
        .collect()
    })
}
