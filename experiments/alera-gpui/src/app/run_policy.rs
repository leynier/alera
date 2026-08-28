use gpui::{Context, Window};
use serde_json::{json, Value};

use super::keyboard_actions::OpenExecutionPlans;
use super::AleraApp;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum RunPolicyStatus {
    #[default]
    None,
    Draft,
    Approved,
    Rejected,
}

impl RunPolicyStatus {
    fn parse(value: Option<&str>) -> Self {
        match value {
            Some("draft") => Self::Draft,
            Some("approved") => Self::Approved,
            Some("rejected") => Self::Rejected,
            _ => Self::None,
        }
    }

    pub(super) const fn label(self) -> &'static str {
        match self {
            Self::None => "No Plan",
            Self::Draft => "Awaiting Approval",
            Self::Approved => "Approved",
            Self::Rejected => "Rejected",
        }
    }

    pub(super) const fn is_pending(self) -> bool {
        matches!(self, Self::Draft)
    }
}

#[derive(Clone, Debug)]
pub(super) struct RunPolicyStage {
    pub id: String,
    pub profile: String,
    pub title: Option<String>,
    pub fallbacks: Vec<String>,
}

impl RunPolicyStage {
    pub(super) fn label(&self) -> &str {
        self.title
            .as_deref()
            .map(str::trim)
            .filter(|title| !title.is_empty())
            .unwrap_or(&self.id)
    }
}

#[derive(Clone, Debug)]
pub(super) struct RunExecutionPolicy {
    pub run_id: String,
    pub status: RunPolicyStatus,
    pub blocks_dispatch: bool,
    pub stages: Vec<RunPolicyStage>,
    pub stall_policy: String,
}

