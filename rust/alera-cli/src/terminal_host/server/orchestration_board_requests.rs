use std::sync::{Arc, OnceLock};
use std::time::Duration;

use alera_core::runtime::{
    OrchestrationBoardQuery, OrchestrationRunSnapshotQuery, OrchestrationTaskInspectionQuery,
    RuntimeStore,
};
use serde_json::{json, Value};
use tokio::sync::Semaphore;

use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, event, ok_response};

use super::{ClientKind, ServerActor};

static READ_SLOTS: OnceLock<Arc<Semaphore>> = OnceLock::new();
static READ_QUEUE: OnceLock<Arc<Semaphore>> = OnceLock::new();

impl ServerActor {
    pub(super) fn start_orchestration_board_read(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| HostError::state("client closed"))?;
        if client.kind != ClientKind::Local {
            return Err(HostError::state("the run board requires a local client"));
        }
        let read = match request_type {
            "orchestration.boardSnapshot" => BoardRead::List(parse(payload)?),
            "orchestration.runSnapshot" => BoardRead::Run(parse(payload)?),
            "orchestration.taskInspection" => BoardRead::Task(parse(payload)?),
            _ => return Err(HostError::format("unknown board request")),
        };
        let permit = READ_QUEUE
            .get_or_init(|| Arc::new(Semaphore::new(8)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| HostError::state("run board is busy; retry shortly"))?;
        let store = self.runtime_store.clone();
        let client = client.handle.clone();
        // SQLite uses its worker threads; serialization also stays outside the
        // actor. Bound both concurrent reads and disconnected request lifetime.
        tokio::spawn(async move {
            let _permit = permit;
            let result = tokio::time::timeout(Duration::from_secs(25), async move {
                let _active = READ_SLOTS
                    .get_or_init(|| Arc::new(Semaphore::new(2)))
                    .clone()
                    .acquire_owned()
                    .await
                    .map_err(|_| HostError::state("run board is unavailable"))?;
                read.execute(store).await
            })
            .await
            .unwrap_or_else(|_| Err(HostError::state("run board read timed out")));
            reply(&client, request_id, result);
        });
        Ok(())
    }

    pub(super) async fn broadcast_orchestration_board_change(&self) {
        match self.runtime_store.take_orchestration_board_change().await {
            Ok(Some(revision)) => {
                let payload = event("orchestrationBoardChanged", json!({ "revision": revision }));
                for client in self
                    .clients
                    .values()
                    .filter(|c| c.authenticated && c.kind == ClientKind::Local)
                {
                    let _ = client
                        .handle
                        .send_control(ClientFrame::Json(payload.clone()));
                }
            }
            Ok(None) => {}
            Err(error) => tracing::warn!("could not read orchestration board revision: {error}"),
        }
    }

    pub(super) async fn handle_board_coordinator_tick(&mut self, run_id: String) {
        self.handle_coordinator_tick(run_id).await;
        self.broadcast_orchestration_board_change().await;
    }

    pub(super) async fn handle_board_agent_hook(
        &mut self,
        event: crate::agent_status::AgentHookEvent,
    ) {
        self.handle_agent_hook_event(event).await;
        self.broadcast_orchestration_board_change().await;
    }
}

enum BoardRead {
    List(OrchestrationBoardQuery),
    Run(OrchestrationRunSnapshotQuery),
    Task(OrchestrationTaskInspectionQuery),
}

impl BoardRead {
    async fn execute(self, store: RuntimeStore) -> HostResult<Value> {
        let value = match self {
            Self::Task(query) => serde_json::to_value(
                store
                    .orchestration_task_inspection(&query)
                    .await
                    .map_err(state)?,
            ),
            Self::List(query) => serde_json::to_value(
                store
                    .orchestration_board_snapshot(&query)
                    .await
                    .map_err(state)?,
            ),
            Self::Run(query) => serde_json::to_value(
                store
                    .orchestration_run_snapshot(&query)
                    .await
                    .map_err(state)?,
            ),
        };
        value.map_err(state)
    }
}

fn parse<T: serde::de::DeserializeOwned>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone()).map_err(|e| HostError::format(e.to_string()))
}

fn state(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

fn reply(client: &ClientHandle, id: i64, result: HostResult<Value>) {
    let response = match result {
        Ok(value) => ok_response(id, value),
        Err(error) => error_response(id, &error),
    };
    let _ = client.send_control(ClientFrame::Json(response));
}
