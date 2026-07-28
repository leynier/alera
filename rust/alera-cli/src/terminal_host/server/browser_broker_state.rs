use std::collections::HashSet;

use super::{BrowserBroker, BrowserCall, BrowserDrain, RemovedBrowserCall};

impl BrowserBroker {
    pub(super) fn remove_calls_for_tabs<'a>(
        &mut self,
        tab_ids: impl IntoIterator<Item = &'a str>,
    ) -> BrowserDrain {
        let tabs = tab_ids
            .into_iter()
            .map(str::to_string)
            .collect::<HashSet<_>>();
        self.remove_matching(|call| tabs.contains(&call.tab_id))
    }

    pub(super) fn remove_calls_for_tab_except(
        &mut self,
        tab_id: &str,
        preserved_correlation_id: Option<&str>,
    ) -> BrowserDrain {
        self.remove_matching(|call| {
            call.tab_id == tab_id && preserved_correlation_id != Some(call.correlation_id.as_str())
        })
    }

    pub(super) fn can_preserve_navigation(
        &self,
        owner_client_id: u64,
        tab_id: &str,
        generation: u64,
        correlation_id: &str,
    ) -> bool {
        self.in_flight.get(tab_id).map(String::as_str) == Some(correlation_id)
            && self.calls.get(correlation_id).is_some_and(|call| {
                call.owner_client_id == owner_client_id
                    && call.tab_id == tab_id
                    && call.generation == generation
                    && is_navigation_request(&call.request_type)
            })
    }

    pub(super) fn remove_matching(
        &mut self,
        predicate: impl Fn(&BrowserCall) -> bool,
    ) -> BrowserDrain {
        let ids = self
            .calls
            .values()
            .filter(|call| predicate(call))
            .map(|call| call.correlation_id.clone())
            .collect::<Vec<_>>();
        let mut drain = BrowserDrain::default();
        let mut affected_tabs = HashSet::new();
        for id in ids {
            let Some(call) = self.calls.remove(&id) else {
                continue;
            };
            let was_in_flight =
                self.in_flight.get(&call.tab_id).map(String::as_str) == Some(id.as_str());
            if was_in_flight {
                self.in_flight.remove(&call.tab_id);
            } else if let Some(queue) = self.queues.get_mut(&call.tab_id) {
                queue.retain(|queued| queued != &id);
            }
            affected_tabs.insert(call.tab_id.clone());
            drain.removed.push(RemovedBrowserCall {
                call,
                was_in_flight,
            });
        }
        for tab_id in affected_tabs {
            if !self.pages.contains_key(&tab_id) {
                self.queues.remove(&tab_id);
                continue;
            }
            if !self.in_flight.contains_key(&tab_id) {
                if let Some(call) = self.promote(&tab_id) {
                    drain.promoted.push(call);
                }
            }
        }
        drain
    }

    pub(super) fn promote(&mut self, tab_id: &str) -> Option<BrowserCall> {
        let queue = self.queues.get_mut(tab_id)?;
        while let Some(correlation_id) = queue.pop_front() {
            if let Some(call) = self.calls.get(&correlation_id).cloned() {
                self.in_flight.insert(tab_id.to_string(), correlation_id);
                if queue.is_empty() {
                    self.queues.remove(tab_id);
                }
                return Some(call);
            }
        }
        self.queues.remove(tab_id);
        None
    }

    pub(super) fn allocate_generation(&mut self) -> u64 {
        self.next_generation = self.next_generation.wrapping_add(1).max(1);
        self.next_generation
    }
}

fn is_navigation_request(request_type: &str) -> bool {
    matches!(
        request_type,
        "browser.navigate" | "browser.back" | "browser.forward" | "browser.reload"
    )
}
