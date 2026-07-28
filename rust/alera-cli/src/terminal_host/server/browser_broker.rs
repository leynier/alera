use std::collections::{BTreeSet, HashMap, VecDeque};

use serde::Serialize;
use serde_json::{json, Value};

#[path = "browser_broker_state.rs"]
mod browser_broker_state;

pub(super) const MAX_BROWSER_CALLS_PER_TAB: usize = 32;
pub(super) const MAX_BROWSER_CALLS_TOTAL: usize = 256;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct BrowserDriver {
    #[serde(skip)]
    pub owner_client_id: u64,
    pub app_instance_id: String,
    pub driver_instance_id: String,
    pub engine: String,
    pub platform: String,
    pub capabilities: BTreeSet<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct BrowserPage {
    pub tab_id: String,
    pub workspace_id: String,
    pub profile_id: String,
    pub generation: u64,
    pub document_generation: u64,
    pub url: Option<String>,
    pub title: Option<String>,
    pub capabilities: BTreeSet<String>,
    #[serde(skip)]
    pub owner_client_id: u64,
}

#[derive(Debug, Clone)]
pub(super) struct BrowserCall {
    pub correlation_id: String,
    pub requester_client_id: u64,
    pub requester_request_id: i64,
    pub owner_client_id: u64,
    pub request_type: String,
    pub tab_id: String,
    pub generation: u64,
    pub params: Value,
    pub deadline_at_ms: i64,
}

#[derive(Debug, Clone)]
pub(super) struct BrowserPageChange {
    pub expected_generation: u64,
    pub profile_id: Option<String>,
    pub document_generation: Option<u64>,
    pub document_changed: bool,
    pub navigation_correlation_id: Option<String>,
    pub url_changed: bool,
    pub url: Option<String>,
    pub title: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct BrowserFailure {
    pub code: &'static str,
    pub message: String,
    pub next_steps: Vec<String>,
    pub retryable: bool,
}

impl BrowserFailure {
    pub(super) fn payload(&self) -> Value {
        json!({
            "ok": false,
            "error": {
                "code": self.code,
                "message": self.message,
                "nextSteps": self.next_steps,
                "retryable": self.retryable,
            }
        })
    }
}

#[derive(Debug)]
pub(super) struct BrowserEnqueue {
    pub call: BrowserCall,
    pub dispatch_now: bool,
}

#[derive(Debug)]
pub(super) struct RemovedBrowserCall {
    pub call: BrowserCall,
    pub was_in_flight: bool,
}

#[derive(Debug, Default)]
pub(super) struct BrowserDrain {
    pub removed: Vec<RemovedBrowserCall>,
    pub promoted: Vec<BrowserCall>,
}

#[derive(Debug)]
pub(super) struct BrowserCompletion {
    pub call: BrowserCall,
    pub promoted: Option<BrowserCall>,
}

#[derive(Debug, Default)]
pub(super) struct BrowserBroker {
    drivers: HashMap<u64, BrowserDriver>,
    pages: HashMap<String, BrowserPage>,
    calls: HashMap<String, BrowserCall>,
    queues: HashMap<String, VecDeque<String>>,
    in_flight: HashMap<String, String>,
    next_generation: u64,
}

impl BrowserBroker {
    pub(super) fn active_jobs(&self) -> usize {
        self.calls.len()
    }

    pub(super) fn driver(&self, owner_client_id: u64) -> Option<&BrowserDriver> {
        self.drivers.get(&owner_client_id)
    }

    pub(super) fn stable_driver_available(&self) -> bool {
        self.drivers
            .values()
            .any(|driver| driver.capabilities.contains("stableGate"))
    }

    pub(super) fn page(&self, tab_id: &str) -> Option<&BrowserPage> {
        self.pages.get(tab_id)
    }

    pub(super) fn call(&self, correlation_id: &str) -> Option<&BrowserCall> {
        self.calls.get(correlation_id)
    }

    pub(super) fn expired_correlations(&self, now_ms: i64) -> Vec<String> {
        self.calls
            .values()
            .filter(|call| call.deadline_at_ms <= now_ms)
            .map(|call| call.correlation_id.clone())
            .collect()
    }

    pub(super) fn pages(&self) -> Vec<BrowserPage> {
        let mut pages = self.pages.values().cloned().collect::<Vec<_>>();
        pages.sort_by(|left, right| left.tab_id.cmp(&right.tab_id));
        pages
    }

    pub(super) fn register_driver(&mut self, driver: BrowserDriver) -> BrowserDrain {
        let drain = self.remove_driver(driver.owner_client_id);
        self.drivers.insert(driver.owner_client_id, driver);
        drain
    }

    pub(super) fn sync_page(
        &mut self,
        owner_client_id: u64,
        mut page: BrowserPage,
    ) -> Result<(BrowserPage, BrowserDrain), BrowserFailure> {
        if !self.drivers.contains_key(&owner_client_id) {
            return Err(failure(
                "driver_not_registered",
                "Register the browser driver before synchronizing pages.",
                &["Call browser.driver.register and retry the sync."],
            ));
        }
        if let Some(existing) = self.pages.get(&page.tab_id) {
            if existing.owner_client_id != owner_client_id {
                return Err(failure(
                    "page_owned",
                    format!(
                        "Browser tab {} is owned by another app connection.",
                        page.tab_id
                    ),
                    &["Wait for the owning app connection to unregister or disconnect."],
                ));
            }
            if existing.workspace_id == page.workspace_id
                && existing.profile_id == page.profile_id
                && existing.document_generation == page.document_generation
            {
                page.owner_client_id = owner_client_id;
                page.generation = existing.generation;
                self.pages.insert(page.tab_id.clone(), page.clone());
                return Ok((page, BrowserDrain::default()));
            }
        }
        let drain = self.remove_page(&page.tab_id);
        page.owner_client_id = owner_client_id;
        page.generation = self.allocate_generation();
        self.pages.insert(page.tab_id.clone(), page.clone());
        Ok((page, drain))
    }

    pub(super) fn change_page(
        &mut self,
        owner_client_id: u64,
        tab_id: &str,
        change: BrowserPageChange,
    ) -> Result<(BrowserPage, BrowserDrain, bool, Option<String>), BrowserFailure> {
        let existing = self.owned_page(owner_client_id, tab_id)?.clone();
        if change.expected_generation != existing.generation {
            return Err(stale_generation(tab_id));
        }
        let profile_changed = change
            .profile_id
            .as_deref()
            .is_some_and(|value| value != existing.profile_id);
        let document_generation_changed = change
            .document_generation
            .is_some_and(|value| value != existing.document_generation);
        let document_transition = change.document_changed || document_generation_changed;
        let invalidate = document_transition || profile_changed;
        let preserved_navigation = if document_transition && !profile_changed {
            change
                .navigation_correlation_id
                .as_deref()
                .filter(|correlation_id| {
                    self.can_preserve_navigation(
                        owner_client_id,
                        tab_id,
                        existing.generation,
                        correlation_id,
                    )
                })
                .map(str::to_string)
        } else {
            None
        };
        let drain = if invalidate {
            self.remove_calls_for_tab_except(tab_id, preserved_navigation.as_deref())
        } else {
            BrowserDrain::default()
        };
        let generation = if invalidate {
            self.allocate_generation()
        } else {
            existing.generation
        };
        if let Some(correlation_id) = preserved_navigation.as_deref() {
            self.calls
                .get_mut(correlation_id)
                .expect("preserved navigation remains active")
                .generation = generation;
        }
        let page = self
            .pages
            .get_mut(tab_id)
            .expect("owned page exists after call drain");
        page.generation = generation;
        if let Some(document_generation) = change.document_generation {
            page.document_generation = document_generation;
        }
        if let Some(profile_id) = change.profile_id {
            page.profile_id = profile_id;
        }
        if change.url_changed {
            page.url = change.url;
        }
        if change.title.is_some() {
            page.title = change.title;
        }
        Ok((page.clone(), drain, invalidate, preserved_navigation))
    }

    pub(super) fn remove_page_owned(
        &mut self,
        owner_client_id: u64,
        tab_id: &str,
    ) -> Result<BrowserDrain, BrowserFailure> {
        self.owned_page(owner_client_id, tab_id)?;
        Ok(self.remove_page(tab_id))
    }

    pub(super) fn remove_page(&mut self, tab_id: &str) -> BrowserDrain {
        self.pages.remove(tab_id);
        self.remove_calls_for_tabs([tab_id])
    }

    pub(super) fn remove_driver(&mut self, owner_client_id: u64) -> BrowserDrain {
        self.drivers.remove(&owner_client_id);
        let tab_ids = self
            .pages
            .values()
            .filter(|page| page.owner_client_id == owner_client_id)
            .map(|page| page.tab_id.clone())
            .collect::<Vec<_>>();
        for tab_id in &tab_ids {
            self.pages.remove(tab_id);
        }
        self.remove_calls_for_tabs(tab_ids.iter().map(String::as_str))
    }

    pub(super) fn enqueue(&mut self, call: BrowserCall) -> Result<BrowserEnqueue, BrowserFailure> {
        let page = self.pages.get(&call.tab_id).ok_or_else(|| {
            failure(
                "page_unavailable",
                format!("Browser tab {} has no registered app page.", call.tab_id),
                &["Open or focus the tab in the Alera desktop app and retry."],
            )
        })?;
        if page.generation != call.generation {
            return Err(stale_generation(&call.tab_id));
        }
        if page.owner_client_id != call.owner_client_id {
            return Err(stale_generation(&call.tab_id));
        }
        if self.calls.len() >= MAX_BROWSER_CALLS_TOTAL {
            return Err(queue_full("browser broker"));
        }
        let queued = self.queues.get(&call.tab_id).map_or(0, VecDeque::len);
        let active = usize::from(self.in_flight.contains_key(&call.tab_id));
        if queued + active >= MAX_BROWSER_CALLS_PER_TAB {
            return Err(queue_full(&format!("browser tab {}", call.tab_id)));
        }
        let dispatch_now = active == 0;
        if dispatch_now {
            self.in_flight
                .insert(call.tab_id.clone(), call.correlation_id.clone());
        } else {
            self.queues
                .entry(call.tab_id.clone())
                .or_default()
                .push_back(call.correlation_id.clone());
        }
        self.calls.insert(call.correlation_id.clone(), call.clone());
        Ok(BrowserEnqueue { call, dispatch_now })
    }

    pub(super) fn complete(
        &mut self,
        owner_client_id: u64,
        correlation_id: &str,
        tab_id: &str,
        generation: u64,
    ) -> Result<BrowserCompletion, BrowserFailure> {
        let call = self.calls.get(correlation_id).cloned().ok_or_else(|| {
            failure(
                "stale_response",
                format!("Browser response {correlation_id} is no longer active."),
                &["Discard this response and wait for the next driver request."],
            )
        })?;
        let page = self.owned_page(owner_client_id, tab_id)?;
        if call.tab_id != tab_id
            || call.generation != generation
            || page.generation != generation
            || self.in_flight.get(tab_id).map(String::as_str) != Some(correlation_id)
        {
            return Err(stale_generation(tab_id));
        }
        self.calls.remove(correlation_id);
        self.in_flight.remove(tab_id);
        Ok(BrowserCompletion {
            call,
            promoted: self.promote(tab_id),
        })
    }

    pub(super) fn remove_correlation(&mut self, correlation_id: &str) -> BrowserDrain {
        let Some(call) = self.calls.get(correlation_id).cloned() else {
            return BrowserDrain::default();
        };
        self.remove_matching(|candidate| candidate.correlation_id == call.correlation_id)
    }

    pub(super) fn remove_requester(&mut self, client_id: u64) -> BrowserDrain {
        self.remove_matching(|call| call.requester_client_id == client_id)
    }

    fn owned_page(
        &self,
        owner_client_id: u64,
        tab_id: &str,
    ) -> Result<&BrowserPage, BrowserFailure> {
        match self.pages.get(tab_id) {
            Some(page) if page.owner_client_id == owner_client_id => Ok(page),
            Some(_) => Err(failure(
                "not_page_owner",
                format!("This app connection does not own browser tab {tab_id}."),
                &["Synchronize only pages created by this app connection."],
            )),
            None => Err(failure(
                "page_unavailable",
                format!("Browser tab {tab_id} is not registered."),
                &["Synchronize the page before reporting changes or completions."],
            )),
        }
    }
}

fn failure(code: &'static str, message: impl Into<String>, next_steps: &[&str]) -> BrowserFailure {
    BrowserFailure {
        code,
        message: message.into(),
        next_steps: next_steps.iter().map(|step| (*step).to_string()).collect(),
        retryable: !matches!(
            code,
            "not_page_owner" | "driver_not_registered" | "page_owned"
        ),
    }
}

fn stale_generation(tab_id: &str) -> BrowserFailure {
    failure(
        "stale_page",
        format!("Browser tab {tab_id} changed before this operation completed."),
        &["Take a new snapshot and retry against its current generation."],
    )
}

fn queue_full(scope: &str) -> BrowserFailure {
    failure(
        "queue_full",
        format!("The {scope} automation queue is full."),
        &["Wait for current browser operations to finish and retry."],
    )
}
