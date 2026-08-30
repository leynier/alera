use serde_json::{json, Value};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct AutomationViewEpoch(u64);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RequestKind {
    List,
    Detail,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct AutomationRequestEpoch {
    view: AutomationViewEpoch,
    kind: RequestKind,
    sequence: u64,
}

#[derive(Default)]
pub(super) struct AutomationRequests {
    view: u64,
    list: u64,
    detail: u64,
}

impl AutomationRequests {
    pub(super) fn reset_view(&mut self) {
        self.view = self.view.wrapping_add(1);
    }

    pub(super) fn view(&self) -> AutomationViewEpoch {
        AutomationViewEpoch(self.view)
    }

    pub(super) fn accepts_view(&self, view: AutomationViewEpoch) -> bool {
        self.view() == view
    }

    pub(super) fn begin_list(&mut self) -> AutomationRequestEpoch {
        self.list = self.list.wrapping_add(1);
        AutomationRequestEpoch { view: self.view(), kind: RequestKind::List, sequence: self.list }
    }

    pub(super) fn begin_detail(&mut self) -> AutomationRequestEpoch {
        self.detail = self.detail.wrapping_add(1);
        AutomationRequestEpoch { view: self.view(), kind: RequestKind::Detail, sequence: self.detail }
    }

    pub(super) fn accepts(&self, request: AutomationRequestEpoch) -> bool {
        self.accepts_view(request.view) && request.sequence == match request.kind {
            RequestKind::List => self.list,
            RequestKind::Detail => self.detail,
        }
    }
}

pub(super) fn editor_definition(initial: Option<&Value>) -> Value {
    initial.and_then(|value| value.get("automation").or(Some(value)))
        .filter(|value| value.is_object()).cloned().unwrap_or_else(|| json!({}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn automation_detail_responses_must_match_latest_request_even_when_id_repeats() {
        let mut requests = AutomationRequests::default();
        let first_a = requests.begin_detail();
        let b = requests.begin_detail();
        let second_a = requests.begin_detail();
        assert!(!requests.accepts(first_a));
        assert!(!requests.accepts(b));
        assert!(requests.accepts(second_a));
    }

    #[test]
    fn automation_close_reopen_invalidates_reads_and_mutation_completions() {
        let mut requests = AutomationRequests::default();
        let view = requests.view();
        let list = requests.begin_list();
        let detail = requests.begin_detail();
        requests.reset_view();
        requests.reset_view();
        assert!(!requests.accepts_view(view));
        assert!(!requests.accepts(list));
        assert!(!requests.accepts(detail));
        let current = requests.begin_list();
        assert!(requests.accepts(current));
    }

    #[test]
    fn automation_refresh_invalidates_an_older_catalog_without_invalidating_its_view() {
        let mut requests = AutomationRequests::default();
        let view = requests.view();
        let old = requests.begin_list();
        let new = requests.begin_list();
        assert!(!requests.accepts(old));
        assert!(requests.accepts(new));
        assert!(requests.accepts_view(view));
    }

    #[test]
    fn new_automation_editor_does_not_inherit_the_selected_active_definition() {
        let selected = json!({"automation": {"id": "old", "state": "active", "queueCap": 42}});
        let mut draft = editor_definition(Some(&selected));
        assert_eq!(draft["id"], "old");
        draft = editor_definition(None);
        assert_eq!(draft, json!({}));
        assert_eq!(selected["automation"]["state"], "active");
        assert_eq!(editor_definition(Some(&json!("invalid"))), json!({}));
    }
}
