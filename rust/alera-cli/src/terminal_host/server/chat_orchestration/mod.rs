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
mod delegation_options;
mod job_lifecycle;
mod lineage;
mod messages;
mod models;
mod monitor;
mod native_operation_guard;
pub(crate) mod operation_wire;
mod operations;
mod parent;
mod queries;
mod request_admission;
mod request_parser;
mod runtime;
mod service;
mod targets;
mod task_acknowledgement;
mod tasks;
mod transfers;
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
mod background_wait_tests;
#[cfg(test)]
mod cancel_admission_tests;
#[cfg(test)]
mod cancellation_tests;
#[cfg(test)]
mod control_admission_tests;
#[cfg(test)]
mod credential_launch_tests;
#[cfg(test)]
mod delegate_wait_tests;
#[cfg(test)]
mod delegation_tests;
#[cfg(test)]
mod effort_configuration_tests;
#[cfg(test)]
mod frozen_receipt_replay_tests;
#[cfg(test)]
pub(crate) mod mock_provider;
#[cfg(test)]
mod native_operation_guard_tests;
#[cfg(test)]
mod operation_wire_tests;
#[cfg(test)]
mod parser_boundary_tests;
#[cfg(test)]
mod paused_runtime_fixture;
#[cfg(test)]
mod person_parent_tests;
#[cfg(test)]
mod preparation_failure_tests;
#[cfg(test)]
mod restart_recovery_tests;
#[cfg(test)]
mod satellite_fixture;
#[cfg(test)]
mod shutdown_tests;
#[cfg(test)]
mod subagent_projection_tests;
#[cfg(test)]
mod task_acknowledgement_tests;
#[cfg(test)]
pub(crate) mod test_support;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod transfers_tests;
#[cfg(test)]
mod turn_lifecycle_tests;
#[cfg(test)]
mod wake_delivery_tests;
