//! Shared provider adapter for Agent Client Protocol runtimes.

mod config;
mod construction;
mod mapping;
mod mapping_values;
mod mcp;
mod native_children;
mod native_children_route;
mod policy;
mod provider;
mod questions;
mod reasoning_effort;
mod registry_commands;
mod respond;
mod runtime_response;
mod state;
mod transport;

pub use agent_client_protocol;
pub use agent_client_protocol::{AcpClientRequestHandler, AcpRequestHandlerContext};
pub use alera_agent_transport;
pub use alera_provider_protocol;
pub use config::{AcpFlavor, AcpProviderConfig, AcpSpawnConfig};
pub use provider::AcpProvider;
pub use reasoning_effort::{config_reasoning_efforts, default_config_reasoning_effort};
pub use transport::BoxedTransport;
pub type BoxedAcpProvider = AcpProvider<BoxedTransport>;
