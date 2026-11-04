//! The skills behind `agentChat.skills`. A live session's own report wins,
//! because it reflects exactly what that process loaded; before a session the
//! factory discovers them the way T3 Code's provider probes do.

use std::path::PathBuf;

use alera_provider_protocol::ProviderSkill;
use serde_json::{json, Value};

use super::session::ChatSession;

impl ChatSession {
    pub(super) fn skill_source(&self) -> Value {
        let unselected =
            self.header.provider == alera_core::runtime::AGENT_CHAT_UNSELECTED_PROVIDER;
        json!({
            "provider": (!unselected).then_some(&self.header.provider),
            "providerInstanceId": (!unselected).then_some(&self.header.provider_instance_id),
            "cwd": self.header.session.cwd,
            "sessionSkills": self.provider_skills,
        })
    }
}

/// The `agentChat.skills` answer. `status` is `ready` when `skills` is the
/// agent's list, `pending` when the agent only reports skills once its
/// session starts, and `failed` when discovery did not answer.
pub(super) fn skills_response(
    source: &Value,
    resolve: impl FnOnce() -> Option<Result<Vec<ProviderSkill>, String>>,
) -> Value {
    let identity = json!({
        "provider": source["provider"],
        "providerInstanceId": source["providerInstanceId"],
    });
    let mut response = identity;
    if let Ok(skills) =
        serde_json::from_value::<Vec<ProviderSkill>>(source["sessionSkills"].clone())
    {
        response["skills"] = json!(skills);
        response["source"] = json!("session");
        response["status"] = json!("ready");
        return response;
    }
    match resolve() {
        Some(Ok(skills)) => {
            response["skills"] = json!(skills);
            response["source"] = json!("discovery");
            response["status"] = json!("ready");
        }
        Some(Err(error)) => {
            response["skills"] = json!([]);
            response["status"] = json!("failed");
            response["error"] = json!(error);
        }
        None => {
            response["skills"] = json!([]);
            response["status"] = json!("pending");
        }
    }
    response
}

pub(super) fn skill_source_cwd(source: &Value) -> Option<PathBuf> {
    source["cwd"].as_str().map(PathBuf::from)
}
