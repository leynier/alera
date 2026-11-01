//! A long provider catalog, as OpenCode reports one per configured backend.

use serde_json::{json, Value};

pub(super) fn opencode_models() -> Vec<Value> {
    (0..12)
        .map(|index| {
            json!({"id": format!("backend/model-{index:02}"), "label": format!("Backend Model {index:02}")})
        })
        .collect()
}
