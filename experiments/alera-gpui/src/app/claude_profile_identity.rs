use super::settings_state::ClaudeQuotaProfile;

pub(super) fn profile_index(profiles: &[ClaudeQuotaProfile], name: &str) -> Option<usize> {
    profiles.iter().position(|profile| profile.profile == name)
}

pub(super) fn profile_move_indices(
    profiles: &[ClaudeQuotaProfile],
    name: &str,
    offset: isize,
) -> Option<(usize, usize)> {
    let source = profile_index(profiles, name)?;
    let target = source.checked_add_signed(offset)?;
    (target < profiles.len() && target != source).then_some((source, target))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profiles(names: &[&str]) -> Vec<ClaudeQuotaProfile> {
        names
            .iter()
            .map(|name| ClaudeQuotaProfile {
                profile: (*name).into(),
                ..Default::default()
            })
            .collect()
    }

    #[test]
    fn stale_removed_profile_actions_do_not_target_the_replacement_row() {
        let current = profiles(&["a", "c"]);
        assert_eq!(profile_index(&current, "b"), None);
        assert_eq!(profile_move_indices(&current, "b", -1), None);
        assert_eq!(profile_move_indices(&profiles(&["a"]), "b", -1), None);
    }

    #[test]
    fn profile_actions_resolve_identity_after_reordering() {
        let current = profiles(&["c", "a", "b"]);
        assert_eq!(profile_index(&current, "b"), Some(2));
        assert_eq!(profile_move_indices(&current, "b", -1), Some((2, 1)));
        assert_eq!(profile_move_indices(&current, "c", -1), None);
        assert_eq!(profile_move_indices(&current, "b", 1), None);
        assert_eq!(profile_move_indices(&current, "c", isize::MAX), None);
        assert_eq!(profile_move_indices(&current, "b", isize::MIN), None);
    }
}
