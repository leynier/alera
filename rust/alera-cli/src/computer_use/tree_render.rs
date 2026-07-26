use crate::computer_use::browser_tab_compaction::compact_browser_tabs;
use crate::computer_use::element_signature::signature_of;
use crate::computer_use::node_elision::{is_elidable_container, suppresses_children};
use crate::computer_use::secure_nodes::{is_secure_node, redacted_name, redacted_value};
use crate::computer_use::snapshot_contract::{ElementRecord, RawNode, Rect, Truncation};

/// Ceiling on how much of a window's tree is reported.
///
/// These are context limits, not memory limits: a file manager showing ten
/// thousand rows would bury the controls the agent is looking for, so the tree
/// is cut and the cut is declared.
#[derive(Debug, Clone, Copy)]
pub struct RenderBudget {
    pub max_nodes: usize,
    pub max_depth: usize,
    /// Longest name or value reported for one node.
    pub text_limit: usize,
}

pub const DEFAULT_BUDGET: RenderBudget = RenderBudget {
    max_nodes: 1200,
    max_depth: 64,
    text_limit: 500,
};

/// One line of the rendered tree.
#[derive(Debug, Clone)]
pub struct RenderedLine {
    pub depth: usize,
    pub index: usize,
    pub role: String,
    pub selected: bool,
    pub text: String,
    /// A note to the agent rather than an addressable element, such as the
    /// omitted-tabs marker.
    pub is_marker: bool,
}

impl RenderedLine {
    pub fn marker(depth: usize, text: String) -> Self {
        RenderedLine {
            depth,
            // Markers are never addressed, and a real element owns every index
            // that was handed out.
            index: usize::MAX,
            role: String::new(),
            selected: false,
            text,
            is_marker: true,
        }
    }
}

pub struct RenderedTree {
    pub tree_text: String,
    pub elements: Vec<ElementRecord>,
    pub truncation: Truncation,
    pub focused_element_index: Option<usize>,
}

/// Render one window's accessibility tree into the text an agent reads.
pub fn render_window_tree(
    window: &RawNode,
    window_bounds: Option<Rect>,
    budget: RenderBudget,
) -> RenderedTree {
    let mut walker = Walker {
        budget,
        window_bounds,
        lines: Vec::new(),
        elements: Vec::new(),
        next_index: 0,
        truncated: false,
        max_depth_reached: false,
        focused_element_index: None,
    };
    walker.visit(window, 0, &mut Vec::new());
    let Walker {
        mut lines,
        mut elements,
        truncated,
        max_depth_reached,
        focused_element_index,
        ..
    } = walker;
    compact_browser_tabs(&mut lines, &mut elements);
    let focused_element_index = focused_element_index
        .filter(|index| elements.iter().any(|element| element.index == *index));
    let tree_text = lines
        .iter()
        .map(|line| format!("{}{}", "\t".repeat(line.depth), line.text))
        .collect::<Vec<_>>()
        .join("\n");
    RenderedTree {
        tree_text,
        elements,
        truncation: Truncation {
            truncated,
            max_nodes: budget.max_nodes,
            max_depth: budget.max_depth,
            max_depth_reached,
        },
        focused_element_index,
    }
}

struct Walker {
    budget: RenderBudget,
    window_bounds: Option<Rect>,
    lines: Vec<RenderedLine>,
    elements: Vec<ElementRecord>,
    next_index: usize,
    truncated: bool,
    max_depth_reached: bool,
    focused_element_index: Option<usize>,
}

impl Walker {
    fn visit(&mut self, node: &RawNode, depth: usize, path: &mut Vec<usize>) {
        if self.next_index >= self.budget.max_nodes {
            self.truncated = true;
            return;
        }
        if depth > self.budget.max_depth {
            self.max_depth_reached = true;
            return;
        }
        // An elided container hands its depth to its children, so the agent
        // does not pay a level of indentation for scaffolding.
        if is_elidable_container(node) {
            self.visit_children(node, depth, path);
            return;
        }
        let index = self.next_index;
        self.next_index += 1;
        let secure = is_secure_node(node);
        let name = self.clamp(&redacted_name(node, secure));
        let value = redacted_value(node, secure).map(|value| self.clamp(&value));
        self.lines.push(RenderedLine {
            depth,
            index,
            role: node.role.clone(),
            selected: node.selected,
            text: render_line_text(node, index, &name, value.as_deref(), secure),
            is_marker: false,
        });
        if node.focused {
            self.focused_element_index = Some(index);
        }
        self.elements.push(ElementRecord {
            index,
            role: node.role.clone(),
            name,
            value,
            actions: node.actions.clone(),
            frame: self.window_local_frame(node),
            path: path.clone(),
            signature: signature_of(node),
            redacted: secure,
        });
        if suppresses_children(node) {
            return;
        }
        self.visit_children(node, depth + 1, path);
    }

