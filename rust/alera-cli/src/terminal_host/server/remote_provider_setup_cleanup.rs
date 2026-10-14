use super::*;
use crate::terminal_host::host_link::HostLink;
use crate::terminal_host::host_link_registry::HostLinkRegistry;

pub(crate) fn spawn_cleanup_on_link(link: Arc<HostLink>, cleanup: SetupCleanup) {
    tokio::spawn(async move {
        terminate_on_link(link, cleanup, false).await;
    });
}

pub(crate) async fn forward_setup_request(
    links: HostLinkRegistry,
    host_id: String,
    mut envelope: Value,
    deadline: std::time::Duration,
) -> HostResult<Value> {
    let desktop_id = envelope["desktopClientId"]
        .as_u64()
        .expect("forwarded desktop identity");
    let session_id = require_string_key(&envelope["payload"], "sessionId")?;
    let lease_id = require_string_key(&envelope, "desktopLeaseId")?;
    let spawning = matches!(
        envelope["type"].as_str(),
        Some("createOrAttach" | "terminal.restart")
    );
    let cleanup = SetupCleanup {
        host_id: host_id.clone(),
        session_id: session_id.clone(),
        selection: ProviderSetupContext::from_json(&envelope["providerSetup"])?,
        desktop_client_id: desktop_id,
        lease_id: lease_id.clone(),
    };
    if spawning
        && !links
            .provider_setup_sessions
            .lease_is_current(&session_id, desktop_id, &lease_id)
    {
        return Err(not_allowed());
    }
    let close = matches!(envelope["type"].as_str(), Some("detach" | "terminate"));
    let retired = if close {
        links
            .provider_setup_sessions
            .release(&session_id, desktop_id)
    } else {
        None
    };
    if close {
        envelope["type"] = json!("terminate");
    }
    let link = links.link(&host_id).await?;
    if spawning
        && !links
            .provider_setup_sessions
            .lease_is_current(&session_id, desktop_id, &lease_id)
    {
        return Err(not_allowed());
    }
    if !link
        .attachment()
        .runtime_capabilities
        .iter()
        .any(|capability| capability == REMOTE_SETUP_CAPABILITY)
    {
        links
            .provider_setup_sessions
            .release(&session_id, desktop_id);
        return Err(HostError::conflict(
            "unsupported",
            "The remote host does not support provider setup terminals.",
            json!({}),
        ));
    }
    let attaching = envelope["type"] == "createOrAttach";
    let result = link
        .request_with_timeout(INTERNAL_SETUP_REQUEST, envelope, deadline)
        .await;
    if spawning
        && !links
            .provider_setup_sessions
            .lease_is_current(&session_id, desktop_id, &lease_id)
    {
        terminate_on_link(link, cleanup, false).await;
        return match result {
            Ok(_) => Err(not_allowed()),
            Err(error) => Err(error),
        };
    }
    if result.is_err() {
        if let Some(cleanup) = retired {
            spawn_cleanup_on_link(link, cleanup);
        } else if attaching
            && matches!(
                result,
                Err(HostError::Conflict { .. } | HostError::Format(_))
            )
        {
            if let Some(cleanup) = links
                .provider_setup_sessions
                .release(&session_id, desktop_id)
            {
                spawn_cleanup_on_link(link, cleanup);
            }
        }
    }
    links.reevaluate();
    result
}

async fn terminate_on_link(link: Arc<HostLink>, cleanup: SetupCleanup, force: bool) {
    if link
        .request_with_timeout(
            INTERNAL_SETUP_REQUEST,
            cleanup.envelope(force),
            std::time::Duration::from_secs(5),
        )
        .await
        .is_err()
    {
        tracing::warn!(target: "host_link", host_id = cleanup.host_id, "could not confirm provider setup terminal closure");
    }
}

pub(crate) async fn close_removed_host_setups(link: Arc<HostLink>, cleanups: Vec<SetupCleanup>) {
    let mut jobs = tokio::task::JoinSet::new();
    for cleanup in cleanups {
        jobs.spawn(terminate_on_link(link.clone(), cleanup, true));
    }
    let _ = tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while jobs.join_next().await.is_some() {}
    })
    .await;
    jobs.abort_all();
}

impl ServerActor {
    pub(in crate::terminal_host::server) fn cleanup_remote_provider_setup_client(
        &self,
        client_id: u64,
    ) {
        for cleanup in self
            .host_links
            .provider_setup_sessions
            .forget_client(client_id)
        {
            let links: HostLinkRegistry = self.host_links.clone();
            tokio::spawn(async move {
                let result = tokio::time::timeout(std::time::Duration::from_secs(10), async {
                    let link = links.link(&cleanup.host_id).await?;
                    link.request_with_timeout(
                        INTERNAL_SETUP_REQUEST,
                        cleanup.envelope(false),
                        std::time::Duration::from_secs(5),
                    )
                    .await
                })
                .await;
                if !matches!(result, Ok(Ok(_))) {
                    tracing::warn!(target: "host_link", host_id = cleanup.host_id, "could not confirm disconnected provider setup terminal closure");
                }
            });
        }
        self.host_links.reevaluate();
    }
}
