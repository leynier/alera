//! `alera agent-quota`: the usage limits the app shows for agent providers.

use anyhow::{bail, Result};
use serde_json::{json, Value};

use crate::agent_profile_commands::ensure_capabilities;
use crate::cli::{AgentQuotaAction, AgentQuotaCommand};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY, RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY,
    RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY,
};

/// The app's own limits for each request: provider APIs and the Claude
/// terminal UI can be slow.
const SNAPSHOT_DEADLINE_MS: u64 = 45_000;
const CLAUDE_TUI_DEADLINE_MS: u64 = 60_000;
const CODEX_RESET_DEADLINE_MS: u64 = 45_000;

pub(crate) async fn run(command: AgentQuotaCommand) -> i32 {
    let json_output = command.output.json;
    match run_command(command).await {
        Ok((value, message)) => {
            crate::print_value(&value, json_output, message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn run_command(command: AgentQuotaCommand) -> Result<(Value, &'static str)> {
    let mut client =
        RuntimeHostRpcClient::connect_or_start(&crate::runtime_dir(&command.runtime)).await?;
    let (capability, request_type, payload, deadline, message) = request(&command.action)?;
    ensure_capabilities(&mut client, &[capability]).await?;
    let value = client
        .request_value_with_deadline(request_type, &payload, deadline)
        .await?;
    Ok((value, message))
}

/// The capability, request, payload, deadline, and summary for an action.
pub(crate) fn request(
    action: &AgentQuotaAction,
) -> Result<(&'static str, &'static str, Value, u64, &'static str)> {
    Ok(match action {
        AgentQuotaAction::Show(args) => (
            RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY,
            "agentQuota.snapshot",
            json!({ "forceRefresh": args.refresh }),
            SNAPSHOT_DEADLINE_MS,
            "agent quotas",
        ),
        AgentQuotaAction::RefreshClaude(args) => {
            let account_id = args.account_id.trim();
            if account_id.is_empty() {
                bail!("--account-id cannot be empty");
            }
            (
                RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY,
                "agentQuota.fetchClaudeTui",
                json!({ "accountId": account_id }),
                CLAUDE_TUI_DEADLINE_MS,
                "Claude quota refreshed",
            )
        }
        AgentQuotaAction::ConsumeCodexReset(args) => {
            let revision = args.offer_revision.trim();
            if revision.is_empty() {
                bail!("--offer-revision cannot be empty");
            }
            (
                RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY,
                "agentQuota.consumeCodexResetCredit",
                json!({ "offerRevision": revision }),
                CODEX_RESET_DEADLINE_MS,
                "Codex reset credit requested",
            )
        }
    })
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::request;
    use crate::cli::{
        AgentQuotaAction, AgentQuotaClaudeArgs, AgentQuotaCodexResetArgs, AgentQuotaShowArgs,
    };

    #[test]
    fn each_action_sends_the_app_payload() {
        let (_, kind, payload, _, _) = request(&AgentQuotaAction::Show(AgentQuotaShowArgs {
            refresh: true,
        }))
        .unwrap();
        assert_eq!(kind, "agentQuota.snapshot");
        assert_eq!(payload, json!({ "forceRefresh": true }));
        let (_, kind, payload, _, _) =
            request(&AgentQuotaAction::RefreshClaude(AgentQuotaClaudeArgs {
                account_id: " work ".into(),
            }))
            .unwrap();
        assert_eq!(kind, "agentQuota.fetchClaudeTui");
        assert_eq!(payload, json!({ "accountId": "work" }));
        let (_, kind, payload, _, _) = request(&AgentQuotaAction::ConsumeCodexReset(
            AgentQuotaCodexResetArgs {
                offer_revision: "rev-7".into(),
            },
        ))
        .unwrap();
        assert_eq!(kind, "agentQuota.consumeCodexResetCredit");
        assert_eq!(payload, json!({ "offerRevision": "rev-7" }));
    }

    #[test]
    fn blank_identifiers_are_refused() {
        assert!(request(&AgentQuotaAction::ConsumeCodexReset(
            AgentQuotaCodexResetArgs {
                offer_revision: " ".into(),
            }
        ))
        .is_err());
        assert!(
            request(&AgentQuotaAction::RefreshClaude(AgentQuotaClaudeArgs {
                account_id: String::new(),
            }))
            .is_err()
        );
    }
}
