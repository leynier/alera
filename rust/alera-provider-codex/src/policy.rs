use alera_provider_protocol::{ApprovalPolicy, RuntimeMode, SandboxMode};
use serde_json::{json, Value};

pub(crate) struct RuntimeDefaults {
    pub approval_policy: ApprovalPolicy,
    pub sandbox_mode: SandboxMode,
    pub approvals_reviewer: &'static str,
}

pub(crate) fn runtime_defaults(mode: RuntimeMode) -> RuntimeDefaults {
    match mode {
        RuntimeMode::ApprovalRequired => RuntimeDefaults {
            approval_policy: ApprovalPolicy::Untrusted,
            sandbox_mode: SandboxMode::ReadOnly,
            approvals_reviewer: "user",
        },
        RuntimeMode::AutoAcceptEdits => RuntimeDefaults {
            approval_policy: ApprovalPolicy::OnRequest,
            sandbox_mode: SandboxMode::WorkspaceWrite,
            approvals_reviewer: "user",
        },
        RuntimeMode::Auto => RuntimeDefaults {
            approval_policy: ApprovalPolicy::OnRequest,
            sandbox_mode: SandboxMode::WorkspaceWrite,
            approvals_reviewer: "auto_review",
        },
        RuntimeMode::FullAccess => RuntimeDefaults {
            approval_policy: ApprovalPolicy::Never,
            sandbox_mode: SandboxMode::DangerFullAccess,
            approvals_reviewer: "user",
        },
    }
}

pub(crate) fn sandbox_policy(mode: SandboxMode) -> Value {
    let kind = match mode {
        SandboxMode::ReadOnly => "readOnly",
        SandboxMode::WorkspaceWrite => "workspaceWrite",
        SandboxMode::DangerFullAccess => "dangerFullAccess",
    };
    json!({ "type": kind })
}
