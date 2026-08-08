use serde_json::{json, Value};

use crate::model::{
    WorkbenchDropZone, WorkbenchLayout, WorkbenchLayoutNode, WorkbenchPaneGroup,
    WorkbenchSplitAxis, WorkbenchSplitDirection,
};

impl WorkbenchLayout {
    pub fn reconcile_tabs(&mut self, tab_ids: &[String]) {
        let valid = tab_ids.iter().collect::<std::collections::BTreeSet<_>>();
        for group in self.groups.values_mut() {
            group.tab_ids.retain(|tab_id| valid.contains(tab_id));
            if group
                .active_tab_id
                .as_ref()
                .is_some_and(|tab_id| !group.tab_ids.contains(tab_id))
            {
                group.active_tab_id = group.tab_ids.first().cloned();
            }
        }
        let empty_group_ids = self
            .groups
            .iter()
            .filter(|(_, group)| group.tab_ids.is_empty())
            .map(|(group_id, _)| group_id.clone())
            .collect::<Vec<_>>();
        if empty_group_ids.len() < self.groups.len() {
            for group_id in empty_group_ids {
                self.groups.remove(&group_id);
                if let Some(root) = remove_layout_leaf(self.root.clone(), &group_id) {
                    self.root = root;
                }
            }
            if !self.groups.contains_key(&self.active_group_id) {
                self.active_group_id = first_layout_leaf(&self.root).to_string();
            }
        }
        let assigned = self
            .groups
            .values()
            .flat_map(|group| group.tab_ids.iter())
            .collect::<std::collections::BTreeSet<_>>();
        let unassigned = tab_ids
            .iter()
            .filter(|tab_id| !assigned.contains(tab_id))
            .cloned()
            .collect::<Vec<_>>();
        if unassigned.is_empty() {
            return;
        }
        let target_group_id = if self.groups.contains_key(&self.active_group_id) {
            self.active_group_id.clone()
        } else {
            self.groups.keys().next().cloned().unwrap_or_default()
        };
        if let Some(group) = self.groups.get_mut(&target_group_id) {
            group.tab_ids.extend(unassigned);
            if group.active_tab_id.is_none() {
                group.active_tab_id = group.tab_ids.first().cloned();
            }
        }
    }

    pub fn add_tab_to_active_group(&mut self, tab_id: String) {
        let Some(group) = self.groups.get_mut(&self.active_group_id) else {
            return;
        };
        if !group.tab_ids.contains(&tab_id) {
            group.tab_ids.push(tab_id.clone());
        }
        group.active_tab_id = Some(tab_id);
    }

    pub fn remove_tab(&mut self, tab_id: &str) {
        for group in self.groups.values_mut() {
            group.tab_ids.retain(|candidate| candidate != tab_id);
            if group.active_tab_id.as_deref() == Some(tab_id) {
                group.active_tab_id = group.tab_ids.first().cloned();
            }
        }
        let empty_group_ids = self
            .groups
            .iter()
            .filter(|(_, group)| group.tab_ids.is_empty())
            .map(|(group_id, _)| group_id.clone())
            .collect::<Vec<_>>();
        if empty_group_ids.len() == self.groups.len() {
            let group_id = self
                .groups
                .contains_key(&self.active_group_id)
                .then(|| self.active_group_id.clone())
                .or_else(|| self.groups.keys().next().cloned())
                .unwrap_or_else(|| format!("group-{}", self.workspace_id));
            self.groups.clear();
            self.groups.insert(
                group_id.clone(),
                WorkbenchPaneGroup {
                    id: group_id.clone(),
                    tab_ids: Vec::new(),
                    active_tab_id: None,
                },
            );
            self.root = WorkbenchLayoutNode::Leaf {
                group_id: group_id.clone(),
            };
            self.active_group_id = group_id;
            return;
        }
        for group_id in empty_group_ids {
            self.groups.remove(&group_id);
            if let Some(root) = remove_layout_leaf(self.root.clone(), &group_id) {
                self.root = root;
            }
        }
        if !self.groups.contains_key(&self.active_group_id) {
            self.active_group_id = first_layout_leaf(&self.root).to_string();
        }
    }

