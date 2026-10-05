use serde::{Deserialize, Serialize};

/// Tags and section given to each workspace an automation run creates. Runs
/// that reuse an existing workspace leave its tags and section alone.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationWorkspacePlacement {
    #[serde(default, alias = "tag_ids")]
    pub tag_ids: Vec<String>,
    #[serde(default, alias = "section_id")]
    pub section_id: Option<String>,
}

impl AutomationWorkspacePlacement {
    pub fn is_empty(&self) -> bool {
        self.tag_ids.is_empty() && self.section_id.is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::AutomationWorkspacePlacement;

    #[test]
    fn placement_reads_both_spellings_and_defaults_to_empty() {
        let placement: AutomationWorkspacePlacement =
            serde_json::from_value(serde_json::json!({"tag_ids":["a"],"sectionId":"s"})).unwrap();
        assert_eq!(placement.tag_ids, vec!["a".to_string()]);
        assert_eq!(placement.section_id.as_deref(), Some("s"));
        let empty: AutomationWorkspacePlacement =
            serde_json::from_value(serde_json::json!({})).unwrap();
        assert!(empty.is_empty());
    }
}
