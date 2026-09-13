use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use alera_core::runtime::Workspace;
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Default)]
pub(super) struct AiAssistOperationRegistry {
    operations: Mutex<HashMap<String, AiAssistOperation>>,
}

struct AiAssistOperation {
    cancel: Option<oneshot::Sender<()>>,
    workspace: Option<Workspace>,
    completion_waiters: Vec<oneshot::Sender<()>>,
}

pub(super) struct AiAssistRegistration {
    registry: Arc<AiAssistOperationRegistry>,
    operation_id: String,
}

impl AiAssistOperationRegistry {
    pub(super) fn register(
        self: &Arc<Self>,
        operation_id: String,
        workspace: Option<Workspace>,
    ) -> HostResult<(AiAssistRegistration, oneshot::Receiver<()>)> {
        let mut operations = self
            .operations
            .lock()
            .map_err(|_| HostError::state("AI Assist state is unavailable."))?;
        if operations.contains_key(&operation_id) {
            return Err(HostError::state(
                "AI Assist is already running for this operation.",
            ));
        }
        let (sender, receiver) = oneshot::channel();
        operations.insert(
            operation_id.clone(),
            AiAssistOperation {
                cancel: Some(sender),
                workspace,
                completion_waiters: Vec::new(),
            },
        );
        Ok((
            AiAssistRegistration {
                registry: self.clone(),
                operation_id,
            },
            receiver,
        ))
    }

    pub(super) fn require_workspace_idle(
        &self,
        workspace: &Workspace,
        action: &str,
    ) -> HostResult<()> {
        let operations = self
            .operations
            .lock()
            .map_err(|_| HostError::state("AI Assist state is unavailable."))?;
        let mut active: Vec<_> = operations
            .iter()
            .filter_map(|(id, operation)| {
                let owner = operation.workspace.as_ref()?;
                let affected = owner.id == workspace.id
                    || (workspace.kind == alera_core::runtime::WorkspaceKind::Linked
                        && owner.host_id == workspace.host_id
                        && alera_core::runtime::relocated_workspace_path(
                            &owner.path,
                            &workspace.path,
                            &workspace.path,
                        )
                        .is_some());
                affected.then_some(id.as_str())
            })
            .collect();
        active.sort_unstable();
        if active.is_empty() {
            return Ok(());
        }
        Err(HostError::state(format!(
            "Stop these AI Assist operations before {action} because process relocation or closure cannot be verified: {}",
            active.join(", ")
        )))
    }

    pub(super) fn cancel(&self, operation_id: &str) -> HostResult<bool> {
        let mut operations = self
            .operations
            .lock()
            .map_err(|_| HostError::state("AI Assist state is unavailable."))?;
        // Cancellation requests do not establish that the old future has finished.
        Ok(operations
            .get_mut(operation_id)
            .and_then(|operation| operation.cancel.take())
            .is_some_and(|sender| sender.send(()).is_ok()))
    }

    pub(super) fn cancel_workspace_operations(
        &self,
        workspace: &Workspace,
    ) -> HostResult<Vec<oneshot::Receiver<()>>> {
        let mut operations = self
            .operations
            .lock()
            .map_err(|_| HostError::state("AI Assist state is unavailable."))?;
        let mut completions = Vec::new();
        for operation in operations.values_mut() {
            if !operation.workspace.as_ref().is_some_and(|owner| {
                owner.id == workspace.id
                    && owner.instance_id == workspace.instance_id
                    && owner.host_id == workspace.host_id
            }) {
                continue;
            }
            let (finished, completion) = oneshot::channel();
            operation.completion_waiters.push(finished);
            completions.push(completion);
            if let Some(cancel) = operation.cancel.take() {
                let _ = cancel.send(());
            }
        }
        Ok(completions)
    }
}

impl Drop for AiAssistRegistration {
    fn drop(&mut self) {
        if let Ok(mut operations) = self.registry.operations.lock() {
            if let Some(operation) = operations.remove(&self.operation_id) {
                for waiter in operation.completion_waiters {
                    let _ = waiter.send(());
                }
            }
        }
    }
}

pub(super) fn active_generations() -> &'static Arc<AiAssistOperationRegistry> {
    static REGISTRY: OnceLock<Arc<AiAssistOperationRegistry>> = OnceLock::new();
    REGISTRY.get_or_init(|| Arc::new(AiAssistOperationRegistry::default()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancellation_reserves_identity_until_completion_and_preserves_neighbors() {
        let registry = Arc::new(AiAssistOperationRegistry::default());
        let (first, mut first_cancel) = registry.register("first".into(), None).unwrap();
        let (neighbor, mut neighbor_cancel) = registry.register("neighbor".into(), None).unwrap();
        assert!(registry.cancel("first").unwrap());
        assert_eq!(first_cancel.try_recv(), Ok(()));
        assert!(!registry.cancel("first").unwrap());
        assert!(registry.register("first".into(), None).is_err());
        assert_eq!(
            neighbor_cancel.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        );
        drop(first);
        let (_next, _next_cancel) = registry.register("first".into(), None).unwrap();
        assert!(registry.cancel("neighbor").unwrap());
        assert_eq!(neighbor_cancel.try_recv(), Ok(()));
        drop(neighbor);
    }

    #[test]
    fn closed_receiver_does_not_release_an_operation_still_finishing() {
        let registry = Arc::new(AiAssistOperationRegistry::default());
        let (registration, receiver) = registry.register("operation".into(), None).unwrap();
        drop(receiver);
        assert!(!registry.cancel("operation").unwrap());
        assert!(registry.register("operation".into(), None).is_err());
        drop(registration);
        assert!(registry.register("operation".into(), None).is_ok());
        assert!(!registry.cancel("missing").unwrap());
    }

    #[tokio::test]
    async fn aborting_the_generation_future_releases_its_registration() {
        let registry = Arc::new(AiAssistOperationRegistry::default());
        let (registration, receiver) = registry.register("aborted".into(), None).unwrap();
        let (started, ready) = oneshot::channel();
        let task = tokio::spawn(async move {
            let _registration = registration;
            let _ = started.send(());
            let _ = receiver.await;
        });
        ready.await.unwrap();
        assert!(registry.register("aborted".into(), None).is_err());
        task.abort();
        assert!(task.await.unwrap_err().is_cancelled());
        assert!(registry.register("aborted".into(), None).is_ok());
    }
}
