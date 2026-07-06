/// Delay between writing the injected banner and the follow-up Enter.
/// Claude Code treats a large single write as a paste and swallows an
/// inlined `\r`, so the Enter must arrive as a separate write. Tuned for
/// Claude Code; other agents share the constant so cadence tuning stays a
/// one-line change.
pub const DEFERRED_ENTER_DELAY_MS: u64 = 500;

/// Agents whose injected text stays as editable prompt input: no auto-Enter,
/// submit stays under user control.
pub fn skips_auto_enter(agent_type: Option<&str>) -> bool {
    matches!(agent_type, Some("cursor"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursor_skips_auto_enter() {
        assert!(skips_auto_enter(Some("cursor")));
        assert!(!skips_auto_enter(Some("claude")));
        assert!(!skips_auto_enter(None));
    }
}
