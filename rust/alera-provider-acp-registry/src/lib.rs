//! Rust ACP Registry provider boundary.
//!
//! Registry agents and local ACP recipes share the common ACP runtime. This
//! crate keeps only recipe/auth/distribution policy and registry flavor data.

mod client_terminals;
#[cfg(test)]
mod client_terminals_edge_tests;
mod client_terminals_lifecycle;
mod client_terminals_output;
mod client_terminals_process;
#[cfg(test)]
mod client_terminals_tests;
mod client_terminals_wire;
mod config;
mod provider;
mod registry_flavor;
#[cfg(test)]
mod registry_flavor_tests;

pub use alera_provider_protocol;
pub use client_terminals_process::{
    ClientTerminalChild, ClientTerminalCommand, ClientTerminalExitStatus, ClientTerminalSpawner,
    NativeClientTerminalSpawner, SpawnedClientTerminal, TerminalReadPipe,
};
pub use config::{
    AcpDistribution, AcpRegistryAgentFlavor, AcpRegistryProviderConfig, AcpRegistryRecipe,
    AcpRegistrySource,
};
pub use provider::AcpRegistryProvider;
