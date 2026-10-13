//! Shared provider adapter for Agent Client Protocol runtimes.

mod config;
mod construction;
mod mapping;
mod mapping_values;
mod mcp;
mod policy;
mod provider;
mod questions;
mod runtime_response;
mod state;
mod transport;

pub use agent_client_protocol;
pub use agent_client_protocol::{AcpClientRequestHandler, AcpRequestHandlerContext};
pub use alera_agent_transport;
pub use alera_provider_protocol;
pub use config::{AcpFlavor, AcpProviderConfig, AcpSpawnConfig};
pub use provider::AcpProvider;
pub use transport::BoxedTransport;
pub type BoxedAcpProvider = AcpProvider<BoxedTransport>;
