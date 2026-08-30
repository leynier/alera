pub(super) fn resolve_selection(
    preferred: Option<String>,
    exists: impl Fn(&str) -> bool,
) -> Option<String> {
    // Flutter keeps an absent selection absent. Startup must not activate a
    // pinned/main workspace just because it happens to arrive first.
    preferred.filter(|id| exists(id))
}

#[cfg(test)]
mod tests {
    use super::resolve_selection;

    #[test]
    fn workspace_selection_does_not_invent_a_startup_or_removed_target() {
        assert_eq!(resolve_selection(None, |_| true), None);
        assert_eq!(resolve_selection(Some("removed".into()), |_| false), None);
        assert_eq!(resolve_selection(Some("chosen".into()), |id| id == "chosen"), Some("chosen".into()));
    }
}
