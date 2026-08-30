use serde_json::Value;

pub(super) fn is_history(canvas: &Value) -> bool {
    matches!(canvas.get("state").and_then(Value::as_str), Some("completed" | "orphaned" | "closed"))
}

pub(super) fn is_pinned(canvas: &Value) -> bool {
    canvas.get("pinned").and_then(Value::as_bool).unwrap_or(false)
}

pub(super) fn groups(values: &[Value], show_history: bool) -> Vec<(&'static str, Vec<&Value>)> {
    ["Pinned", "Waiting", "Live", "History"].into_iter().filter_map(|group| {
        let canvases = values.iter().filter(|canvas| match group {
            "Pinned" => is_pinned(canvas),
            "History" => show_history && is_history(canvas) && !is_pinned(canvas),
            "Waiting" => !is_pinned(canvas) && canvas["state"] == "waiting",
            "Live" => !is_pinned(canvas) && canvas["state"] == "live",
            _ => false,
        }).collect::<Vec<_>>();
        (!canvases.is_empty()).then_some((group, canvases))
    }).collect()
}

pub(super) fn selected<'a>(values: &'a [Value], selected_id: Option<&str>) -> Option<&'a Value> {
    selected_id.and_then(|id| values.iter().find(|canvas| canvas["id"] == id))
        .or_else(|| values.iter().find(|canvas| is_pinned(canvas)))
        .or_else(|| values.iter().find(|canvas| !is_history(canvas)))
        .or_else(|| values.first())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn agent_canvas_catalog_groups_without_duplicate_pinned_history() {
        let values = vec![json!({"id":"past","state":"closed"}), json!({"id":"live","state":"live"}),
            json!({"id":"pin","state":"completed","pinned":true}), json!({"id":"wait","state":"waiting"})];
        let active = groups(&values, false);
        assert_eq!(active.iter().map(|(name, _)| *name).collect::<Vec<_>>(), ["Pinned", "Waiting", "Live"]);
        assert_eq!(groups(&values, true).iter().map(|(_, rows)| rows.len()).sum::<usize>(), 4);
        assert_eq!(selected(&values, None).unwrap()["id"], "pin");
        assert_eq!(selected(&values, Some("past")).unwrap()["id"], "past");
        assert_eq!(selected(&values[..1], None).unwrap()["id"], "past");
        assert!(selected(&[], None).is_none());
    }
}
