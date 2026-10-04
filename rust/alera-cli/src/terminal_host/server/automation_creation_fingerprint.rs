use alera_core::runtime::AutomationDefinition;
use serde_json::Value;
use sha2::{Digest, Sha256};

pub(super) fn fingerprint(definition: &AutomationDefinition, input: &Value) -> String {
    let mut normalized = definition.clone();
    normalized.name = normalized.name.trim().into();
    normalized.description = normalized.description.trim().into();
    normalized.slug = normalized.slug.trim().to_ascii_lowercase();
    normalized.project_id = normalized
        .project_id
        .as_deref()
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .map(str::to_string);
    normalized.tag_ids.retain(|id| !id.trim().is_empty());
    let mut value = serde_json::to_value(normalized).expect("automation serializes");
    let fields = value.as_object_mut().expect("automation is an object");
    // Compare authoring intent after defaults, independent of generated identity
    // and later lifecycle edits. The original fingerprint survives those edits.
    for field in [
        "revision",
        "approvedRevision",
        "createdBy",
        "modifiedBy",
        "createdAt",
        "updatedAt",
        "creationRequestKey",
        "creationRequestFingerprint",
        "scheduleCursorAt",
        "stateBeforeTrash",
        "circuitOpened",
        "circuitOpenedAt",
    ] {
        fields.remove(field);
    }
    for field in ["id", "slug"] {
        if input.get(field).is_none() {
            fields.remove(field);
        }
    }
    Sha256::digest(serde_json::to_vec(&value).expect("automation serializes"))
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}
