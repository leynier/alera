//! Runtime-host agent chats over the provider adapters. See `readme.md` for
//! the wire contract and the in-process API.

use std::sync::atomic::{AtomicUsize, Ordering};

mod catalog;
pub(crate) mod commands;
pub(crate) mod events;
mod handoff;
mod header;
mod host_events;
pub(crate) mod ids;
mod instances;
mod item_normalization;
mod payload_reader;
pub(crate) mod production_factory;
pub(crate) mod provider_factory;
pub(crate) mod provider_traits;
mod request_view;
mod restart_recovery;
pub(crate) mod runtime_handle;
mod runtime_handle_attention;
mod runtime_handle_fork;
mod session;
mod session_background_work;
mod session_config;
#[cfg(test)]
mod session_delivery_tests;
mod session_effort;
mod session_feedback;
mod session_goal;
mod session_history;
mod session_history_mutations;
mod session_merge_back;
mod session_native_checkpoints;
mod session_native_dispatch;
mod session_native_fork;
mod session_native_history;
mod session_native_history_commit;
mod session_native_history_recovery;
#[cfg(test)]
mod session_native_history_tests;
mod session_ops;
mod session_pending;
mod session_projection;
mod session_projection_segments;
mod session_projection_subagents;
mod session_provider;
mod session_queue;
mod session_requests;
mod session_send;
mod session_skills;
mod session_snapshot;
mod session_subagents;
mod session_turn_admission;
mod session_turns;
pub(crate) mod tab_directory;
pub(crate) mod wire;

pub(crate) use commands::{CallerCtx, ChatOp, ReceiptKey, SendInput};
pub(crate) use events::ChatRuntimeEvent;
pub(crate) use instances::InstanceDirectory;
pub(crate) use production_factory::ProductionProviderFactory;
pub(crate) use runtime_handle::{AgentChatRuntime, CreateChatInput};

/// Counts the host's idle-shutdown decision reads: chats with work in flight
/// (a turn, an open request, queued input, a starting provider) and chats
/// with a live provider process.
#[derive(Debug, Default)]
pub(crate) struct ChatActivity {
    busy: AtomicUsize,
    live: AtomicUsize,
}

impl ChatActivity {
    pub(crate) fn adjust_busy(&self, busy: bool) {
        adjust(&self.busy, busy);
    }

    pub(crate) fn adjust_live(&self, live: bool) {
        adjust(&self.live, live);
    }

    pub(crate) fn has_busy(&self) -> bool {
        self.busy.load(Ordering::Acquire) > 0
    }

    pub(crate) fn has_live(&self) -> bool {
        self.live.load(Ordering::Acquire) > 0
    }
}

fn adjust(counter: &AtomicUsize, up: bool) {
    if up {
        counter.fetch_add(1, Ordering::AcqRel);
    } else {
        let _ = counter.fetch_update(Ordering::AcqRel, Ordering::Acquire, |value| {
            Some(value.saturating_sub(1))
        });
    }
}