    pub fn move_tab_to_group(&mut self, tab_id: &str, target_group_id: &str, index: usize) -> bool {
        let Some(source_group_id) = self
            .groups
            .iter()
            .find(|(_, group)| group.tab_ids.iter().any(|candidate| candidate == tab_id))
            .map(|(group_id, _)| group_id.clone())
        else {
            return false;
        };
        if source_group_id == target_group_id {
            let Some(group) = self.groups.get_mut(target_group_id) else {
                return false;
            };
            let Some(source_index) = group
                .tab_ids
                .iter()
                .position(|candidate| candidate == tab_id)
            else {
                return false;
            };
            let insert_index = index.min(group.tab_ids.len().saturating_sub(1));
            if source_index == insert_index {
                return false;
            }
            group.tab_ids.remove(source_index);
            group.tab_ids.insert(insert_index, tab_id.to_string());
            group.active_tab_id = Some(tab_id.to_string());
            self.active_group_id = target_group_id.to_string();
            return true;
        }
        self.remove_tab(tab_id);
        let resolved_group_id = if self.groups.contains_key(target_group_id) {
            target_group_id.to_string()
        } else {
            self.active_group_id.clone()
        };
        let Some(group) = self.groups.get_mut(&resolved_group_id) else {
            return false;
        };
        group
            .tab_ids
            .insert(index.min(group.tab_ids.len()), tab_id.to_string());
        group.active_tab_id = Some(tab_id.to_string());
        self.active_group_id = resolved_group_id;
        true
    }

    /// Applies the complete Flutter tab-drop mutation.
    ///
    /// Center drops use the tab-strip insertion index. Directional drops first
    /// remove the tab from its source group (which prunes a now-empty split),
    /// then insert a new sibling pane around the target group. The caller is
    /// responsible for rejecting same-group single-tab drops before invoking
    /// this method; keeping the guard here makes persisted/programmatic drops
    /// safe as well.
    pub fn move_tab_to_drop(
        &mut self,
        tab_id: &str,
        target_group_id: &str,
        zone: WorkbenchDropZone,
        new_group_id: &str,
        index: Option<usize>,
    ) -> bool {
        if zone == WorkbenchDropZone::Center {
            return self.move_tab_to_group(tab_id, target_group_id, index.unwrap_or(usize::MAX));
        }

        let Some(source_group_id) = self
            .groups
            .iter()
            .find(|(_, group)| group.tab_ids.iter().any(|candidate| candidate == tab_id))
            .map(|(group_id, _)| group_id.clone())
        else {
            return false;
        };
        let source_tab_count = self
            .groups
            .get(&source_group_id)
            .map(|group| group.tab_ids.len())
            .unwrap_or_default();
        if source_group_id == target_group_id && source_tab_count <= 1 {
            return false;
        }

        self.remove_tab(tab_id);
        let resolved_target_group_id = if self.groups.contains_key(target_group_id) {
            target_group_id.to_string()
        } else {
            self.active_group_id.clone()
        };
        let Some(direction) = zone.split_direction() else {
            return false;
        };
        self.split_group(
            &resolved_target_group_id,
            direction,
            WorkbenchPaneGroup {
                id: new_group_id.to_string(),
                tab_ids: vec![tab_id.to_string()],
                active_tab_id: Some(tab_id.to_string()),
            },
        );
        self.groups.contains_key(new_group_id)
    }

    pub fn activate_tab(&mut self, tab_id: &str) {
        let Some((group_id, group)) = self
            .groups
            .iter_mut()
            .find(|(_, group)| group.tab_ids.iter().any(|candidate| candidate == tab_id))
        else {
            return;
        };
        self.active_group_id = group_id.clone();
        group.active_tab_id = Some(tab_id.to_string());
    }

