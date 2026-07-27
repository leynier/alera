use crate::computer_use::snapshot_contract::ElementRecord;
use crate::computer_use::tree_render::RenderedLine;

/// Roles a browser uses for the entries of its tab strip.
const TAB_ROLES: &[&str] = &["page tab", "tab"];

/// How many sibling tabs it takes before the strip is worth collapsing. Below
/// this a browser window is readable as it is, and collapsing would only hide
/// tabs the agent might legitimately be asked to switch between.
const TAB_COMPACTION_THRESHOLD: usize = 10;

/// Collapse long browser tab strips, keeping the selected tabs.
///
/// A window with eighty tabs spends most of the agent's tree budget on tabs it
/// was not asked about, pushing the page content past the node limit. The
/// dropped elements keep their numbers, so the surviving indexes have gaps:
/// that is why an index may never be inferred from the element count.
pub fn compact_browser_tabs(lines: &mut Vec<RenderedLine>, elements: &mut Vec<ElementRecord>) {
    let groups = tab_groups(lines);
    if groups.is_empty() {
        return;
    }
    let mut dropped_indexes = Vec::new();
    // Rebuilt back to front so each splice leaves the earlier positions valid.
    for group in groups.into_iter().rev() {
        let mut kept = Vec::new();
        let mut dropped = 0usize;
        for position in group.positions.iter() {
            let line = &lines[*position];
            if line.selected {
                kept.push(lines[*position].clone());
            } else {
                dropped_indexes.push(line.index);
                dropped += 1;
            }
        }
        if dropped == 0 {
            continue;
        }
        kept.push(RenderedLine::marker(
            group.depth,
            format!("... {dropped} inactive browser tabs omitted"),
        ));
        let start = group.positions[0];
        let end = group.positions[group.positions.len() - 1] + 1;
        lines.splice(start..end, kept);
    }
    if !dropped_indexes.is_empty() {
        elements.retain(|element| !dropped_indexes.contains(&element.index));
    }
}

struct TabGroup {
    depth: usize,
    /// Positions in the line list, in order and contiguous.
    positions: Vec<usize>,
}

/// Find runs of adjacent tab lines that sit at the same depth.
///
/// Depth and adjacency together stand in for "same parent": the renderer has
/// already flattened the tree into lines, and a run of tabs at one depth is a
/// strip.
fn tab_groups(lines: &[RenderedLine]) -> Vec<TabGroup> {
    let mut groups: Vec<TabGroup> = Vec::new();
    let mut current: Option<TabGroup> = None;
    for (position, line) in lines.iter().enumerate() {
        let is_tab = TAB_ROLES.contains(&line.role.to_lowercase().as_str());
        match (&mut current, is_tab) {
            (Some(group), true) if group.depth == line.depth => group.positions.push(position),
            (_, true) => {
                if let Some(group) = current.take() {
                    push_if_long_enough(&mut groups, group);
                }
                current = Some(TabGroup {
                    depth: line.depth,
                    positions: vec![position],
                });
            }
            (Some(_), false) => {
                if let Some(group) = current.take() {
                    push_if_long_enough(&mut groups, group);
                }
            }
            (None, false) => {}
        }
    }
    if let Some(group) = current.take() {
        push_if_long_enough(&mut groups, group);
    }
    groups
}

