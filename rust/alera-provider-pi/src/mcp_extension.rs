use alera_agent_transport::ProcessConfig;
use alera_provider_protocol::{McpServerSpec, McpTransport, ProviderError};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

const EXTENSION_FILE: &str = "alera-mcp-extension.mjs";
const SPEC_FILE: &str = "servers.json";
static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(1);

/// A private, process-lifetime copy of the extension and its host-provided
/// server list. The Pi process receives only these paths in its launch input.
pub(crate) struct McpExtensionLease {
    directory: PathBuf,
    extension_path: PathBuf,
    spec_path: PathBuf,
}

impl McpExtensionLease {
    pub(crate) fn prepare(servers: &[McpServerSpec]) -> Result<Option<Self>, ProviderError> {
        for server in servers {
            server.validate()?;
            if matches!(&server.transport, McpTransport::Http { .. }) {
                return Err(ProviderError::Unsupported(
                    "Pi MCP injection supports stdio servers only".into(),
                ));
            }
        }

        let directory = create_private_directory()?;
        let extension_path = directory.join(EXTENSION_FILE);
        let spec_path = directory.join(SPEC_FILE);
        let result = (|| {
            write_private(&extension_path, EXTENSION_SOURCE.as_bytes())?;
            write_private(
                &directory.join("mcp_process_tree.mjs"),
                PROCESS_TREE_SOURCE.as_bytes(),
            )?;
            write_private(
                &directory.join("mcp_stdio_supervisor.mjs"),
                SUPERVISOR_SOURCE.as_bytes(),
            )?;
            write_private(
                &directory.join("permission_extension.mjs"),
                PERMISSION_SOURCE.as_bytes(),
            )?;
            let specs = serde_json::to_vec_pretty(servers).map_err(|error| {
                ProviderError::Protocol(format!("serialize Pi MCP specs: {error}"))
            })?;
            write_private(&spec_path, &specs)?;
            Ok::<_, ProviderError>(())
        })();
        if let Err(error) = result {
            let _ = fs::remove_dir_all(&directory);
            return Err(error);
        }
        Ok(Some(Self {
            directory,
            extension_path,
            spec_path,
        }))
    }

    pub(crate) fn configure(&self, process: &mut ProcessConfig) {
        process.args.extend([
            "--extension".into(),
            self.extension_path.clone().into_os_string(),
        ]);
        process.env.insert(
            "ALERA_PI_MCP_SPEC_FILE".into(),
            self.spec_path.clone().into_os_string(),
        );
    }

    #[cfg(test)]
    pub(crate) fn extension_path(&self) -> &PathBuf {
        &self.extension_path
    }

    #[cfg(test)]
    pub(crate) fn spec_path(&self) -> &PathBuf {
        &self.spec_path
    }
}

impl Drop for McpExtensionLease {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.directory);
    }
}

fn create_private_directory() -> Result<PathBuf, ProviderError> {
    let parent = std::env::temp_dir();
    for _ in 0..32 {
        let suffix = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        let path = parent.join(format!("alera-pi-mcp-{}-{suffix}", std::process::id()));
        match fs::create_dir(&path) {
            Ok(()) => {
                #[cfg(unix)]
                fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).map_err(|error| {
                    let _ = fs::remove_dir_all(&path);
                    ProviderError::Protocol(format!("set Pi MCP directory permissions: {error}"))
                })?;
                return Ok(path);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(ProviderError::Protocol(format!(
                    "create Pi MCP extension directory: {error}"
                )))
            }
        }
    }
    Err(ProviderError::Protocol(
        "could not allocate a private Pi MCP extension directory".into(),
    ))
}

fn write_private(path: &PathBuf, bytes: &[u8]) -> Result<(), ProviderError> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    let mut file = options.open(path).map_err(|error| {
        ProviderError::Protocol(format!(
            "write Pi MCP extension asset {}: {error}",
            path.display()
        ))
    })?;
    file.write_all(bytes).map_err(|error| {
        ProviderError::Protocol(format!(
            "write Pi MCP extension asset {}: {error}",
            path.display()
        ))
    })?;
    file.sync_all().map_err(|error| {
        ProviderError::Protocol(format!(
            "flush Pi MCP extension asset {}: {error}",
            path.display()
        ))
    })
}

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

