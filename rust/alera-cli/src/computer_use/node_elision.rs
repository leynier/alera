use crate::computer_use::snapshot_contract::RawNode;

/// Roles that exist only to hold other nodes. When one carries no name, no
/// value and no actions, it is scaffolding: emitting it costs the agent a line
/// and a level of indentation and tells it nothing.
const CONTAINER_ROLES: &[&str] = &[
    "panel",
    "filler",
    "section",
    "unknown",
    "group",
    "generic",
    "pane",
    "layered pane",
    "root pane",
    "scroll pane",
    "viewport",
    "redundant object",
    "application",
    "document frame",
    "document web",
];

/// Roles whose children are their own rendering. A button's label is not a
/// separate control, and listing it invites the agent to click the label.
const COMPACT_ROLES: &[&str] = &[
    "push button",
    "button",
    "toggle button",
    "check box",
    "radio button",
    "menu item",
    "check menu item",
    "radio menu item",
    "label",
    "static text",
    "static",
    "text",
    "heading",
    "link",
    "page tab",
    "tab",
    "image",
    "icon",
    "slider",
    "progress bar",
    "spin button",
];

/// Whether this node should be skipped, with its children taking its place.
pub fn is_elidable_container(node: &RawNode) -> bool {
    if !CONTAINER_ROLES.contains(&node.role.to_lowercase().as_str()) {
        return false;
    }
    if node.focused {
        // The focused element is always worth reporting: the agent uses it to
        // decide whether keyboard input will land where it intends.
        return false;
    }
    node.name.trim().is_empty()
        && node.value.is_none()
        && node.actions.is_empty()
        && !node.children.is_empty()
}

/// Whether this node's children should be left out.
pub fn suppresses_children(node: &RawNode) -> bool {
    COMPACT_ROLES.contains(&node.role.to_lowercase().as_str())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn container(role: &str) -> RawNode {
        RawNode::new(role).with_children(vec![RawNode::named("push button", "Play")])
    }

    #[test]
    fn an_empty_container_is_elided() {
        for role in ["panel", "filler", "PANEL", "scroll pane", "viewport"] {
            assert!(is_elidable_container(&container(role)), "{role}");
        }
    }

    #[test]
    fn a_named_container_is_kept() {
        let mut named = container("panel");
        named.name = "Playback Controls".to_string();
        assert!(!is_elidable_container(&named));
    }

    #[test]
    fn a_container_with_actions_is_kept() {
        let mut actionable = container("panel");
        actionable.actions = vec!["click".to_string()];
        assert!(!is_elidable_container(&actionable));
    }

    /// The agent reads the focused node to decide whether typing will land
    /// where it means, so it must survive elision.
    #[test]
    fn a_focused_container_is_kept() {
        let mut focused = container("panel");
        focused.focused = true;
        assert!(!is_elidable_container(&focused));
    }

    /// Eliding a leaf would drop it from the tree entirely rather than lift its
    /// children up, because it has none.
    #[test]
    fn an_empty_container_with_no_children_is_kept() {
        assert!(!is_elidable_container(&RawNode::new("panel")));
    }

    #[test]
    fn a_meaningful_role_is_never_elided() {
        for role in ["push button", "entry", "list", "table", "window"] {
            assert!(!is_elidable_container(&container(role)), "{role}");
        }
    }

    #[test]
    fn compact_controls_hide_their_children() {
        for role in ["push button", "check box", "label", "link", "PAGE TAB"] {
            assert!(suppresses_children(&RawNode::new(role)), "{role}");
        }
    }

    #[test]
    fn structural_roles_keep_their_children() {
        for role in ["list", "table", "tree", "entry", "menu", "window", "panel"] {
            assert!(!suppresses_children(&RawNode::new(role)), "{role}");
        }
    }
}
