use std::collections::BTreeMap;
use super::TextActionSetting;

pub(super) fn validation_error(id: &str, name: &str, prompt: &str, existing: &[TextActionSetting], editing_id: Option<&str>) -> Option<&'static str> {
    if id.trim().is_empty() { return Some("Action ID is required."); }
    if name.trim().is_empty() { return Some("Action name is required."); }
    if prompt.trim().is_empty() { return Some("Action prompt is required."); }
    let other = |action: &&TextActionSetting| editing_id != Some(action.id.as_str());
    if existing.iter().filter(other).any(|action| action.id.trim() == id.trim()) { return Some("Action IDs must be unique."); }
    let name = name.trim().to_lowercase();
    if existing.iter().filter(other).any(|action| action.name.trim().to_lowercase() == name) { return Some("Action names must be unique."); }
    None
}

pub(super) fn reasoning_after_edit(mut existing: BTreeMap<String, String>, model: &str, reasoning: &str) -> BTreeMap<String, String> {
    if !model.is_empty() {
        if reasoning.is_empty() { existing.remove(model); }
        else { existing.insert(model.to_owned(), reasoning.to_owned()); }
    }
    existing
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_action_reasoning_edit_preserves_other_models() {
        let original = BTreeMap::from([("one".into(), "high".into()), ("two".into(), "low".into())]);
        let edited = reasoning_after_edit(original.clone(), "one", "medium");
        assert_eq!(edited["one"], "medium");
        assert_eq!(edited["two"], "low");
        assert_eq!(reasoning_after_edit(original.clone(), "", ""), original);
        assert_eq!(reasoning_after_edit(original, "one", ""), BTreeMap::from([("two".into(), "low".into())]));
    }

    #[test]
    fn text_action_validation_matches_required_fields_and_unicode_names() {
        let action = TextActionSetting { id: "one".into(), name: "Árbol".into(), prompt: "Do something".into(), ..Default::default() };
        assert_eq!(validation_error("", "name", "prompt", &[], None), Some("Action ID is required."));
        assert_eq!(validation_error("new", "", "", &[], None), Some("Action name is required."));
        assert_eq!(validation_error("new", "name", "", &[], None), Some("Action prompt is required."));
        assert_eq!(validation_error("new", " árbol ", "prompt", &[action.clone()], None), Some("Action names must be unique."));
        assert_eq!(validation_error("one", "other", "prompt", &[action.clone()], None), Some("Action IDs must be unique."));
        assert_eq!(validation_error("one", "Árbol", "prompt", &[action], Some("one")), None);
    }
}