    fn visit_children(&mut self, node: &RawNode, depth: usize, path: &mut Vec<usize>) {
        for (child_index, child) in node.children.iter().enumerate() {
            path.push(child_index);
            self.visit(child, depth, path);
            path.pop();
        }
    }

    /// Frames arrive from providers already window-local, except that a provider
    /// with screen geometry passes the window rectangle so the conversion
    /// happens in one place.
    fn window_local_frame(&self, node: &RawNode) -> Option<Rect> {
        let frame = node.frame?;
        if frame.is_empty() {
            return None;
        }
        Some(match self.window_bounds {
            Some(bounds) => frame.to_window_local(&bounds),
            None => frame,
        })
    }

    fn clamp(&self, text: &str) -> String {
        clamp_text(text, self.budget.text_limit)
    }
}

/// Cut long text at a character boundary, marking that it was cut.
fn clamp_text(text: &str, limit: usize) -> String {
    if text.chars().count() <= limit {
        return text.to_string();
    }
    let kept: String = text.chars().take(limit).collect();
    format!("{kept}…")
}

fn render_line_text(
    node: &RawNode,
    index: usize,
    name: &str,
    value: Option<&str>,
    secure: bool,
) -> String {
    let mut text = format!("{index} {}", node.role);
    if !name.trim().is_empty() {
        text.push(' ');
        text.push_str(name.trim());
    }
    if let Some(value) = value {
        if !value.trim().is_empty() {
            text.push_str(", Value: ");
            text.push_str(value.trim());
        }
    }
    if secure {
        // Said plainly so the agent does not read the missing value as an empty
        // field and try to fill it in.
        text.push_str(", concealed");
    }
    if node.focused {
        text.push_str(", focused");
    }
    if node.selected {
        text.push_str(", selected");
    }
    if !node.actions.is_empty() {
        text.push_str(", Actions: ");
        text.push_str(&node.actions.join(", "));
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    fn button(name: &str) -> RawNode {
        let mut node = RawNode::named("push button", name);
        node.actions = vec!["click".to_string()];
        node
    }

    fn window(children: Vec<RawNode>) -> RawNode {
        RawNode::named("frame", "Alera").with_children(children)
    }

    fn render(root: &RawNode) -> RenderedTree {
        render_window_tree(root, None, DEFAULT_BUDGET)
    }

    #[test]
    fn the_window_is_the_first_element() {
        let tree = render(&window(vec![button("Play")]));
        assert!(tree.tree_text.starts_with("0 frame Alera"));
        assert_eq!(tree.elements[0].index, 0);
        assert_eq!(tree.elements[0].path, Vec::<usize>::new());
    }

    #[test]
    fn children_are_indented_and_numbered_in_order() {
        let tree = render(&window(vec![button("Play"), button("Pause")]));
        let lines: Vec<&str> = tree.tree_text.lines().collect();
        assert_eq!(lines[1], "\t1 push button Play, Actions: click");
        assert_eq!(lines[2], "\t2 push button Pause, Actions: click");
        assert_eq!(tree.elements[1].path, vec![0]);
        assert_eq!(tree.elements[2].path, vec![1]);
    }

    /// Scaffolding must not cost the agent a line or a level of indentation, but
    /// the path still has to walk through it to find the element again.
    #[test]
    fn elided_containers_lift_their_children_without_losing_the_path() {
        let tree = render(&window(vec![RawNode::new("panel").with_children(vec![
            RawNode::new("filler").with_children(vec![button("Play")]),
        ])]));
        let lines: Vec<&str> = tree.tree_text.lines().collect();
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[1], "\t1 push button Play, Actions: click");
        assert_eq!(tree.elements[1].path, vec![0, 0, 0]);
    }

    #[test]
    fn compact_controls_hide_their_children() {
        let mut labelled = button("Play");
        labelled.children = vec![RawNode::named("static text", "Play")];
        let tree = render(&window(vec![labelled]));
        assert_eq!(tree.tree_text.lines().count(), 2);
    }

    #[test]
    fn a_value_and_the_focus_marker_are_reported() {
        let mut entry = RawNode::named("entry", "Search");
        entry.value = Some("alera".to_string());
        entry.focused = true;
        let tree = render(&window(vec![entry]));
        assert!(tree
            .tree_text
            .contains("1 entry Search, Value: alera, focused"));
        assert_eq!(tree.focused_element_index, Some(1));
    }

    /// A concealed field must say so, or the agent reads the absent value as an
    /// empty box and tries to type into it.
    #[test]
    fn a_password_field_is_concealed_and_says_so() {
        let mut password = RawNode::named("entry", "Password");
        password.value = Some("hunter2".to_string());
        let tree = render(&window(vec![password]));
        assert!(tree.tree_text.contains("[redacted]"));
        assert!(tree.tree_text.contains("concealed"));
        assert!(!tree.tree_text.contains("hunter2"));
        assert!(!tree.tree_text.contains("Password"));
        assert!(tree.elements[1].redacted);
        assert_eq!(tree.elements[1].value, None);
    }

    #[test]
    fn the_node_budget_stops_the_walk_and_declares_it() {
        let many: Vec<RawNode> = (0..50).map(|i| button(&format!("Button {i}"))).collect();
        let budget = RenderBudget {
            max_nodes: 10,
            ..DEFAULT_BUDGET
        };
        let tree = render_window_tree(&window(many), None, budget);
        assert!(tree.truncation.truncated);
        assert_eq!(tree.elements.len(), 10);
    }

    #[test]
    fn the_depth_budget_stops_descending_and_declares_it() {
        let mut deep = button("Deep");
        for _ in 0..10 {
            deep = RawNode::named("list", "Level").with_children(vec![deep]);
        }
        let budget = RenderBudget {
            max_depth: 3,
            ..DEFAULT_BUDGET
        };
        let tree = render_window_tree(&window(vec![deep]), None, budget);
        assert!(tree.truncation.max_depth_reached);
        assert!(!tree.tree_text.contains("Deep"));
    }

    #[test]
    fn an_untruncated_tree_says_so() {
        let tree = render(&window(vec![button("Play")]));
        assert!(!tree.truncation.truncated);
        assert!(!tree.truncation.max_depth_reached);
        assert_eq!(tree.truncation.max_nodes, DEFAULT_BUDGET.max_nodes);
    }

    #[test]
    fn long_text_is_cut_at_the_budget() {
        let mut entry = RawNode::named("entry", "x".repeat(40));
        entry.value = Some("y".repeat(40));
        let budget = RenderBudget {
            text_limit: 10,
            ..DEFAULT_BUDGET
        };
        let tree = render_window_tree(&window(vec![entry]), None, budget);
        assert!(tree.tree_text.contains(&format!("{}…", "x".repeat(10))));
        assert!(tree.tree_text.contains(&format!("{}…", "y".repeat(10))));
    }

    /// Cutting by bytes would split a multi-byte character and panic.
    #[test]
    fn cutting_respects_character_boundaries() {
        assert_eq!(clamp_text("áéíóú", 3), "áéí…");
        assert_eq!(clamp_text("abc", 3), "abc");
        assert_eq!(clamp_text("", 3), "");
    }

    #[test]
    fn frames_are_converted_to_window_local_coordinates_once() {
        let mut node = button("Play");
        node.frame = Some(Rect::new(150.0, 260.0, 40.0, 20.0));
        let bounds = Rect::new(100.0, 200.0, 800.0, 600.0);
        let tree = render_window_tree(&window(vec![node]), Some(bounds), DEFAULT_BUDGET);
        assert_eq!(
            tree.elements[1].frame,
            Some(Rect::new(50.0, 60.0, 40.0, 20.0))
        );
    }

    #[test]
    fn a_degenerate_frame_is_reported_as_no_frame() {
        let mut node = button("Play");
        node.frame = Some(Rect::new(0.0, 0.0, 0.0, 0.0));
        let tree = render(&window(vec![node]));
        assert_eq!(tree.elements[1].frame, None);
    }

    /// The focused element can be one of the tabs compaction drops, and a stale
    /// pointer into a removed element would be worse than none.
    #[test]
    fn a_focus_marker_on_a_dropped_element_is_cleared() {
        let mut tabs: Vec<RawNode> = (0..20)
            .map(|i| RawNode::named("page tab", format!("Tab {i}")))
            .collect();
        tabs[5].focused = true;
        let tree = render(&window(tabs));
        assert_eq!(tree.focused_element_index, None);
    }

    #[test]
    fn a_focus_marker_on_a_surviving_element_is_kept() {
        let mut tabs: Vec<RawNode> = (0..20)
            .map(|i| RawNode::named("page tab", format!("Tab {i}")))
            .collect();
        tabs[5].focused = true;
        tabs[5].selected = true;
        let tree = render(&window(tabs));
        assert_eq!(tree.focused_element_index, Some(6));
    }
}
