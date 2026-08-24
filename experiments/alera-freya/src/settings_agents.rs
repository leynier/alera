use std::collections::BTreeMap;
use std::time::Duration;

use crate::{MUTED, TEXT, dialog_select, settings_group_described, settings_row_shell};
use alera_desktop_core::RuntimeBridge;
use freya::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

mod actions;
mod components;

use actions::{install_skill, persist_behavior, run_request, update_hook};
use components::{loading_row, toggle_control};

const BEHAVIOR_KEY: &str = "freya.settings.agentBehavior";
const AGENTS: [(&str, &str); 9] = [
    ("codex", "Codex Hooks"),
    ("claude", "Claude Code Hooks"),
    ("copilot", "GitHub Copilot Hooks"),
    ("cursor", "Cursor Hooks"),
    ("agy", "Antigravity Hooks"),
    ("opencode", "OpenCode Hooks"),
    ("pi", "Pi Hooks"),
    ("amp", "Amp Hooks"),
    ("grok", "Grok Build Hooks"),
];

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase")]
struct CliRegistrationStatus {
    state: String,
    ready: bool,
    path_configured: bool,
    command_path: Option<String>,
    detail: String,
}

impl CliRegistrationStatus {
    fn label(&self) -> &'static str {
        match self.state.as_str() {
            "installed" if self.ready => "Registered",
            "installed" if !self.path_configured => "Registered, Add To PATH",
            "installed" => "Registered",
            "notInstalled" => "Not Registered",
            "stale" => "Registration Needs Update",
            "conflict" => "Registration Conflict",
            "unsupported" => "Registration Unsupported",
            _ => "Registration Status Unknown",
        }
    }

    fn blocks_install(&self) -> bool {
        matches!(self.state.as_str(), "conflict" | "unsupported")
    }
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(default, rename_all = "camelCase")]
struct AgentBehavior {
    notifications_enabled: bool,
    finished_notifications_enabled: bool,
    keep_awake: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
struct AgentSettingsSnapshot {
    cli: CliRegistrationStatus,
    hooks: BTreeMap<String, bool>,
    behavior: AgentBehavior,
}

#[derive(Clone, Copy)]
struct AgentSignals {
    busy: State<bool>,
    message: State<Option<String>>,
    revision: State<u64>,
}

pub fn content(active: bool, bridge: RuntimeBridge) -> Element {
    let snapshot = use_state(|| None::<Result<AgentSettingsSnapshot, String>>);
    let revision = use_state(|| 0_u64);
    let busy = use_state(|| false);
    let message = use_state(|| None::<String>);
    let runner_all = use_state(|| "Auto".to_string());
    let runner_cli = use_state(|| "Auto".to_string());
    let runner_orchestration = use_state(|| "Auto".to_string());
    let runner_computer = use_state(|| "Auto".to_string());
    let runner_emulator = use_state(|| "Auto".to_string());
    let open_runner_menu = use_state(|| None::<String>);
    let runner_just_opened = use_state(|| false);
    let signals = AgentSignals {
        busy,
        message,
        revision,
    };

    let deps = (active, *revision.read());
    let bridge_for_load = bridge.clone();
    let mut snapshot_for_load = snapshot;
    use_side_effect_with_deps(&deps, move |(active, _)| {
        if !*active {
            return;
        }
        let bridge = bridge_for_load.clone();
        spawn(async move {
            snapshot_for_load.set(Some(load_snapshot(bridge).await));
        });
    });

    let body = match snapshot.read().as_ref() {
        None => loading_row("Loading Agent Settings"),
        Some(Err(error)) => loading_row(error),
        Some(Ok(value)) => render_snapshot(
            value.clone(),
            bridge,
            signals,
            [
                runner_all,
                runner_cli,
                runner_orchestration,
                runner_computer,
                runner_emulator,
            ],
            open_runner_menu,
            runner_just_opened,
        ),
    };
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(10.)
        .child(body)
        .maybe_child(
            message
                .read()
                .clone()
                .map(|value| label().font_size(10.).color(MUTED).max_lines(4).text(value)),
        )
        .into_element()
}

async fn load_snapshot(bridge: RuntimeBridge) -> Result<AgentSettingsSnapshot, String> {
    let runtime_settings = bridge
        .request_with_timeout("runtimeSettings.get", json!({}), Duration::from_secs(10))
        .await?;
    let cli = bridge
        .request_with_timeout("cliRegistration.status", json!({}), Duration::from_secs(15))
        .await
        .and_then(|value| serde_json::from_value(value).map_err(|error| error.to_string()))?;
    let behavior_value = bridge
        .request_with_timeout(
            "runtimeMetadata.get",
            json!({"key": BEHAVIOR_KEY}),
            Duration::from_secs(10),
        )
        .await?;
    let behavior = behavior_value
        .as_str()
        .and_then(|value| serde_json::from_str(value).ok())
        .unwrap_or_default();
    let hooks = runtime_settings
        .get("agentStatusHooks")
        .and_then(Value::as_object)
        .into_iter()
        .flatten()
        .filter_map(|(name, enabled)| enabled.as_bool().map(|value| (name.clone(), value)))
        .collect();
    Ok(AgentSettingsSnapshot {
        cli,
        hooks,
        behavior,
    })
}

fn render_snapshot(
    snapshot: AgentSettingsSnapshot,
    bridge: RuntimeBridge,
    signals: AgentSignals,
    runners: [State<String>; 5],
    open_menu: State<Option<String>>,
    just_opened: State<bool>,
) -> Element {
    let bridge_for_cli_refresh = bridge.clone();
    let bridge_for_cli_install = bridge.clone();
    let cli_blocked = snapshot.cli.blocks_install();
    let cli_status = format!(
        "{}{}",
        snapshot.cli.label(),
        snapshot
            .cli
            .command_path
            .as_deref()
            .map(|path| format!(" - {path}"))
            .unwrap_or_default()
    );
    let cli_group = settings_group_described(
        "Alera CLI And Skills",
        "Register the CLI command and install agent instructions.",
        vec![
            settings_row_shell(
                "Alera CLI Command",
                "Register the Alera command on PATH for terminals and agents.",
            )
            .child(
                rect()
                    .vertical()
                    .cross_align(Alignment::End)
                    .spacing(5.)
                    .child(label().font_size(10.).color(TEXT).text(cli_status))
                    .child(
                        rect()
                            .horizontal()
                            .spacing(6.)
                            .child(
                                Button::new()
                                    .compact()
                                    .outline()
                                    .on_press(move |_| {
                                        run_request(
                                            bridge_for_cli_refresh.clone(),
                                            "cliRegistration.status",
                                            json!({}),
                                            "CLI Registration Refreshed",
                                            signals,
                                        )
                                    })
                                    .child("Refresh"),
                            )
                            .child(
                                Button::new()
                                    .compact()
                                    .filled()
                                    .on_press(move |_| {
                                        if !cli_blocked {
                                            run_request(
                                                bridge_for_cli_install.clone(),
                                                "cliRegistration.install",
                                                json!({}),
                                                "CLI Registration Updated",
                                                signals,
                                            );
                                        }
                                    })
                                    .child("Register"),
                            ),
                    ),
            )
            .into_element(),
            skill_row(
                "All Alera Skills",
                "Install or update CLI, Orchestration, Computer Use and Emulator skills.",
                "all",
                runners[0],
                open_menu,
                just_opened,
                bridge.clone(),
                signals,
            ),
            skill_row(
                "Alera CLI Skill",
                "Teach agents to operate projects and workspaces with the Alera CLI.",
                "cli",
                runners[1],
                open_menu,
                just_opened,
                bridge.clone(),
                signals,
            ),
            skill_row(
                "Alera Orchestration Skill",
                "Install the protocol-v2 orchestration instructions.",
                "orchestration",
                runners[2],
                open_menu,
                just_opened,
                bridge.clone(),
                signals,
            ),
            skill_row(
                "Alera Computer Use Skill",
                "Install desktop accessibility and interaction instructions.",
                "computer-use",
                runners[3],
                open_menu,
                just_opened,
                bridge.clone(),
                signals,
            ),
            skill_row(
                "Alera Emulator Skill",
                "Install Android and iOS emulator automation instructions.",
                "emulator",
                runners[4],
                open_menu,
                just_opened,
                bridge.clone(),
                signals,
            ),
        ],
    );

    let mut hook_rows = Vec::new();
    for (agent, title) in AGENTS {
        let enabled = snapshot.hooks.get(agent).copied().unwrap_or(false);
        let hooks = snapshot.hooks.clone();
        let bridge = bridge.clone();
        hook_rows.push(
            settings_row_shell(
                title,
                "Use Alera-managed status integration for this agent.",
            )
            .child(toggle_control(enabled, move || {
                update_hook(bridge.clone(), hooks.clone(), agent, !enabled, signals)
            }))
            .into_element(),
        );
    }
    let hooks_group = settings_group_described(
        "Status Hooks",
        "Managed hooks let terminal tabs show agent state.",
        hook_rows,
    );

    let behavior = snapshot.behavior.clone();
    let behavior_for_notifications = behavior.clone();
    let behavior_for_finished = behavior.clone();
    let behavior_for_awake = behavior.clone();
    let behavior_group = settings_group_described(
        "Behavior",
        "How Alera reacts while agents are running.",
        vec![
            behavior_row(
                "Agent Status Notifications",
                "Show native notifications when an agent needs attention.",
                behavior.notifications_enabled,
                bridge.clone(),
                behavior_for_notifications,
                |value| value.notifications_enabled = !value.notifications_enabled,
                signals,
            ),
            behavior_row(
                "Agent Finished Notifications",
                "Also notify when an agent reports the end of a turn.",
                behavior.finished_notifications_enabled,
                bridge.clone(),
                behavior_for_finished,
                |value| {
                    value.finished_notifications_enabled = !value.finished_notifications_enabled
                },
                signals,
            ),
            behavior_row(
                "Keep Computer Awake While Agents Are Working",
                "Keep this computer and display awake while agents are working.",
                behavior.keep_awake,
                bridge,
                behavior_for_awake,
                |value| value.keep_awake = !value.keep_awake,
                signals,
            ),
        ],
    );
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(12.)
        .child(cli_group)
        .child(hooks_group)
        .child(behavior_group)
        .maybe_child((*signals.busy.read()).then(|| {
            rect()
                .horizontal()
                .spacing(6.)
                .child(CircularLoader::new().size(12.))
                .child(label().font_size(10.).color(MUTED).text("Working"))
        }))
        .into_element()
}

#[allow(clippy::too_many_arguments)]
fn skill_row(
    title: &'static str,
    description: &'static str,
    skill: &'static str,
    runner: State<String>,
    open_menu: State<Option<String>>,
    just_opened: State<bool>,
    bridge: RuntimeBridge,
    signals: AgentSignals,
) -> Element {
    settings_row_shell(title, description)
        .child(rect().width(Size::px(150.)).child(dialog_select(
            skill,
            runner,
            open_menu,
            just_opened,
            ["Auto", "npx", "bunx"],
        )))
        .child(
            Button::new()
                .compact()
                .outline()
                .on_press(move |_| {
                    install_skill(bridge.clone(), skill, runner.read().clone(), signals)
                })
                .child(if skill == "all" {
                    "Install / Update All"
                } else {
                    "Install / Update"
                }),
        )
        .into_element()
}

fn behavior_row(
    title: &'static str,
    description: &'static str,
    enabled: bool,
    bridge: RuntimeBridge,
    mut behavior: AgentBehavior,
    update: fn(&mut AgentBehavior),
    signals: AgentSignals,
) -> Element {
    settings_row_shell(title, description)
        .child(toggle_control(enabled, move || {
            update(&mut behavior);
            persist_behavior(bridge.clone(), behavior.clone(), signals);
        }))
        .into_element()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn behavior_round_trips_through_runtime_metadata() {
        let behavior = AgentBehavior {
            notifications_enabled: true,
            finished_notifications_enabled: true,
            keep_awake: false,
        };
        let encoded = serde_json::to_string(&behavior).expect("encode behavior");
        assert_eq!(
            serde_json::from_str::<AgentBehavior>(&encoded).expect("decode behavior"),
            behavior
        );
    }

    #[test]
    fn cli_conflicts_and_unsupported_states_block_registration() {
        for state in ["conflict", "unsupported"] {
            assert!(
                CliRegistrationStatus {
                    state: state.to_string(),
                    ..CliRegistrationStatus::default()
                }
                .blocks_install()
            );
        }
        assert!(
            !CliRegistrationStatus {
                state: "stale".to_string(),
                ..CliRegistrationStatus::default()
            }
            .blocks_install()
        );
    }
}
