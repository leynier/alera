use std::collections::{BTreeMap, BTreeSet};
use serde_json::Value;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub(super) enum AutomationFilter { State, Project, Profile, Tag }

impl AutomationFilter {
    pub fn label(self) -> &'static str { match self { Self::State => "State", Self::Project => "Project", Self::Profile => "Profile", Self::Tag => "Tag" } }
}

#[derive(Default)]
pub(super) struct AutomationFilters(pub BTreeMap<AutomationFilter, String>);

impl AutomationFilters {
    pub fn matches(&self, item: &Value, query: &str) -> bool {
        self.0.iter().all(|(filter, selected)| values(item, *filter).iter().any(|value| value == selected))
            && (query.is_empty() || ["name", "slug", "description"].iter().any(|key| item[key].as_str().unwrap_or_default().to_lowercase().contains(query)))
    }
    pub fn set(&mut self, filter: AutomationFilter, value: Option<String>) {
        if let Some(value) = value { self.0.insert(filter, value); } else { self.0.remove(&filter); }
    }
}

pub(super) fn options(items: &[Value], filter: AutomationFilter) -> Vec<String> {
    if filter == AutomationFilter::State {
        return ["draft", "active", "paused", "blocked", "archived", "trashed"].map(str::to_owned).into();
    }
    let mut seen = BTreeSet::new();
    items.iter().flat_map(|item| values(item, filter)).filter(|value| seen.insert(value.clone())).collect()
}

fn values(item: &Value, filter: AutomationFilter) -> Vec<String> {
    match filter {
        AutomationFilter::State => item["state"].as_str().map(str::to_owned).into_iter().collect(),
        AutomationFilter::Project => item["projectId"].as_str().map(str::to_owned).into_iter().collect(),
        AutomationFilter::Profile => item["target"].as_object().and_then(|target| target.values().find_map(|value| value["agentProfileId"].as_str())).map(str::to_owned).into_iter().collect(),
        AutomationFilter::Tag => item["tagIds"].as_array().into_iter().flatten().filter_map(Value::as_str).map(str::to_owned).collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn automation_catalog_combines_all_filters_and_unicode_search() {
        let item = json!({"name":"Revisión","slug":"review","description":"Fixture","state":"draft","projectId":"p","target":{"freshTab":{"agentProfileId":"agent"}},"tagIds":["one","two"]});
        let mut filters = AutomationFilters::default();
        for (filter, value) in [(AutomationFilter::State,"draft"), (AutomationFilter::Project,"p"), (AutomationFilter::Profile,"agent"), (AutomationFilter::Tag,"two")] { filters.set(filter, Some(value.into())); }
        assert!(filters.matches(&item, "revisión"));
        assert!(!filters.matches(&item, "absent"));
        filters.set(AutomationFilter::Project, Some("other".into()));
        assert!(!filters.matches(&item, ""));
        filters.set(AutomationFilter::Project, None);
        assert!(filters.matches(&item, "fixture"));
    }

    #[test]
    fn automation_catalog_options_keep_catalog_order_and_deduplicate() {
        let items = vec![json!({"projectId":"b","tagIds":["z","a"]}), json!({"projectId":"a","tagIds":["z"]}), json!({"projectId":"b"})];
        assert_eq!(options(&items, AutomationFilter::Project), ["b", "a"]);
        assert_eq!(options(&items, AutomationFilter::Tag), ["z", "a"]);
        assert!(options(&items, AutomationFilter::State).contains(&"blocked".into()));
        assert!(options(&items, AutomationFilter::Profile).is_empty());
    }
}