    pub fn split_group(
        &mut self,
        target_group_id: &str,
        direction: WorkbenchSplitDirection,
        new_group: WorkbenchPaneGroup,
    ) {
        let axis = match direction {
            WorkbenchSplitDirection::Left | WorkbenchSplitDirection::Right => {
                WorkbenchSplitAxis::Horizontal
            }
            WorkbenchSplitDirection::Up | WorkbenchSplitDirection::Down => {
                WorkbenchSplitAxis::Vertical
            }
        };
        let target = WorkbenchLayoutNode::Leaf {
            group_id: target_group_id.to_string(),
        };
        let added = WorkbenchLayoutNode::Leaf {
            group_id: new_group.id.clone(),
        };
        let (first, second) = match direction {
            WorkbenchSplitDirection::Left | WorkbenchSplitDirection::Up => (added, target),
            WorkbenchSplitDirection::Right | WorkbenchSplitDirection::Down => (target, added),
        };
        if replace_layout_leaf(
            &mut self.root,
            target_group_id,
            WorkbenchLayoutNode::Split {
                axis,
                first: Box::new(first),
                second: Box::new(second),
                ratio: 0.5,
            },
        ) {
            self.active_group_id = new_group.id.clone();
            self.groups.insert(new_group.id.clone(), new_group);
        }
    }

    pub fn merge_group_into_sibling(&mut self, group_id: &str) {
        let Some(sibling_id) = sibling_group_id(&self.root, group_id) else {
            return;
        };
        let Some(source) = self.groups.remove(group_id) else {
            return;
        };
        let Some(target) = self.groups.get_mut(&sibling_id) else {
            self.groups.insert(source.id.clone(), source);
            return;
        };
        target.tab_ids.extend(source.tab_ids);
        target.active_tab_id = source
            .active_tab_id
            .or_else(|| target.active_tab_id.clone());
        if let Some(root) = remove_layout_leaf(self.root.clone(), group_id) {
            self.root = root;
            self.active_group_id = sibling_id;
        }
    }

    pub fn update_split_ratio(&mut self, path: &[usize], ratio: f64) {
        update_layout_ratio(&mut self.root, path, ratio.clamp(0.15, 0.85));
    }

    pub fn to_value(&self) -> Value {
        json!({
            "workspaceId": self.workspace_id,
            "activeGroupId": self.active_group_id,
            "groups": self.groups.iter().map(|(key, group)| {
                (
                    key.clone(),
                    json!({
                        "id": group.id,
                        "tabIds": group.tab_ids,
                        "activeTabId": group.active_tab_id,
                    }),
                )
            }).collect::<serde_json::Map<_, _>>(),
            "root": layout_node_to_value(&self.root),
        })
    }
}

fn update_layout_ratio(node: &mut WorkbenchLayoutNode, path: &[usize], ratio: f64) {
    let WorkbenchLayoutNode::Split {
        first,
        second,
        ratio: current,
        ..
    } = node
    else {
        return;
    };
    let Some((&step, remaining)) = path.split_first() else {
        *current = ratio;
        return;
    };
    update_layout_ratio(if step == 0 { first } else { second }, remaining, ratio);
}

fn replace_layout_leaf(
    node: &mut WorkbenchLayoutNode,
    group_id: &str,
    replacement: WorkbenchLayoutNode,
) -> bool {
    match node {
        WorkbenchLayoutNode::Leaf {
            group_id: candidate,
        } if candidate == group_id => {
            *node = replacement;
            true
        }
        WorkbenchLayoutNode::Split { first, second, .. } => {
            replace_layout_leaf(first, group_id, replacement.clone())
                || replace_layout_leaf(second, group_id, replacement)
        }
        _ => false,
    }
}

fn first_layout_leaf(node: &WorkbenchLayoutNode) -> &str {
    match node {
        WorkbenchLayoutNode::Leaf { group_id } => group_id,
        WorkbenchLayoutNode::Split { first, .. } => first_layout_leaf(first),
    }
}

fn sibling_group_id(node: &WorkbenchLayoutNode, group_id: &str) -> Option<String> {
    match node {
        WorkbenchLayoutNode::Leaf { .. } => None,
        WorkbenchLayoutNode::Split { first, second, .. } => match (&**first, &**second) {
            (WorkbenchLayoutNode::Leaf { group_id: first_id }, _) if first_id == group_id => {
                Some(first_layout_leaf(second).to_string())
            }
            (
                _,
                WorkbenchLayoutNode::Leaf {
                    group_id: second_id,
                },
            ) if second_id == group_id => Some(first_layout_leaf(first).to_string()),
            _ => sibling_group_id(first, group_id).or_else(|| sibling_group_id(second, group_id)),
        },
    }
}

