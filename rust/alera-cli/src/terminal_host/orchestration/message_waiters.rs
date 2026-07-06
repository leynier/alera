use alera_core::runtime::OrchestrationMessageType;

/// What a blocked request is waiting for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WaitKind {
    /// `check --wait`: any new message for the handle, optionally filtered
    /// by message type.
    Check {
        type_filter: Vec<OrchestrationMessageType>,
        inject: bool,
    },
    /// `ask`: a reply in a specific thread addressed to the asker, strictly
    /// after the question's sequence number.
    Ask {
        thread_id: String,
        after_sequence: i64,
    },
}

/// A client request parked until a matching message arrives or the deadline
/// fires. Waiters are dropped when their client disconnects.
#[derive(Debug)]
pub struct MessageWaiter {
    pub waiter_id: u64,
    pub client_id: u64,
    pub request_id: i64,
    pub handle: String,
    pub kind: WaitKind,
}

/// Registry of parked long-poll requests, owned by the server actor.
#[derive(Debug, Default)]
pub struct MessageWaiterRegistry {
    next_id: u64,
    waiters: Vec<MessageWaiter>,
}

impl MessageWaiterRegistry {
    pub fn register(
        &mut self,
        client_id: u64,
        request_id: i64,
        handle: String,
        kind: WaitKind,
    ) -> u64 {
        self.next_id += 1;
        let waiter_id = self.next_id;
        self.waiters.push(MessageWaiter {
            waiter_id,
            client_id,
            request_id,
            handle,
            kind,
        });
        waiter_id
    }

    pub fn repark(&mut self, waiter: MessageWaiter) {
        self.waiters.push(waiter);
    }

    /// Removes and returns the waiters that should wake for a message of
    /// `message_type` addressed to `to_handle`. Waiters whose type filter
    /// does not include the arriving type stay parked, so a coordinator
    /// waiting for worker_done is not woken by heartbeat noise.
    pub fn take_matching(
        &mut self,
        to_handle: &str,
        message_type: OrchestrationMessageType,
    ) -> Vec<MessageWaiter> {
        let (woken, parked): (Vec<_>, Vec<_>) = std::mem::take(&mut self.waiters)
            .into_iter()
            .partition(|waiter| {
                waiter.handle == to_handle
                    && match &waiter.kind {
                        WaitKind::Check { type_filter, .. } => {
                            type_filter.is_empty() || type_filter.contains(&message_type)
                        }
                        // Ask waiters wake on any message to the handle;
                        // the handler re-checks the thread and re-parks
                        // on a miss.
                        WaitKind::Ask { .. } => true,
                    }
            });
        self.waiters = parked;
        woken
    }

    pub fn take_by_id(&mut self, waiter_id: u64) -> Option<MessageWaiter> {
        let index = self
            .waiters
            .iter()
            .position(|waiter| waiter.waiter_id == waiter_id)?;
        Some(self.waiters.remove(index))
    }

    pub fn remove_client(&mut self, client_id: u64) {
        self.waiters.retain(|waiter| waiter.client_id != client_id);
    }

    #[cfg(test)]
    pub fn is_empty(&self) -> bool {
        self.waiters.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn type_filter_skips_non_matching_wakeups() {
        let mut registry = MessageWaiterRegistry::default();
        registry.register(
            1,
            10,
            "coord".to_string(),
            WaitKind::Check {
                type_filter: vec![OrchestrationMessageType::WorkerDone],
                inject: false,
            },
        );

        // Heartbeat noise must not wake a worker_done waiter.
        let woken = registry.take_matching("coord", OrchestrationMessageType::Heartbeat);
        assert!(woken.is_empty());
        assert!(!registry.is_empty());

        let woken = registry.take_matching("coord", OrchestrationMessageType::WorkerDone);
        assert_eq!(woken.len(), 1);
        assert!(registry.is_empty());
    }

    #[test]
    fn empty_filter_wakes_on_any_type() {
        let mut registry = MessageWaiterRegistry::default();
        registry.register(
            1,
            10,
            "coord".to_string(),
            WaitKind::Check {
                type_filter: vec![],
                inject: false,
            },
        );
        let woken = registry.take_matching("coord", OrchestrationMessageType::Status);
        assert_eq!(woken.len(), 1);
    }

    #[test]
    fn only_matching_handle_wakes() {
        let mut registry = MessageWaiterRegistry::default();
        registry.register(
            1,
            10,
            "a".to_string(),
            WaitKind::Check {
                type_filter: vec![],
                inject: false,
            },
        );
        registry.register(
            2,
            11,
            "b".to_string(),
            WaitKind::Check {
                type_filter: vec![],
                inject: false,
            },
        );
        let woken = registry.take_matching("a", OrchestrationMessageType::Status);
        assert_eq!(woken.len(), 1);
        assert_eq!(woken[0].handle, "a");
        assert!(!registry.is_empty());
    }

    #[test]
    fn ask_waiters_wake_on_any_message_to_handle() {
        let mut registry = MessageWaiterRegistry::default();
        registry.register(
            1,
            10,
            "worker".to_string(),
            WaitKind::Ask {
                thread_id: "msg_1".to_string(),
                after_sequence: 5,
            },
        );
        let woken = registry.take_matching("worker", OrchestrationMessageType::Status);
        assert_eq!(woken.len(), 1);
    }

    #[test]
    fn client_disconnect_drops_its_waiters() {
        let mut registry = MessageWaiterRegistry::default();
        registry.register(
            1,
            10,
            "a".to_string(),
            WaitKind::Check {
                type_filter: vec![],
                inject: false,
            },
        );
        registry.register(
            2,
            11,
            "a".to_string(),
            WaitKind::Check {
                type_filter: vec![],
                inject: false,
            },
        );
        registry.remove_client(1);
        let woken = registry.take_matching("a", OrchestrationMessageType::Status);
        assert_eq!(woken.len(), 1);
        assert_eq!(woken[0].client_id, 2);
    }

    #[test]
    fn take_by_id_removes_the_waiter() {
        let mut registry = MessageWaiterRegistry::default();
        let id = registry.register(
            1,
            10,
            "a".to_string(),
            WaitKind::Check {
                type_filter: vec![],
                inject: false,
            },
        );
        assert!(registry.take_by_id(id).is_some());
        assert!(registry.take_by_id(id).is_none());
    }
}
