use crate::computer_use::snapshot_contract::RawNode;

/// Identity of a node, used to tell whether the path that led to it still leads
/// to the same thing.
///
/// The path alone is not identity: a list that gained a row above the target
/// keeps every path valid while every path now points one row off. Comparing a
/// signature turns that into a refusal instead of a click on the wrong row.
///
/// Deliberately excludes the value, so typing into a field does not invalidate
/// the element the agent is working with.
pub fn signature_of(node: &RawNode) -> String {
    signature_parts(&node.role, &node.name, &node.actions, node.children.len())
}

/// The signature from its parts, so it can be recomputed against a live
/// accessibility object without walking that object's whole subtree.
///
/// Checking identity costs one child count, not a second tree read; an action
/// that had to re-observe everything first would be too slow to gate on.
pub fn signature_parts(role: &str, name: &str, actions: &[String], child_count: usize) -> String {
    let mut actions: Vec<&str> = actions.iter().map(String::as_str).collect();
    // Providers report actions in whatever order the toolkit hands them over,
    // and that order is not stable between observations.
    actions.sort_unstable();
    format!(
        "{}|{}|{}|{child_count}",
        role.to_lowercase(),
        name.trim(),
        actions.join(",")
    )
}

/// Whether a freshly observed node is still the one a cached element described.
pub fn matches_signature(node: &RawNode, expected: &str) -> bool {
    signature_of(node) == expected
}

/// Walk a path of child indexes from a root node.
pub fn node_at_path<'a>(root: &'a RawNode, path: &[usize]) -> Option<&'a RawNode> {
    let mut node = root;
    for index in path {
        node = node.children.get(*index)?;
    }
    Some(node)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn button(name: &str) -> RawNode {
        let mut node = RawNode::named("push button", name);
        node.actions = vec!["click".to_string()];
        node
    }

    #[test]
    fn the_same_node_signs_the_same_way() {
        assert_eq!(signature_of(&button("Play")), signature_of(&button("Play")));
    }

    #[test]
    fn a_different_name_or_role_signs_differently() {
        assert_ne!(
            signature_of(&button("Play")),
            signature_of(&button("Pause"))
        );
        let mut other_role = button("Play");
        other_role.role = "toggle button".to_string();
        assert_ne!(signature_of(&button("Play")), signature_of(&other_role));
    }

    /// Toolkits hand actions over in an unstable order, so a re-observation of
    /// the same node must not read as a different node.
    #[test]
    fn action_order_does_not_change_the_signature() {
        let mut forward = button("Play");
        forward.actions = vec!["click".to_string(), "focus".to_string()];
        let mut reversed = button("Play");
        reversed.actions = vec!["focus".to_string(), "click".to_string()];
        assert_eq!(signature_of(&forward), signature_of(&reversed));
    }

    /// Typing into a field must not invalidate the element being typed into.
    #[test]
    fn the_value_is_not_part_of_the_signature() {
        let mut empty = RawNode::named("entry", "Search");
        let mut filled = RawNode::named("entry", "Search");
        empty.value = Some(String::new());
        filled.value = Some("alera".to_string());
        assert_eq!(signature_of(&empty), signature_of(&filled));
    }

    /// A container that gained or lost children is a re-render, and any index
    /// the agent still holds for it describes the old layout.
    #[test]
    fn a_changed_child_count_changes_the_signature() {
        let one = RawNode::new("list").with_children(vec![button("a")]);
        let two = RawNode::new("list").with_children(vec![button("a"), button("b")]);
        assert_ne!(signature_of(&one), signature_of(&two));
    }

    #[test]
    fn surrounding_whitespace_in_a_name_is_ignored() {
        let mut padded = button("Play");
        padded.name = "  Play  ".to_string();
        assert_eq!(signature_of(&button("Play")), signature_of(&padded));
    }

    #[test]
    fn a_path_walks_to_the_expected_node() {
        let tree = RawNode::new("window").with_children(vec![
            RawNode::new("panel").with_children(vec![button("Play"), button("Pause")])
        ]);
        assert_eq!(node_at_path(&tree, &[0, 1]).unwrap().name, "Pause");
        assert_eq!(node_at_path(&tree, &[]).unwrap().role, "window");
    }

    #[test]
    fn a_path_past_the_end_of_the_tree_resolves_to_nothing() {
        let tree = RawNode::new("window").with_children(vec![button("Play")]);
        assert!(node_at_path(&tree, &[1]).is_none());
        assert!(node_at_path(&tree, &[0, 0]).is_none());
    }

    /// The pair the action path relies on: the path still resolves, but to a
    /// different element, and the signature is what notices.
    #[test]
    fn a_shifted_list_resolves_but_fails_its_signature() {
        let before = RawNode::new("list").with_children(vec![button("Row 1"), button("Row 2")]);
        let expected = signature_of(node_at_path(&before, &[0]).unwrap());

        let after = RawNode::new("list").with_children(vec![
            button("Row 0"),
            button("Row 1"),
            button("Row 2"),
        ]);
        let resolved = node_at_path(&after, &[0]).unwrap();
        assert_eq!(resolved.name, "Row 0");
        assert!(!matches_signature(resolved, &expected));
    }
}