fn push_if_long_enough(groups: &mut Vec<TabGroup>, group: TabGroup) {
    if group.positions.len() >= TAB_COMPACTION_THRESHOLD {
        groups.push(group);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tab(index: usize, selected: bool) -> RenderedLine {
        RenderedLine {
            depth: 2,
            index,
            role: "page tab".to_string(),
            selected,
            text: format!("{index} page tab Tab {index}"),
            is_marker: false,
        }
    }

    fn other(index: usize, role: &str) -> RenderedLine {
        RenderedLine {
            depth: 2,
            index,
            role: role.to_string(),
            selected: false,
            text: format!("{index} {role}"),
            is_marker: false,
        }
    }

    fn element(index: usize) -> ElementRecord {
        ElementRecord {
            index,
            role: "page tab".to_string(),
            name: format!("Tab {index}"),
            value: None,
            actions: Vec::new(),
            frame: None,
            path: vec![index],
            signature: "sig".to_string(),
            redacted: false,
        }
    }

    #[test]
    fn a_short_tab_strip_is_left_alone() {
        let mut lines: Vec<RenderedLine> = (0..9).map(|i| tab(i, i == 0)).collect();
        let mut elements: Vec<ElementRecord> = (0..9).map(element).collect();
        compact_browser_tabs(&mut lines, &mut elements);
        assert_eq!(lines.len(), 9);
        assert_eq!(elements.len(), 9);
    }

    #[test]
    fn a_long_tab_strip_keeps_only_the_selected_tab_and_a_marker() {
        let mut lines: Vec<RenderedLine> = (0..30).map(|i| tab(i, i == 7)).collect();
        let mut elements: Vec<ElementRecord> = (0..30).map(element).collect();
        compact_browser_tabs(&mut lines, &mut elements);
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0].index, 7);
        assert!(lines[1].is_marker);
        assert!(lines[1].text.contains("29 inactive browser tabs omitted"));
        assert_eq!(elements.len(), 1);
        assert_eq!(elements[0].index, 7);
    }

    /// The whole point of the surviving indexes: they are the numbers the agent
    /// must use, and they no longer run consecutively.
    #[test]
    fn surviving_indexes_keep_their_original_numbers() {
        let mut lines: Vec<RenderedLine> = (5..25).map(|i| tab(i, i == 20)).collect();
        let mut elements: Vec<ElementRecord> = (5..25).map(element).collect();
        compact_browser_tabs(&mut lines, &mut elements);
        assert_eq!(elements.len(), 1);
        assert_eq!(elements[0].index, 20);
    }

    #[test]
    fn several_selected_tabs_all_survive() {
        let mut lines: Vec<RenderedLine> = (0..20).map(|i| tab(i, i == 3 || i == 11)).collect();
        let mut elements: Vec<ElementRecord> = (0..20).map(element).collect();
        compact_browser_tabs(&mut lines, &mut elements);
        assert_eq!(elements.len(), 2);
        assert_eq!(lines[0].index, 3);
        assert_eq!(lines[1].index, 11);
        assert!(lines[2].text.contains("18 inactive"));
    }

    #[test]
    fn content_around_the_strip_is_untouched() {
        let mut lines = vec![other(0, "tool bar")];
        lines.extend((1..21).map(|i| tab(i, i == 1)));
        lines.push(other(21, "document web"));
        let mut elements: Vec<ElementRecord> = (0..22).map(element).collect();
        compact_browser_tabs(&mut lines, &mut elements);
        assert_eq!(lines[0].role, "tool bar");
        assert_eq!(lines[1].index, 1);
        assert!(lines[2].is_marker);
        assert_eq!(lines[3].role, "document web");
        assert!(elements.iter().any(|e| e.index == 0));
        assert!(elements.iter().any(|e| e.index == 21));
    }

    /// Tabs at different depths belong to different strips, and a run of nine
    /// is below the threshold on its own.
    #[test]
    fn tabs_at_different_depths_are_separate_strips() {
        let mut lines: Vec<RenderedLine> = (0..9).map(|i| tab(i, i == 0)).collect();
        for i in 9..18 {
            let mut line = tab(i, i == 9);
            line.depth = 4;
            lines.push(line);
        }
        let mut elements: Vec<ElementRecord> = (0..18).map(element).collect();
        compact_browser_tabs(&mut lines, &mut elements);
        assert_eq!(lines.len(), 18);
        assert_eq!(elements.len(), 18);
    }

    #[test]
    fn a_strip_with_every_tab_selected_is_left_alone() {
        let mut lines: Vec<RenderedLine> = (0..15).map(|i| tab(i, true)).collect();
        let mut elements: Vec<ElementRecord> = (0..15).map(element).collect();
        compact_browser_tabs(&mut lines, &mut elements);
        assert_eq!(lines.len(), 15);
        assert_eq!(elements.len(), 15);
    }
}
