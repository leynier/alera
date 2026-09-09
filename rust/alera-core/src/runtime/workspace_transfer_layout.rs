use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

pub(super) fn merge_transfer_layout(
    source_id: &str,
    destination_id: &str,
    source: Option<Value>,
    destination: Option<Value>,
    source_tabs: &[String],
    destination_tabs: &[String],
) -> Value {
    let mut source = complete_layout(source_id, source, source_tabs);
    let destination = complete_layout(destination_id, destination, destination_tabs);
    let mut used: BTreeSet<String> = destination["groups"]
        .as_object()
        .unwrap()
        .keys()
        .cloned()
        .collect();
    let mut names = BTreeMap::new();
    let mut groups = serde_json::Map::new();
    used.extend(source["groups"].as_object().unwrap().keys().cloned());
    for (id, group) in source["groups"].as_object().unwrap() {
        let mut next = id.clone();
        let mut suffix = 1;
        while destination["groups"].get(id).is_some() && used.contains(&next) {
            next = format!("{id}/handoff/{suffix}");
            suffix += 1;
        }
        used.insert(next.clone());
        names.insert(id.clone(), next.clone());
        let mut group = group.clone();
        group["id"] = json!(next);
        groups.insert(next, group);
    }
    remap_root(&mut source["root"], &names);
    if let Some(active) = source["activeGroupId"]
        .as_str()
        .and_then(|id| names.get(id))
    {
        source["activeGroupId"] = json!(active);
    }
    let root = if destination_tabs.is_empty() {
        source["root"].clone()
    } else if source_tabs.is_empty() {
        destination["root"].clone()
    } else {
        json!({"type":"split", "axis":"horizontal", "ratio":0.5,
            "first":source["root"], "second":destination["root"]})
    };
    if !destination_tabs.is_empty() {
        groups.extend(destination["groups"].as_object().unwrap().clone());
    }
    json!({"workspaceId":destination_id, "root":root, "groups":groups,
        "activeGroupId":if source_tabs.is_empty() { &destination["activeGroupId"] } else { &source["activeGroupId"] }})
}

