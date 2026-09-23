//! Main-panel terminal ids for workspace rows. Desktop stores the assignment
//! in shared view prefs; a host without that map falls back to the first
//! primary-candidate tab so a phone can still merge one agent onto the row.

use std::collections::{BTreeMap, HashSet};

use alera_core::runtime::WorkspaceTabRecord;
use serde_json::Value;

pub(super) fn is_primary_terminal_candidate(tab: &WorkspaceTabRecord) -> bool {
    if tab.kind != "terminal" || tab.title == "Setup" {
        return false;
    }
    let Some(payload) = tab.payload.as_object() else {
        return true;
    };
    payload.get("autoCloseOnSuccess") != Some(&Value::Bool(true))
        && payload.get("initialCommandOnce") != Some(&Value::Bool(true))
}

/// Desktop `workspaceMainTabIds` when present and still live; otherwise the
/// earliest primary-candidate tab in each workspace.
pub(super) fn resolve_workspace_main_tab_ids(
    stored: &BTreeMap<String, Vec<String>>,
    tabs: &[WorkspaceTabRecord],
) -> BTreeMap<String, Vec<String>> {
    let mut live_ids = BTreeMap::<String, HashSet<String>>::new();
    for tab in tabs {
        live_ids
            .entry(tab.workspace_id.clone())
            .or_default()
            .insert(tab.id.clone());
    }
    let mut resolved = BTreeMap::new();
    for (workspace_id, live) in &live_ids {
        if let Some(stored_ids) = stored.get(workspace_id) {
            let kept = stored_ids
                .iter()
                .filter(|id| live.contains(*id))
                .cloned()
                .collect::<Vec<_>>();
            if !kept.is_empty() {
                resolved.insert(workspace_id.clone(), kept);
                continue;
            }
        }
        let Some(primary) = tabs
            .iter()
            .find(|tab| tab.workspace_id == *workspace_id && is_primary_terminal_candidate(tab))
        else {
            continue;
        };
        resolved.insert(workspace_id.clone(), vec![primary.id.clone()]);
    }
    resolved
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};
    use serde_json::json;

    use super::*;

    fn tab(
        id: &str,
        workspace_id: &str,
        title: &str,
        payload: Value,
        created_secs: i64,
    ) -> WorkspaceTabRecord {
        let created = Utc.timestamp_opt(created_secs, 0).single().unwrap();
        WorkspaceTabRecord {
            id: id.into(),
            workspace_id: workspace_id.into(),
            kind: "terminal".into(),
            title: title.into(),
            created_at: created,
            updated_at: created,
            payload,
        }
    }

    #[test]
    fn stored_live_ids_win_and_drop_closed_tabs() {
        let stored = BTreeMap::from([(
            "ws".into(),
            vec!["gone".into(), "main".into(), "also-main".into()],
        )]);
        let tabs = vec![
            tab("setup", "ws", "Setup", json!({}), 1),
            tab("main", "ws", "Codex", json!({}), 2),
            tab("side", "ws", "Extra", json!({}), 3),
        ];
        let resolved = resolve_workspace_main_tab_ids(&stored, &tabs);
        assert_eq!(resolved["ws"], vec!["main".to_string()]);
    }

    #[test]
    fn missing_assignment_uses_the_first_primary_candidate() {
        let tabs = vec![
            tab("setup", "ws", "Setup", json!({}), 1),
            tab(
                "once",
                "ws",
                "Install",
                json!({"initialCommandOnce": true}),
                2,
            ),
            tab("auto", "ws", "Ship", json!({"autoCloseOnSuccess": true}), 3),
            tab("primary", "ws", "Codex", json!({}), 4),
            tab("side", "ws", "Review", json!({}), 5),
        ];
        let resolved = resolve_workspace_main_tab_ids(&BTreeMap::new(), &tabs);
        assert_eq!(resolved["ws"], vec!["primary".to_string()]);
    }

    #[test]
    fn stale_assignment_falls_back_to_the_first_candidate() {
        let stored = BTreeMap::from([("ws".into(), vec!["closed".into()])]);
        let tabs = vec![
            tab("older", "ws", "First", json!({}), 1),
            tab("newer", "ws", "Second", json!({}), 2),
        ];
        let resolved = resolve_workspace_main_tab_ids(&stored, &tabs);
        assert_eq!(resolved["ws"], vec!["older".to_string()]);
    }
}
