use super::*;

#[derive(Clone, Default)]
pub(crate) struct RemoteSetupSessions(Arc<Mutex<HashMap<String, SetupRoute>>>);

struct SetupRoute {
    host_id: String,
    selection: ProviderSetupContext,
    clients: HashMap<u64, String>,
}

#[derive(Clone)]
pub(crate) struct SetupCleanup {
    pub host_id: String,
    pub session_id: String,
    pub selection: ProviderSetupContext,
    pub desktop_client_id: u64,
    pub lease_id: String,
}

impl SetupCleanup {
    pub(crate) fn envelope(&self, force: bool) -> Value {
        json!({
            "type": if force { FORCE_CLOSE_OPERATION } else { "terminate" },
            "providerSetup": self.selection,
            "payload": {"sessionId": self.session_id},
            "desktopClientId": self.desktop_client_id,
            "desktopLeaseId": self.lease_id,
        })
    }
}

impl RemoteSetupSessions {
    pub(crate) fn admit(
        &self,
        host_id: &str,
        client_id: u64,
        envelope: &Value,
    ) -> HostResult<String> {
        let operation = require_string_key(envelope, "type")?;
        if !setup_operation_allowed(&operation) {
            return Err(not_allowed());
        }
        let selection = ProviderSetupContext::from_json(&envelope["providerSetup"])?;
        let session_id = require_string_key(&envelope["payload"], "sessionId")?;
        if !session_id.starts_with(SETUP_SESSION_PREFIX) {
            return Err(not_allowed());
        }
        if matches!(operation.as_str(), "createOrAttach" | "terminal.restart") {
            let tab_id = require_string_key(&envelope["payload"], "tabId")?;
            if session_id != format!("{SETUP_SESSION_PREFIX}{tab_id}")
                || envelope["payload"]["workspaceId"] != SETUP_WORKSPACE_ID
                || envelope["payload"]["launch"]["providerSetup"] != json!(selection)
                || envelope["payload"]["attachmentMode"] == "observe"
            {
                return Err(not_allowed());
            }
        }
        let mut routes = self.0.lock().expect("setup routes poisoned");
        if let Some(route) = routes.get_mut(&session_id) {
            if route.host_id != host_id || route.selection != selection {
                return Err(not_allowed());
            }
            if operation != "createOrAttach" && !route.clients.contains_key(&client_id) {
                return Err(not_allowed());
            }
            return Ok(route
                .clients
                .entry(client_id)
                .or_insert_with(|| uuid::Uuid::new_v4().to_string())
                .clone());
        }
        if operation != "createOrAttach" {
            return Err(not_allowed());
        }
        let lease = uuid::Uuid::new_v4().to_string();
        routes.insert(
            session_id,
            SetupRoute {
                host_id: host_id.into(),
                selection,
                clients: HashMap::from([(client_id, lease.clone())]),
            },
        );
        Ok(lease)
    }

    pub(crate) fn clients(&self, host_id: &str, session_id: &str) -> Option<Vec<u64>> {
        self.0
            .lock()
            .expect("setup routes poisoned")
            .get(session_id)
            .filter(|route| route.host_id == host_id)
            .map(|route| route.clients.keys().copied().collect())
    }

    pub(crate) fn lease_is_current(
        &self,
        session_id: &str,
        client_id: u64,
        lease_id: &str,
    ) -> bool {
        self.0
            .lock()
            .expect("setup routes poisoned")
            .get(session_id)
            .is_some_and(|route| {
                route
                    .clients
                    .get(&client_id)
                    .is_some_and(|lease| lease == lease_id)
            })
    }

    pub(crate) fn release(&self, session_id: &str, client_id: u64) -> Option<SetupCleanup> {
        let mut routes = self.0.lock().expect("setup routes poisoned");
        let route = routes.get_mut(session_id)?;
        let lease_id = route.clients.remove(&client_id)?;
        let cleanup = SetupCleanup {
            host_id: route.host_id.clone(),
            session_id: session_id.into(),
            selection: route.selection.clone(),
            desktop_client_id: client_id,
            lease_id,
        };
        if route.clients.is_empty() {
            routes.remove(session_id);
        }
        Some(cleanup)
    }

    pub(crate) fn forget_client(&self, client_id: u64) -> Vec<SetupCleanup> {
        let sessions: Vec<_> = self
            .0
            .lock()
            .expect("setup routes poisoned")
            .iter()
            .filter(|(_, route)| route.clients.contains_key(&client_id))
            .map(|(id, _)| id.clone())
            .collect();
        sessions
            .into_iter()
            .filter_map(|id| self.release(&id, client_id))
            .collect()
    }

    pub(crate) fn has_host(&self, host_id: &str) -> bool {
        self.0
            .lock()
            .expect("setup routes poisoned")
            .values()
            .any(|route| route.host_id == host_id && !route.clients.is_empty())
    }

    pub(crate) fn forget_host(&self, host_id: &str) -> Vec<SetupCleanup> {
        let mut cleanups = Vec::new();
        self.0
            .lock()
            .expect("setup routes poisoned")
            .retain(|session_id, route| {
                if route.host_id != host_id {
                    return true;
                }
                if let Some((client_id, lease_id)) = route.clients.iter().next() {
                    cleanups.push(SetupCleanup {
                        host_id: host_id.into(),
                        session_id: session_id.clone(),
                        selection: route.selection.clone(),
                        desktop_client_id: *client_id,
                        lease_id: lease_id.clone(),
                    });
                }
                false
            });
        cleanups
    }
}