fn complete_layout(id: &str, layout: Option<Value>, tabs: &[String]) -> Value {
    let group_id = format!("{id}/main");
    let layout = layout.unwrap_or(Value::Null);
    let mut groups = serde_json::Map::new();
    let mut seen = BTreeSet::new();
    for (name, group) in layout["groups"].as_object().into_iter().flatten() {
        if name.is_empty() || !group.is_object() {
            continue;
        }
        let ids: Vec<Value> = group["tabIds"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .filter(|tab| tabs.iter().any(|id| id == tab) && seen.insert((*tab).to_string()))
            .map(|id| json!(id))
            .collect();
        let active = if ids.contains(&group["activeTabId"]) {
            group["activeTabId"].clone()
        } else {
            ids.last().cloned().unwrap_or(Value::Null)
        };
        groups.insert(
            name.clone(),
            json!({"id":name,"tabIds":ids,"activeTabId":active}),
        );
    }
    if groups.is_empty() {
        groups.insert(
            group_id.clone(),
            json!({"id":group_id,"tabIds":[],"activeTabId":null}),
        );
    }
    let active = layout["activeGroupId"]
        .as_str()
        .filter(|id| groups.contains_key(*id))
        .map(str::to_string)
        .unwrap_or_else(|| groups.keys().next().unwrap().clone());
    if let Some(group) = groups.get_mut(&active) {
        let ids = group["tabIds"].as_array_mut().unwrap();
        for tab in tabs {
            if seen.insert(tab.clone()) {
                ids.push(json!(tab));
            }
        }
        if group["activeTabId"].is_null() {
            group["activeTabId"] = group["tabIds"]
                .as_array()
                .unwrap()
                .last()
                .cloned()
                .unwrap_or(Value::Null);
        }
    }
    let mut leaves = BTreeSet::new();
    let mut root = normalize_root(&layout["root"], &groups, &mut leaves);
    for name in groups.keys() {
        if leaves.insert(name.clone()) {
            let leaf = json!({"type":"leaf","groupId":name});
            root = Some(match root {
                Some(root) => {
                    json!({"type":"split","axis":"horizontal","ratio":0.5,"first":root,"second":leaf})
                }
                None => leaf,
            });
        }
    }
    json!({"workspaceId":id,"root":root,"groups":groups,"activeGroupId":active})
}

fn normalize_root(
    root: &Value,
    groups: &serde_json::Map<String, Value>,
    leaves: &mut BTreeSet<String>,
) -> Option<Value> {
    if let Some(id) = root["groupId"].as_str() {
        return (groups.contains_key(id) && leaves.insert(id.to_string()))
            .then(|| json!({"type":"leaf","groupId":id}));
    }
    if root["type"] != "split" {
        return None;
    }
    let first = normalize_root(&root["first"], groups, leaves);
    let second = normalize_root(&root["second"], groups, leaves);
    match (first, second) {
        (Some(first), Some(second)) => Some(
            json!({"type":"split","axis":if root["axis"] == "vertical" {"vertical"} else {"horizontal"},
            "ratio":root["ratio"].as_f64().unwrap_or(0.5).clamp(0.15,0.85),"first":first,"second":second}),
        ),
        (first, second) => first.or(second),
    }
}

fn remap_root(root: &mut Value, names: &BTreeMap<String, String>) {
    if let Some(id) = root["groupId"].as_str().and_then(|id| names.get(id)) {
        root["groupId"] = json!(id);
    } else if root["type"] == "split" {
        remap_root(&mut root["first"], names);
        remap_root(&mut root["second"], names);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn layout(id: &str, tab: &str) -> Value {
        json!({"workspaceId":id,"root":{"type":"leaf","groupId":"main/main"},
            "groups":{"main/main":{"id":"main/main","tabIds":[tab],"activeTabId":tab}},"activeGroupId":"main/main"})
    }

    #[test]
    fn round_trip_remaps_colliding_groups_and_retains_active_selection() {
        let first = merge_transfer_layout(
            "main",
            "child",
            Some(layout("main", "agent")),
            None,
            &["agent".into()],
            &[],
        );
        let back = merge_transfer_layout(
            "child",
            "main",
            Some(first),
            Some(layout("main", "editor")),
            &["agent".into()],
            &["editor".into()],
        );
        assert_eq!(back["groups"]["main/main"]["tabIds"], json!(["editor"]));
        assert_eq!(
            back["groups"]["main/main/handoff/1"]["tabIds"],
            json!(["agent"])
        );
        assert_eq!(back["activeGroupId"], "main/main/handoff/1");
        assert_ne!(
            back["root"]["first"]["groupId"],
            back["root"]["second"]["groupId"]
        );
    }

    #[test]
    fn absent_layout_integrates_every_tab() {
        let merged = merge_transfer_layout(
            "child",
            "main",
            None,
            Some(layout("main", "editor")),
            &["agent".into(), "notes".into()],
            &["editor".into()],
        );
        assert_eq!(
            merged["groups"]["child/main"]["tabIds"],
            json!(["agent", "notes"])
        );
        assert_eq!(merged["groups"]["main/main"]["tabIds"], json!(["editor"]));
    }

    #[test]
    fn malformed_groups_and_selection_never_drop_transferred_tabs() {
        for from in [
            json!({"groups":{},"root":{},"activeGroupId":"missing"}),
            json!({"groups":{"bad":false,"other":{"tabIds":3}},"root":{"type":"leaf","groupId":"absent"},"activeGroupId":"absent"}),
        ] {
            let result = merge_transfer_layout(
                "child",
                "main",
                Some(from),
                None,
                &["a".into(), "b".into()],
                &[],
            );
            let ids: Vec<_> = result["groups"]
                .as_object()
                .unwrap()
                .values()
                .flat_map(|group| group["tabIds"].as_array().unwrap())
                .collect();
            assert_eq!(ids.len(), 2);
            assert!(ids.contains(&&json!("a")) && ids.contains(&&json!("b")));
        }
    }
}
