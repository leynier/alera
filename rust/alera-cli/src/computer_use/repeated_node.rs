//! Collapsing a node that says nothing its parent did not.

use crate::computer_use::snapshot_contract::RawNode;

/// Identity of the nearest node that was actually emitted, used to spot a child
/// that says the same thing as its parent.
pub struct EmittedNode {
    pub role: String,
    pub name: String,
}

/// Whether this node is indistinguishable from the parent that was emitted.
///
/// Some applications nest an element inside another with the same role and name,
/// sometimes for many levels: an Electron app on macOS reported an `AXApplication`
/// inside its own `AXApplication` all the way down, which filled the tree with
/// identical lines until the depth budget stopped it. Only the outermost one is
/// worth a line, and its children belong to it.
pub fn repeats_parent(node: &RawNode, parent: Option<&EmittedNode>) -> bool {
    let Some(parent) = parent else {
        return false;
    };
    if node.children.is_empty() {
        // A leaf that echoes its parent still tells the agent where the content
        // ends, and eliding it would leave the parent looking empty.
        return false;
    }
    node.role.to_lowercase() == parent.role
        && node.name.trim() == parent.name
        && node.value.is_none()
        && node.actions.is_empty()
        && !node.focused
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parent(role: &str, name: &str) -> EmittedNode {
        EmittedNode {
            role: role.to_string(),
            name: name.to_string(),
        }
    }

    fn container(role: &str, name: &str) -> RawNode {
        RawNode::named(role, name).with_children(vec![RawNode::named("push button", "Send")])
    }

    /// The case this exists for, seen on a real macOS desktop.
    #[test]
    fn a_child_identical_to_its_parent_is_elided() {
        assert!(repeats_parent(
            &container("application", "ChatGPT"),
            Some(&parent("application", "ChatGPT"))
        ));
    }

    #[test]
    fn a_different_name_or_role_is_kept() {
        assert!(!repeats_parent(
            &container("application", "Other"),
            Some(&parent("application", "ChatGPT"))
        ));
        assert!(!repeats_parent(
            &container("group", "ChatGPT"),
            Some(&parent("application", "ChatGPT"))
        ));
    }

    /// An echoing leaf marks where the content ends; eliding it would leave the
    /// parent looking empty.
    #[test]
    fn a_leaf_is_never_elided() {
        assert!(!repeats_parent(
            &RawNode::named("application", "ChatGPT"),
            Some(&parent("application", "ChatGPT"))
        ));
    }

    /// A repeat that carries something of its own is a real control.
    #[test]
    fn a_repeat_with_its_own_value_or_actions_is_kept() {
        let mut valued = container("application", "ChatGPT");
        valued.value = Some("x".to_string());
        assert!(!repeats_parent(
            &valued,
            Some(&parent("application", "ChatGPT"))
        ));

        let mut actionable = container("application", "ChatGPT");
        actionable.actions = vec!["AXPress".to_string()];
        assert!(!repeats_parent(
            &actionable,
            Some(&parent("application", "ChatGPT"))
        ));

        let mut focused = container("application", "ChatGPT");
        focused.focused = true;
        assert!(!repeats_parent(
            &focused,
            Some(&parent("application", "ChatGPT"))
        ));
    }

    #[test]
    fn the_root_has_no_parent_to_repeat() {
        assert!(!repeats_parent(&container("application", "ChatGPT"), None));
    }

    /// Roles and names are compared case- and whitespace-insensitively, because
    /// providers are not consistent about either.
    #[test]
    fn comparison_ignores_case_and_padding() {
        let mut node = container("Application", "  ChatGPT  ");
        node.role = "APPLICATION".to_string();
        assert!(repeats_parent(
            &node,
            Some(&parent("application", "ChatGPT"))
        ));
    }
}
