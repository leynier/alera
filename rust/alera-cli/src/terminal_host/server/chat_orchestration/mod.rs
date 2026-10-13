//! Durable orchestration between agent chats.
//!
//! This module deliberately owns only chat orchestration. Terminal
//! orchestration keeps its existing tables, permissions and lifecycle. The
//! host server supplies the workspace resolver and event sink when it wires
//! this service into its request actor.

pub(super) mod authorization;
mod cancellation;
mod credentials;
mod delegate_wait;
mod delegation;
mod lineage;
mod messages;
mod models;
mod monitor;
mod operations;
mod queries;
mod request_admission;
mod runtime;
mod service;
mod targets;
mod tasks;
mod wakes;

pub(crate) use authorization::{BoundChat, OrchestrationCaller};
pub(crate) use credentials::ChatCredentialLaunchHook;
pub(crate) use runtime::{ChatOrchestrationRuntime, LocalChatOrchestrationRuntime};
pub(crate) use service::{ChatOrchestrationService, OrchestrationEventSink};
pub(crate) use targets::RuntimeTargetResolver;
#[cfg(test)]
pub(crate) use targets::{ChatTargetResolver, ResolvedChatTarget};

pub(crate) const MAX_WAIT_SECONDS: u64 = 50;

#[cfg(test)]
mod authorization_tests;
#[cfg(test)]
mod cancel_admission_tests;
#[cfg(test)]
mod cancellation_tests;
#[cfg(test)]
mod control_admission_tests;
#[cfg(test)]
mod delegate_wait_tests;
#[cfg(test)]
mod delegation_tests;
#[cfg(test)]
pub(crate) mod mock_provider;
#[cfg(test)]
mod parser_boundary_tests;
#[cfg(test)]
mod paused_runtime_fixture;
#[cfg(test)]
mod preparation_failure_tests;
#[cfg(test)]
mod restart_recovery_tests;
#[cfg(test)]
mod satellite_fixture;
#[cfg(test)]
pub(crate) mod test_support;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod turn_lifecycle_tests;
#[cfg(test)]
mod wake_delivery_tests;