impl RunExecutionPolicy {
    fn parse(value: &Value) -> Self {
        let policy = value.get("policy");
        let stages = policy
            .and_then(|policy| policy.get("stages"))
            .and_then(Value::as_array)
            .map(|stages| {
                stages
                    .iter()
                    .filter_map(|stage| {
                        let id = stage.get("id")?.as_str()?.to_owned();
                        Some(RunPolicyStage {
                            id,
                            profile: stage
                                .get("profile")
                                .and_then(Value::as_str)
                                .unwrap_or_default()
                                .to_owned(),
                            title: stage
                                .get("title")
                                .and_then(Value::as_str)
                                .map(str::to_owned),
                            fallbacks: stage
                                .get("fallbacks")
                                .and_then(Value::as_array)
                                .into_iter()
                                .flatten()
                                .filter_map(Value::as_str)
                                .map(str::to_owned)
                                .collect(),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        Self {
            run_id: value
                .get("runId")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned(),
            status: RunPolicyStatus::parse(value.get("status").and_then(Value::as_str)),
            blocks_dispatch: value
                .get("blocksDispatch")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            stages,
            stall_policy: policy
                .and_then(|policy| policy.get("stallPolicy"))
                .and_then(Value::as_str)
                .unwrap_or("ask")
                .to_owned(),
        }
    }

    fn has_policy(&self) -> bool {
        self.status != RunPolicyStatus::None
    }
}

impl AleraApp {
    pub(super) fn on_open_execution_plans(
        &mut self,
        _: &OpenExecutionPlans,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.open_execution_plans(window, cx);
    }

    pub(crate) fn open_execution_plans(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.show_execution_plans = true;
        self.run_policy_error = None;
        self.run_policy_reason_input.update(cx, |input, cx| {
            input.set_value("", window, cx);
        });
        self.load_execution_plans(cx);
    }

    pub(crate) fn open_execution_plans_from_menu(&mut self, cx: &mut Context<Self>) {
        self.show_execution_plans = true;
        self.run_policy_error = None;
        self.load_execution_plans(cx);
    }

    pub(super) fn close_execution_plans(&mut self, cx: &mut Context<Self>) {
        self.show_execution_plans = false;
        self.run_policy_error = None;
        cx.notify();
    }

    pub(super) fn load_execution_plans(&mut self, cx: &mut Context<Self>) {
        self.run_policies_loading = true;
        self.run_policy_error = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = async {
                let runs = bridge.request("orchestration.runList", json!({})).await?;
                let items = runs
                    .get("items")
                    .or_else(|| runs.get("runs"))
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                let mut policies = Vec::new();
                for run in items {
                    let Some(run_id) = run.get("id").and_then(Value::as_str) else {
                        continue;
                    };
                    let payload = bridge
                        .request("orchestration.runPolicyShow", json!({"run": run_id}))
                        .await?;
                    let policy = RunExecutionPolicy::parse(&payload);
                    if policy.has_policy() {
                        policies.push(policy);
                    }
                }
                Ok::<_, String>(policies)
            }
            .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.run_policies_loading = false;
                match result {
                    Ok(policies) => this.run_policies = policies,
                    Err(error) => {
                        // Flutter's AsyncError has no stale data. Clearing the
                        // previous list keeps a failed refresh from showing an
                        // obsolete plan underneath the error state.
                        this.run_policies.clear();
                        self::set_policy_error(this, error);
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn decide_run_policy(
        &mut self,
        run_id: String,
        approve: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.run_policy_busy_id.is_some() {
            return;
        }
        let reason = self
            .run_policy_reason_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        if !approve && reason.is_empty() {
            self.run_policy_error = Some("A rejection needs a reason.".into());
            cx.notify();
            return;
        }
        self.run_policy_busy_id = Some(run_id.clone());
        self.run_policy_error = None;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = if approve {
                bridge
                    .request(
                        "orchestration.runPolicyApprove",
                        json!({"run": run_id, "actor": "app"}),
                    )
                    .await
            } else {
                bridge
                    .request(
                        "orchestration.runPolicyReject",
                        json!({"run": run_id, "reason": reason, "actor": "app"}),
                    )
                    .await
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                this.run_policy_busy_id = None;
                match result {
                    Ok(_) => {
                        this.run_policy_reason_input.update(cx, |input, cx| {
                            input.set_value("", window, cx);
                        });
                        this.load_execution_plans(cx);
                    }
                    Err(error) => {
                        self::set_policy_error(this, error);
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }
}

fn set_policy_error(app: &mut AleraApp, error: String) {
    app.run_policy_error = Some(error.into());
}

#[cfg(test)]
mod tests {
    use super::{RunExecutionPolicy, RunPolicyStage, RunPolicyStatus};
    use serde_json::json;

    #[test]
    fn parses_flutter_policy_metadata_and_trims_stage_titles() {
        let policy = RunExecutionPolicy::parse(&json!({
            "runId": "run-1",
            "workspaceId": "workspace-1",
            "status": "draft",
            "blocksDispatch": true,
            "updatedAt": "2026-08-25T13:00:00Z",
            "policy": {
                "stallPolicy": "auto-failover",
                "stages": [{
                    "id": "implement",
                    "title": "  Implement  ",
                    "profile": "Codex",
                    "fallbacks": ["Claude"]
                }]
            }
        }));

        assert_eq!(policy.run_id, "run-1");
        assert_eq!(policy.status, RunPolicyStatus::Draft);
        assert!(policy.blocks_dispatch);
        assert_eq!(policy.stall_policy, "auto-failover");
        assert_eq!(policy.stages[0].label(), "Implement");
        assert_eq!(policy.stages[0].fallbacks, ["Claude"]);
    }

    #[test]
    fn stage_without_title_uses_id_and_rejects_blank_title() {
        let blank = RunPolicyStage {
            id: "review".to_string(),
            profile: "Codex".to_string(),
            title: Some("  ".to_string()),
            fallbacks: Vec::new(),
        };
        let absent = RunPolicyStage {
            id: "test".to_string(),
            profile: "Codex".to_string(),
            title: None,
            fallbacks: Vec::new(),
        };

        assert_eq!(blank.label(), "review");
        assert_eq!(absent.label(), "test");
    }
}
