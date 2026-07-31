use gpui::{
    div, AnyElement, Context, InteractiveElement as _, IntoElement as _, ParentElement as _,
    SharedString, StatefulInteractiveElement as _, Styled as _,
};
use serde_json::{json, Value};
use std::time::Duration;

use crate::activity::Activity;
use crate::runtime_bridge::RuntimeBridge;
use crate::theme;

use super::AleraApp;
#[derive(Clone, Debug, Default)]
pub struct RuntimeFeatureState {
    pub activity: Activity,
    pub loading: bool,
    pub generation: u64,
    pub sections: Vec<FeatureSection>,
    pub error: Option<String>,
}

#[derive(Clone, Debug)]
pub struct FeatureSection {
    pub title: String,
    pub value: Value,
}

pub struct FeatureContext {
    pub workspace_id: Option<String>,
    pub project_id: Option<String>,
}

impl AleraApp {
    pub(super) fn refresh_runtime_feature(&mut self, cx: &mut Context<Self>) {
        if !self.activity.uses_runtime_catalog() {
            return;
        }
        self.runtime_feature.generation += 1;
        self.runtime_feature.activity = self.activity;
        self.runtime_feature.loading = true;
        self.runtime_feature.error = None;
        let generation = self.runtime_feature.generation;
        let activity = self.activity;
        let bridge = self.bridge.clone();
        let feature_context = self.feature_context();
        cx.spawn(async move |this, cx| {
            let result = load_feature(activity, &bridge, feature_context).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.runtime_feature.generation {
                    return;
                }
                this.runtime_feature.loading = false;
                match result {
                    Ok(sections) => {
                        this.runtime_feature.sections = sections;
                        this.runtime_feature.error = None;
                    }
                    Err(error) => this.runtime_feature.error = Some(error),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn feature_context(&self) -> FeatureContext {
        let workspace = self
            .selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.workspace(id));
        FeatureContext {
            workspace_id: workspace.map(|item| item.id.clone()),
            project_id: workspace.map(|item| item.project_id.clone()),
        }
    }

    pub(super) fn render_runtime_feature(&self, cx: &mut Context<Self>) -> AnyElement {
        let state = &self.runtime_feature;
        let mut cards = Vec::new();
        if state.loading {
            cards.push(
                feature_card("Loading", "Reading Live Runtime State")
                    .id("feature-loading")
                    .into_any_element(),
            );
        }
        if let Some(error) = &state.error {
            cards.push(
                feature_card("Unavailable", error.clone())
                    .id("feature-error")
                    .into_any_element(),
            );
        }
        cards.extend(state.sections.iter().enumerate().map(|(index, section)| {
            feature_card(&section.title, pretty_value(&section.value))
                .id(("feature-section", index))
                .into_any_element()
        }));
        div()
            .id("runtime-feature-scroll")
            .flex()
            .flex_col()
            .flex_1()
            .overflow_y_scroll()
            .p_5()
            .gap_3()
            .child(
                div()
                    .text_2xl()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child(state.activity.label()),
            )
            .child(self.render_runtime_action_console(cx))
            .children(cards)
            .into_any_element()
    }
}

async fn load_feature(
    activity: Activity,
    bridge: &RuntimeBridge,
    context: FeatureContext,
) -> Result<Vec<FeatureSection>, String> {
    let requests = requests_for(activity, &context);
    let mut sections = Vec::with_capacity(requests.len());
    for request in requests {
        let deadline = if request.verb == "agentQuota.snapshot" {
            Duration::from_secs(30)
        } else {
            Duration::from_secs(3)
        };
        let value = bridge
            .request_with_timeout(request.verb, request.payload, deadline)
            .await
            .map_err(|error| format!("{}: {error}", request.title))?;
        sections.push(FeatureSection {
            title: request.title.to_string(),
            value,
        });
    }
    Ok(sections)
}

struct FeatureRequest {
    title: &'static str,
    verb: &'static str,
    payload: Value,
}

fn requests_for(activity: Activity, context: &FeatureContext) -> Vec<FeatureRequest> {
    let workspace_id = context.workspace_id.clone().unwrap_or_default();
    let project_id = context.project_id.clone().unwrap_or_default();
    match activity {
        Activity::PullRequests => vec![
            request(
                "Linked Review",
                "linkedReview.find",
                json!({"workspaceId": workspace_id}),
            ),
            request(
                "Repository",
                "workspace.repositoryWebUrl",
                json!({"workspaceId": workspace_id}),
            ),
        ],
        Activity::AiText => vec![request(
            "Generation Settings",
            "runtimeSettings.get",
            json!({}),
        )],
        Activity::Agents => vec![
            request("Profiles", "agentProfile.list", json!({})),
            request("Quotas", "agentQuota.snapshot", json!({})),
            request("Presence", "agentPresence.list", json!({})),
        ],
        Activity::Resources => vec![request(
            "Processes",
            "resources.snapshot",
            json!({"appPid": std::process::id()}),
        )],
        Activity::Orchestration => vec![
            request(
                "Runs",
                "orchestration.runList",
                json!({"workspace": workspace_id}),
            ),
            request(
                "Tasks",
                "orchestration.taskList",
                json!({"workspace": workspace_id}),
            ),
            request("Gates", "orchestration.gateList", json!({})),
            request(
                "Terminals",
                "orchestration.terminals",
                json!({"workspace": workspace_id}),
            ),
        ],
        Activity::Settings => vec![
            request("Runtime", "runtimeSettings.get", json!({})),
            request("Workbench", "workbenchViewPrefs.get", json!({})),
            request(
                "Project",
                "projectConfig.effective",
                json!({"projectId": project_id}),
            ),
        ],
        Activity::Devices => vec![
            request("Status", "mobile.status.get", json!({})),
            request("Devices", "mobile.device.list", json!({})),
            request("Runtime Settings", "mobile.runtimeSettings.get", json!({})),
        ],
        Activity::Diagnostics => vec![
            request("Runtime Host", "status.get", json!({})),
            request("CLI Registration", "cliRegistration.status", json!({})),
        ],
        _ => Vec::new(),
    }
}

fn request(title: &'static str, verb: &'static str, payload: Value) -> FeatureRequest {
    FeatureRequest {
        title,
        verb,
        payload,
    }
}

fn pretty_value(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
}

fn feature_card(title: impl Into<SharedString>, body: impl Into<SharedString>) -> gpui::Div {
    div()
        .rounded_lg()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface())
        .p_4()
        .child(
            div()
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(title.into()),
        )
        .child(
            div()
                .mt_2()
                .font_family("JetBrains Mono")
                .text_sm()
                .text_color(theme::text_muted())
                .child(body.into()),
        )
}
