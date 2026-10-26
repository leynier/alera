use muse_agent_sdk::MuseClientOptions;
use std::ffi::OsString;
use std::path::PathBuf;

/// Process and handshake configuration for the external `muse serve` host.
#[derive(Clone)]
pub struct MuseProviderConfig {
    pub provider_instance_id: String,
    pub options: MuseClientOptions,
}

impl Default for MuseProviderConfig {
    fn default() -> Self {
        Self {
            provider_instance_id: "muse".into(),
            options: MuseClientOptions::default(),
        }
    }
}

impl MuseProviderConfig {
    pub fn with_executable(path: impl Into<PathBuf>) -> Self {
        let mut config = Self::default();
        config.options.executable = path.into();
        config
    }

    pub fn set_env(mut self, key: impl Into<OsString>, value: impl Into<OsString>) -> Self {
        self.options.env.insert(key.into(), value.into());
        self
    }
}
