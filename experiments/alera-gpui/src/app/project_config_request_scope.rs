#[derive(Clone)]
pub(super) struct ProjectConfigRequestScope {
    project_id: String,
    selection_epoch: u64,
    draft: String,
}

impl ProjectConfigRequestScope {
    pub(super) fn new(project_id: String, selection_epoch: u64, draft: String) -> Self {
        Self {
            project_id,
            selection_epoch,
            draft,
        }
    }

    pub(super) fn is_selected(&self, project_id: Option<&str>, selection_epoch: u64) -> bool {
        project_id == Some(self.project_id.as_str()) && self.selection_epoch == selection_epoch
    }

    pub(super) fn draft_is_unchanged(&self, current: &str) -> bool {
        self.draft == current
    }

    pub(super) fn may_replace_draft(&self, current: &str, last_seed: Option<&str>) -> bool {
        self.draft_is_unchanged(current) && last_seed.is_none_or(|seed| seed == current)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delayed_save_does_not_target_another_project_or_a_reopened_selection() {
        let request = ProjectConfigRequestScope::new("a".into(), 1, "saved a".into());
        assert!(!request.is_selected(Some("b"), 2));
        assert!(!request.is_selected(Some("a"), 3));
        assert!(!request.is_selected(None, 2));
        assert!(request.is_selected(Some("a"), 1));
    }

    #[test]
    fn read_completion_preserves_edits_before_and_during_the_request() {
        let request = ProjectConfigRequestScope::new("a".into(), 1, "draft".into());
        assert!(!request.may_replace_draft("new typing", Some("draft")));
        assert!(!request.may_replace_draft("draft", Some("persisted")));
        assert!(request.may_replace_draft("draft", Some("draft")));
        assert!(request.may_replace_draft("draft", None));
        assert!(!request.draft_is_unchanged("typed during save"));
    }
}