fn remove_layout_leaf(node: WorkbenchLayoutNode, group_id: &str) -> Option<WorkbenchLayoutNode> {
    match node {
        WorkbenchLayoutNode::Leaf {
            group_id: candidate,
        } => (candidate != group_id).then_some(WorkbenchLayoutNode::Leaf {
            group_id: candidate,
        }),
        WorkbenchLayoutNode::Split {
            axis,
            first,
            second,
            ratio,
        } => match (
            remove_layout_leaf(*first, group_id),
            remove_layout_leaf(*second, group_id),
        ) {
            (Some(first), Some(second)) => Some(WorkbenchLayoutNode::Split {
                axis,
                first: Box::new(first),
                second: Box::new(second),
                ratio,
            }),
            (Some(node), None) | (None, Some(node)) => Some(node),
            (None, None) => None,
        },
    }
}

fn layout_node_to_value(node: &WorkbenchLayoutNode) -> Value {
    match node {
        WorkbenchLayoutNode::Leaf { group_id } => {
            json!({"type": "leaf", "groupId": group_id})
        }
        WorkbenchLayoutNode::Split {
            axis,
            first,
            second,
            ratio,
        } => json!({
            "type": "split",
            "axis": match axis {
                WorkbenchSplitAxis::Horizontal => "horizontal",
                WorkbenchSplitAxis::Vertical => "vertical",
            },
            "first": layout_node_to_value(first),
            "second": layout_node_to_value(second),
            "ratio": ratio,
        }),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    fn layout() -> WorkbenchLayout {
        WorkbenchLayout {
            workspace_id: "w1".to_string(),
            root: WorkbenchLayoutNode::Leaf {
                group_id: "root".to_string(),
            },
            groups: BTreeMap::from([(
                "root".to_string(),
                WorkbenchPaneGroup {
                    id: "root".to_string(),
                    tab_ids: vec!["t1".to_string()],
                    active_tab_id: Some("t1".to_string()),
                },
            )]),
            active_group_id: "root".to_string(),
        }
    }

    #[test]
    fn split_and_merge_preserve_tabs_and_active_group() {
        let mut layout = layout();
        layout.split_group(
            "root",
            WorkbenchSplitDirection::Right,
            WorkbenchPaneGroup {
                id: "right".to_string(),
                tab_ids: vec!["t2".to_string()],
                active_tab_id: Some("t2".to_string()),
            },
        );
        assert_eq!(layout.active_group_id, "right");
        assert_eq!(layout.groups.len(), 2);
        assert!(matches!(
            layout.root,
            WorkbenchLayoutNode::Split {
                axis: WorkbenchSplitAxis::Horizontal,
                ..
            }
        ));

        layout.merge_group_into_sibling("right");
        assert_eq!(layout.active_group_id, "root");
        assert_eq!(layout.groups["root"].tab_ids, ["t1", "t2"]);
        assert!(matches!(layout.root, WorkbenchLayoutNode::Leaf { .. }));
    }

    #[test]
    fn reconcile_tabs_keeps_every_runtime_tab_in_exactly_one_group() {
        let mut layout = layout();
        layout.groups.get_mut("root").unwrap().tab_ids =
            vec!["stale".to_string(), "t1".to_string()];
        layout.groups.get_mut("root").unwrap().active_tab_id = Some("stale".to_string());

        layout.reconcile_tabs(&["t1".to_string(), "t2".to_string()]);

        assert_eq!(layout.groups["root"].tab_ids, ["t1", "t2"]);
        assert_eq!(layout.groups["root"].active_tab_id.as_deref(), Some("t1"));
    }

    #[test]
    fn moving_tabs_reorders_and_prunes_an_empty_source_group() {
        let mut layout = layout();
        layout.groups.get_mut("root").unwrap().tab_ids =
            vec!["t1".to_string(), "t2".to_string(), "t3".to_string()];
        assert!(layout.move_tab_to_group("t1", "root", 2));
        assert_eq!(layout.groups["root"].tab_ids, ["t2", "t3", "t1"]);

        layout.split_group(
            "root",
            WorkbenchSplitDirection::Right,
            WorkbenchPaneGroup {
                id: "right".to_string(),
                tab_ids: vec!["t4".to_string()],
                active_tab_id: Some("t4".to_string()),
            },
        );
        assert!(layout.move_tab_to_group("t4", "root", 1));
        assert!(!layout.groups.contains_key("right"));
        assert_eq!(layout.groups["root"].tab_ids, ["t2", "t4", "t3", "t1"]);
        assert!(matches!(layout.root, WorkbenchLayoutNode::Leaf { .. }));
    }

    #[test]
    fn directional_tab_drop_creates_a_split_and_prunes_the_source() {
        let mut layout = layout();
        layout.groups.get_mut("root").unwrap().tab_ids = vec!["t1".to_string(), "t2".to_string()];
        assert!(layout.move_tab_to_drop("t2", "root", WorkbenchDropZone::Down, "bottom", None,));
        assert_eq!(layout.groups["root"].tab_ids, ["t1"]);
        assert_eq!(layout.groups["bottom"].tab_ids, ["t2"]);
        assert!(matches!(
            layout.root,
            WorkbenchLayoutNode::Split {
                axis: WorkbenchSplitAxis::Vertical,
                ..
            }
        ));
        assert_eq!(layout.active_group_id, "bottom");
    }

    #[test]
    fn directional_drop_of_a_single_tab_into_itself_is_a_noop() {
        let mut layout = layout();
        assert!(!layout.move_tab_to_drop("t1", "root", WorkbenchDropZone::Right, "unused", None,));
        assert_eq!(layout.groups.len(), 1);
        assert!(matches!(layout.root, WorkbenchLayoutNode::Leaf { .. }));
    }

    #[test]
    fn directional_drop_uses_the_flutter_axis_and_order_for_each_edge() {
        for (zone, axis, new_group_is_first) in [
            (
                WorkbenchDropZone::Left,
                WorkbenchSplitAxis::Horizontal,
                true,
            ),
            (
                WorkbenchDropZone::Right,
                WorkbenchSplitAxis::Horizontal,
                false,
            ),
            (WorkbenchDropZone::Up, WorkbenchSplitAxis::Vertical, true),
            (WorkbenchDropZone::Down, WorkbenchSplitAxis::Vertical, false),
        ] {
            let mut layout = layout();
            layout.groups.get_mut("root").unwrap().tab_ids =
                vec!["t1".to_string(), "t2".to_string()];
            assert!(layout.move_tab_to_drop("t2", "root", zone, "new", None));
            let WorkbenchLayoutNode::Split {
                axis: actual_axis,
                first,
                second,
                ..
            } = layout.root
            else {
                panic!("directional drop did not create a split");
            };
            assert_eq!(actual_axis, axis);
            let first_id = match *first {
                WorkbenchLayoutNode::Leaf { group_id } => group_id,
                _ => panic!("first child is not a leaf"),
            };
            let second_id = match *second {
                WorkbenchLayoutNode::Leaf { group_id } => group_id,
                _ => panic!("second child is not a leaf"),
            };
            assert_eq!(new_group_is_first, first_id == "new");
            assert_eq!(
                if new_group_is_first {
                    second_id
                } else {
                    first_id
                },
                "root"
            );
        }
    }

    #[test]
    fn closing_the_last_tab_keeps_one_empty_group() {
        let mut layout = layout();
        layout.remove_tab("t1");
        assert_eq!(layout.groups.len(), 1);
        assert!(layout.groups["root"].tab_ids.is_empty());
        assert_eq!(layout.active_group_id, "root");
    }

    #[test]
    fn reconciling_tabs_prunes_an_empty_split_group() {
        let mut layout = layout();
        layout.split_group(
            "root",
            WorkbenchSplitDirection::Right,
            WorkbenchPaneGroup {
                id: "right".to_string(),
                tab_ids: vec!["stale".to_string()],
                active_tab_id: Some("stale".to_string()),
            },
        );

        layout.reconcile_tabs(&["t1".to_string()]);

        assert_eq!(layout.groups.len(), 1);
        assert!(layout.groups.contains_key("root"));
        assert!(
            matches!(layout.root, WorkbenchLayoutNode::Leaf { ref group_id } if group_id == "root")
        );
    }
}