pub(crate) const EXTENSION_SOURCE: &str = include_str!("mcp_extension.js");
const PROCESS_TREE_SOURCE: &str = include_str!("mcp_process_tree.mjs");
const SUPERVISOR_SOURCE: &str = include_str!("mcp_stdio_supervisor.mjs");
const PERMISSION_SOURCE: &str = include_str!("permission_extension.mjs");

#[cfg(test)]
mod tests {
    use super::*;
    use alera_agent_transport::ProcessConfig;
    use alera_provider_protocol::McpServerSpec;
    use std::collections::BTreeMap;

    fn server(transport: McpTransport) -> McpServerSpec {
        McpServerSpec {
            name: "chat-tools".into(),
            transport,
        }
    }

    #[test]
    fn extension_asset_contains_real_pi_and_mcp_boundaries() {
        for marker in [
            "registerTool",
            "session_start",
            "session_shutdown",
            "initialize",
            "notifications/initialized",
            "tools/list",
            "tools/call",
            "notifications/cancelled",
            "signal",
        ] {
            assert!(EXTENSION_SOURCE.contains(marker), "missing {marker}");
        }
        assert!(EXTENSION_SOURCE.contains("process.env[SPEC_FILE_ENV]"));
        assert!(PROCESS_TREE_SOURCE.contains("spawn("));
        assert!(PROCESS_TREE_SOURCE.contains("SIGTERM"));
        assert!(PROCESS_TREE_SOURCE.contains("SIGKILL"));
        assert!(SUPERVISOR_SOURCE.contains("disconnect"));
        assert!(PERMISSION_SOURCE.contains("tool_call"));
        assert!(PERMISSION_SOURCE.contains("block: true"));
    }

    #[test]
    fn private_lease_writes_spec_and_injects_only_paths() {
        let mut env = BTreeMap::new();
        env.insert(
            "ALERA_CHAT_CREDENTIAL_FILE".into(),
            "/private/credential".into(),
        );
        let lease = McpExtensionLease::prepare(&[server(McpTransport::Stdio {
            command: "/opt/alera".into(),
            args: vec!["mcp".into(), "serve".into()],
            env,
            cwd: None,
        })])
        .unwrap()
        .unwrap();
        let mut process = ProcessConfig::default();
        lease.configure(&mut process);
        assert!(process.args.windows(2).any(|pair| {
            pair[0] == "--extension" && pair[1] == lease.extension_path().as_os_str()
        }));
        let spec_path = process
            .env
            .get(std::ffi::OsStr::new("ALERA_PI_MCP_SPEC_FILE"))
            .unwrap();
        assert_eq!(spec_path, lease.spec_path().as_os_str());
        let specs = std::fs::read_to_string(lease.spec_path()).unwrap();
        assert!(specs.contains("ALERA_CHAT_CREDENTIAL_FILE"));
        assert!(specs.contains("/private/credential"));
        let extension_path = lease.extension_path().to_owned();
        let spec_path = lease.spec_path().to_owned();
        let directory = lease.directory.clone();
        assert!(directory.join("mcp_process_tree.mjs").exists());
        assert!(directory.join("mcp_stdio_supervisor.mjs").exists());
        assert!(directory.join("permission_extension.mjs").exists());
        drop(lease);
        assert!(!extension_path.exists());
        assert!(!spec_path.exists());
        assert!(!directory.exists());
    }

    #[test]
    fn default_permission_extension_is_injected_without_mcp_servers() {
        let lease = McpExtensionLease::prepare(&[]).unwrap().unwrap();
        let mut process = ProcessConfig::default();
        lease.configure(&mut process);
        assert!(process.args.windows(2).any(|pair| {
            pair[0] == "--extension" && pair[1] == lease.extension_path().as_os_str()
        }));
        assert_eq!(fs::read_to_string(lease.spec_path()).unwrap(), "[]");
    }

    #[test]
    fn http_servers_are_rejected_before_process_launch() {
        let result = McpExtensionLease::prepare(&[server(McpTransport::Http {
            url: "https://example.invalid/mcp".into(),
            headers: BTreeMap::new(),
        })]);
        assert!(matches!(result, Err(ProviderError::Unsupported(_))));
    }
}
