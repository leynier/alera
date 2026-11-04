//! Native mutation persistence, independent of provider RPC execution.

#[cfg(test)]
#[path = "agent_chat_native_operations_admission_tests.rs"]
mod admission_tests;
#[path = "agent_chat_native_operations_completion.rs"]
mod completion;
#[cfg(test)]
#[path = "agent_chat_native_operations_completion_tests.rs"]
mod completion_tests;
#[path = "agent_chat_native_operations_guards.rs"]
mod guards;
#[cfg(test)]
#[path = "agent_chat_native_operations_intent_tests.rs"]
mod intent_tests;
#[path = "agent_chat_native_operations_models.rs"]
mod models;
#[path = "agent_chat_native_operations_prefix.rs"]
mod prefix;
#[path = "agent_chat_native_operations_schema.rs"]
mod schema;
#[path = "agent_chat_native_operations_store.rs"]
mod store;
#[cfg(test)]
#[path = "agent_chat_native_operations_test_support.rs"]
mod test_support;
#[path = "agent_chat_native_operations_validation.rs"]
mod validation;
#[path = "agent_chat_native_operations_view.rs"]
mod view;

pub(super) use guards::require_native_operation_safe_commit_in;
pub use models::*;
pub(super) use prefix::{require_rewind_header, rewind_in, target_in};
pub(super) use store::{active_operation_in, require_no_native_operation_in};
pub use view::agent_chat_native_operation_public_summary;
