use futures_util::future::{BoxFuture, FutureExt, Shared};
use serde_json::json;

use super::codex_app_server::CodexAppServer;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

pub(super) type CodexServerStartup = Shared<BoxFuture<'static, HostResult<CodexAppServer>>>;

impl ServerActor {
    pub(super) async fn ensure_codex_server(
        &mut self,
        cwd: Option<&str>,
    ) -> HostResult<CodexAppServer> {
        if let Some(server) = self.codex.as_ref() {
            return Ok(server.clone());
        }
        let startup = self.codex_server_startup(cwd);
        let result = startup.clone().await;
        self.adopt_codex_startup(&startup, result)
    }

    pub(super) fn codex_server_startup(&mut self, cwd: Option<&str>) -> CodexServerStartup {
        if let Some(server) = self.codex.clone() {
            return async move { Ok(server) }.boxed().shared();
        }
        if let Some(startup) = &self.codex_starting {
            return startup.clone();
        }
        let inbox = self.inbox.clone();
        let cwd = cwd.map(str::to_string);
        let startup = async move {
            tokio::time::timeout(
                std::time::Duration::from_secs(90),
                CodexAppServer::start(inbox, cwd.as_deref()),
            )
            .await
            .unwrap_or_else(|_| Err(HostError::state("Codex app-server startup timed out.")))
        }
        .boxed()
        .shared();
        self.codex_starting = Some(startup.clone());
        startup
    }

    pub(super) fn adopt_codex_startup(
        &mut self,
        startup: &CodexServerStartup,
        result: HostResult<CodexAppServer>,
    ) -> HostResult<CodexAppServer> {
        if let Some(current) = &self.codex {
            return match result {
                Ok(server) if current.matches_instance(&server.instance_token()) => {
                    Ok(current.clone())
                }
                _ => Err(HostError::state(
                    "The Codex process changed during recovery.",
                )),
            };
        }
        if !self
            .codex_starting
            .as_ref()
            .is_some_and(|pending| pending.ptr_eq(startup))
        {
            return Err(HostError::state(
                "The Codex process changed during recovery.",
            ));
        }
        self.codex_starting = None;
        let server = result?;
        self.codex = Some(server.clone());
        self.broadcast_authenticated(event("codexServerChanged", json!({"status":"ready"})));
        Ok(server)
    }
}
