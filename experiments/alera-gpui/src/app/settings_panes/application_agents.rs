fn application_pane(
    workspace_directory_input: &Entity<InputState>,
    settings: &SettingsState,
    inputs: &SettingsInputs,
    anchors: &SettingsGroupAnchors,
    diagnostics_export_busy: bool,
    diagnostics_log_level_select: &SettingsSelect,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
    let github_star_state = settings.github_star_state;
    let support_control: AnyElement = match github_star_state {
        GitHubStarState::Loading => div()
            .w(px(110.0))
            .h(px(34.0))
            .rounded_lg()
            .bg(theme::surface_raised())
            .into_any_element(),
        GitHubStarState::NotStarred => div()
            .id("support-alera-star")
            .flex()
            .items_center()
            .justify_center()
            .h(px(34.0))
            .px_3()
            .gap_2()
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_selected())
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                    this.star_github(cx);
                    cx.stop_propagation();
                }),
            )
            .child(icon(AleraIcon::Star, 16.0, theme::text_muted()))
            .child("Star")
            .into_any_element(),
        GitHubStarState::Starring => div()
            .flex()
            .items_center()
            .justify_center()
            .h(px(34.0))
            .px_3()
            .gap_2()
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_selected())
            .child(loading_indicator(14.0, theme::text_muted()))
            .child("Starring…")
            .into_any_element(),
        GitHubStarState::Starred => div()
            .flex()
            .items_center()
            .h(px(34.0))
            .gap_2()
            .child(icon(AleraIcon::Star, 16.0, theme::warning()))
            .child(
                div()
                    .text_size(px(13.0))
                    .font_weight(gpui::FontWeight::MEDIUM)
                    .text_color(theme::warning())
                    .child("Thanks for the support!"),
            )
            .into_any_element(),
        GitHubStarState::Error => div()
            .id("support-alera-retry")
            .flex()
            .items_center()
            .justify_center()
            .h(px(34.0))
            .px_3()
            .gap_2()
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_selected())
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                    this.star_github(cx);
                    cx.stop_propagation();
                }),
            )
            .child(icon(AleraIcon::Star, 16.0, theme::text_muted()))
            .child("Try Again")
            .into_any_element(),
        GitHubStarState::Hidden => div().into_any_element(),
    };
    div()
        .child(
            application_workspace_panel(workspace_directory_input, cx)
                .id(("settings-group-anchor", 0usize))
                .anchor_scroll(settings_group_anchor(
                    anchors,
                    SettingsPane::Application,
                    0,
                )),
        )
        .child(
            div()
                .mt_4()
                .child(
                    exact_settings_group(
                        "Safety",
                        "Confirmation prompts for destructive workspace actions.",
                        vec![
                        exact_settings_row(
                            "Confirm Project Removal",
                            "Ask before unregistering a project and deleting its workspace metadata.",
                            settings_switch(
                                "confirm-project-removal",
                                settings.confirm_project_removal,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.set_confirm_project_removal(
                                        !this.settings_state.confirm_project_removal,
                                        cx,
                                    );
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        exact_settings_row(
                            "Confirm Workspace Removal",
                            "Ask before removing a linked workspace and deleting its branch.",
                            settings_switch(
                                "confirm-workspace-removal",
                                settings.confirm_workspace_removal,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.set_confirm_workspace_removal(
                                        !this.settings_state.confirm_workspace_removal,
                                        cx,
                                    );
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        ],
                    )
                    .id(("settings-group-anchor", 1usize))
                    .anchor_scroll(settings_group_anchor(
                        anchors,
                        SettingsPane::Application,
                        1,
                    )),
                ),
        )
        .child(
            div()
                .mt_4()
                .child(
                    exact_settings_group(
                        "Runtime",
                        "Lifecycle of the local runtime host that owns terminal sessions.",
                        vec![
                        exact_settings_row(
                            "Keep Runtime Open When App Quits",
                            "Leave the app-launched sidecar running after a clean quit. Persistent CLI runtimes are never stopped by quitting, and unexpected exits always leave the host up.",
                            settings_switch(
                                "keep-runtime-open-on-quit",
                                settings.keep_runtime_open_on_quit,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.set_keep_runtime_open_on_quit(
                                        !this.settings_state.keep_runtime_open_on_quit,
                                        cx,
                                    );
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        exact_settings_row(
                            "Empty Host Shutdown",
                            "Seconds to keep the host alive after the app closes with no running sessions.",
                            number_input_control(
                                "host-empty-seconds",
                                settings_input(inputs, "host-empty-seconds"),
                                "s",
                                5.0,
                                5.0,
                                3600.0,
                                cx,
                            ),
                        ),
                        exact_settings_row(
                            "Detached Session Shutdown",
                            "Seconds to keep detached running sessions alive after the app closes.",
                            number_input_control(
                                "host-detached-seconds",
                                settings_input(inputs, "host-detached-seconds"),
                                "s",
                                60.0,
                                5.0,
                                86_400.0,
                                cx,
                            ),
                        ),
                        ],
                    )
                    .id(("settings-group-anchor", 2usize))
                    .anchor_scroll(settings_group_anchor(
                        anchors,
                        SettingsPane::Application,
                        2,
                    )),
                ),
        )
        .child(
            div()
                .mt_6()
                .child(
                    exact_settings_group(
                        "Diagnostics",
                        "Alera keeps rotating log files on this computer so an error can be reviewed after it happens.",
                        vec![
                        exact_settings_row(
                            "Open Logs Folder",
                            "Show the folder holding the app log files.",
                            settings_button("open-logs-folder", "Open").on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.open_logs_folder(cx);
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        exact_settings_row(
                            "Export Diagnostics",
                            "Save a zip with app and runtime logs plus version details. Secrets such as tokens are masked before anything is written.",
                            settings_button_with_loading(
                                "export-diagnostics",
                                "Export",
                                diagnostics_export_busy,
                            )
                            .when(!diagnostics_export_busy, |button| {
                                button.on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(|this, _: &MouseDownEvent, window, cx| {
                                        this.export_diagnostics(window, cx);
                                        cx.stop_propagation();
                                    }),
                                )
                            }),
                        ),
                        exact_settings_row(
                            "Log Level",
                            "How much detail is written to the log files.",
                            settings_select_control(
                                diagnostics_log_level_select,
                                false,
                                false,
                            ),
                        ),
                        exact_settings_row(
                            "Send Crash Reports",
                            "Send crashes to Sentry, an external service. Off by default; local log files work either way.",
                            settings_switch(
                                "send-crash-reports",
                                settings.crash_reporting_enabled,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.set_crash_reporting_enabled(
                                        !this.settings_state.crash_reporting_enabled,
                                        cx,
                                    );
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        ],
                    )
                    .id(("settings-group-anchor", 3usize))
                    .anchor_scroll(settings_group_anchor(
                        anchors,
                        SettingsPane::Application,
                        3,
                    )),
                ),
        )
        .child(
            div()
                .mt_6()
                .child(
                    exact_settings_group(
                        "Updates",
                        "Check the Alera release channel for a newer desktop build.",
                        vec![update_settings_row(settings, cx)]
                    )
                    .id(("settings-group-anchor", 4usize))
                    .anchor_scroll(settings_group_anchor(
                        anchors,
                        SettingsPane::Application,
                        4,
                    )),
                ),
        )
        .when(github_star_state != GitHubStarState::Hidden, |pane| {
            pane.child(
                div()
                    .mt_6()
                    .child(
                        settings_title_only_group(
                            "Support Alera",
                            vec![settings_title_only_row(
                                "Star Alera on GitHub",
                                support_control,
                            )],
                        )
                        .id(("settings-group-anchor", 5usize))
                        .anchor_scroll(settings_group_anchor(
                            anchors,
                            SettingsPane::Application,
                            5,
                        )),
                    ),
            )
        })
        .into_any_element()
}

fn agents_pane(
    settings: &SettingsState,
    selects: &BTreeMap<String, SettingsSelect>,
    skill_runners: &BTreeMap<String, String>,
    anchors: &SettingsGroupAnchors,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
    let cli_registration = settings.cli_registration_status.as_ref();
    let cli_registration_blocked = cli_registration.is_some_and(|status| status.blocks_install());
    div()
        .child(
            exact_settings_group(
                "Alera CLI And Skills",
                "Register The CLI Command And Install Agent Instructions.",
                vec![
                exact_settings_row_width(
                    "Alera CLI Command",
                    "Register The Alera Command On PATH For Terminals And Agents.",
                    360.0,
                    div()
                        .flex()
                        .flex_col()
                        .items_end()
                        .gap_2()
                        .child(
                            div()
                                .flex()
                                .justify_end()
                                .gap_2()
                                .child(
                                    settings_icon_button(
                                        "refresh-cli-registration",
                                        AleraIcon::Refresh,
                                        "Refresh",
                                    )
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                            this.refresh_cli_registration(cx);
                                            cx.stop_propagation();
                                        }),
                                    ),
                                )
                                .child(
                                    settings_icon_button(
                                        "install-cli-registration",
                                        AleraIcon::Terminal,
                                        "Register",
                                    )
                                    .when(!cli_registration_blocked, |button| {
                                        button.on_mouse_down(
                                            MouseButton::Left,
                                            cx.listener(
                                                |this, _: &MouseDownEvent, _, cx| {
                                                    this.install_cli_registration(cx);
                                                    cx.stop_propagation();
                                                },
                                            ),
                                        )
                                    }),
                                ),
                        )
                        .when_some(cli_registration, |control, status| {
                            control.child(
                                div()
                                    .max_w(px(360.0))
                                    .text_right()
                                    .child(
                                        div()
                                            .text_size(px(11.0))
                                            .font_weight(gpui::FontWeight::MEDIUM)
                                            .text_color(if status.ready {
                                                theme::success()
                                            } else if status.blocks_install() {
                                                theme::danger()
                                            } else {
                                                theme::text_muted()
                                            })
                                            .child(status.label()),
                                    )
                                    .child(
                                        div()
                                            .mt_1()
                                            .text_size(px(10.0))
                                            .text_color(theme::text_faint())
                                            .child(if let Some(path) = status.command_path.as_ref() {
                                                format!(
                                                    "{path} {}",
                                                    status
                                                        .detail
                                                        .strip_prefix("The Registration ")
                                                        .unwrap_or(&status.detail)
                                                )
                                            } else {
                                                status.detail.clone()
                                            }),
                                    ),
                            )
                        }),
                ),
                exact_settings_row_width(
                    "All Alera Skills",
                    "Install Or Update CLI, Orchestration, Computer Use, And Emulator Skills. Reapplies Selected Status Hooks.",
                    360.0,
                    skill_install_control(
                        "all-skills",
                        "all",
                        selects
                            .get("skill-runner-all")
                            .expect("all skill runner select should exist"),
                        skill_runners
                            .get("all")
                            .map(String::as_str)
                            .unwrap_or("Auto"),
                        false,
                        "Install / Update All",
                        cx,
                    ),
                ),
                exact_settings_row_width(
                    "Alera CLI Skill",
                    "Install The Codex Skill That Teaches Agents To Use The Alera CLI.",
                    360.0,
                    skill_install_control(
                        "cli-skill",
                        "cli",
                        selects
                            .get("skill-runner-cli")
                            .expect("cli skill runner select should exist"),
                        skill_runners
                            .get("cli")
                            .map(String::as_str)
                            .unwrap_or("Auto"),
                        true,
                        "Install / Update",
                        cx,
                    ),
                ),
                exact_settings_row_width(
                    "Alera Orchestration Skill",
                    "Install Or Update Orchestration And Reapply Selected Status Hooks.",
                    360.0,
                    skill_install_control(
                        "orchestration-skill",
                        "orchestration",
                        selects
                            .get("skill-runner-orchestration")
                            .expect("orchestration skill runner select should exist"),
                        skill_runners
                            .get("orchestration")
                            .map(String::as_str)
                            .unwrap_or("Auto"),
                        true,
                        "Install / Update",
                        cx,
                    ),
                ),
                exact_settings_row_width(
                    "Alera Computer Use Skill",
                    "Install The Skill For Reading And Operating Desktop Applications.",
                    360.0,
                    skill_install_control(
                        "computer-use-skill",
                        "computer-use",
                        selects
                            .get("skill-runner-computer-use")
                            .expect("computer use skill runner select should exist"),
                        skill_runners
                            .get("computer-use")
                            .map(String::as_str)
                            .unwrap_or("Auto"),
                        true,
                        "Install / Update",
                        cx,
                    ),
                ),
                exact_settings_row_width(
                    "Alera Emulator Skill",
                    "Install The Skill For Android And iOS Emulator Automation.",
                    360.0,
                    skill_install_control(
                        "emulator-skill",
                        "emulator",
                        selects
                            .get("skill-runner-emulator")
                            .expect("emulator skill runner select should exist"),
                        skill_runners
                            .get("emulator")
                            .map(String::as_str)
                            .unwrap_or("Auto"),
                        true,
                        "Install / Update",
                        cx,
                    ),
                ),
                ],
            )
            .id(("settings-group-anchor", 0usize))
            .anchor_scroll(settings_group_anchor(anchors, SettingsPane::Agents, 0)),
        )
        .child(
            div()
                .mt_4()
                .child(
                    exact_settings_group(
                        "Status Hooks",
                        "Managed hooks let terminal tabs show agent state.",
                        vec![
                        agent_hook_row(
                            "codex",
                            "Codex Hooks",
                            "Use an Alera-managed Codex runtime home with status hooks.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "claude",
                            "Claude Code Hooks",
                            "Use an Alera-managed Claude Code config with status hooks.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "copilot",
                            "GitHub Copilot Hooks",
                            "Use an Alera-managed GitHub Copilot home overlay.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "cursor",
                            "Cursor Hooks",
                            "Use an Alera-managed Cursor Agent plugin wrapper.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "agy",
                            "Antigravity Hooks",
                            "Install Alera-managed Antigravity hooks for the agy CLI. Disable to remove only Alera-managed hook entries.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "opencode",
                            "OpenCode Hooks",
                            "Use an Alera-managed OpenCode config overlay with status plugin.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "pi",
                            "Pi Hooks",
                            "Use an Alera-managed Pi agent overlay with status extension.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "amp",
                            "Amp Hooks",
                            "Use an Alera-managed Amp config overlay.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "grok",
                            "Grok Build Hooks",
                            "Install Alera-managed Grok Build hooks in a dedicated global file.",
                            settings,
                            cx,
                        ),
                        ],
                    )
                    .id(("settings-group-anchor", 1usize))
                    .anchor_scroll(settings_group_anchor(anchors, SettingsPane::Agents, 1)),
                ),
        )
        .child(
            div()
                .mt_4()
                .child(
                    exact_settings_group(
                        "Behavior",
                        "How Alera reacts while agents are running.",
                        vec![
                        exact_settings_row(
                            "Agent Status Notifications",
                            "Show native notifications when an agent needs attention. Bursts are grouped into one notification.",
                            settings_switch(
                                "agent-status-notifications",
                                settings.agent_status_notifications_enabled,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.update_agent_settings(
                                        |settings| {
                                            settings.agent_status_notifications_enabled =
                                                !settings.agent_status_notifications_enabled;
                                        },
                                        cx,
                                    );
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        exact_settings_row(
                            "Agent Finished Notifications",
                            "Also notify when an agent finishes. Most agents report the end of a turn, not the end of a task, so this notifies on every reply.",
                            settings_switch(
                                "agent-finished-notifications",
                                settings.agent_status_finished_notifications_enabled,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.update_agent_settings(
                                        |settings| {
                                            settings.agent_status_finished_notifications_enabled =
                                                !settings.agent_status_finished_notifications_enabled;
                                        },
                                        cx,
                                    );
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        exact_settings_row(
                            "Keep Computer Awake While Agents Are Working",
                            agent_awake_description(),
                            settings_switch(
                                "keep-computer-awake",
                                settings.keep_computer_awake_while_agents_work,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.update_agent_settings(
                                        |settings| {
                                            settings.keep_computer_awake_while_agents_work =
                                                !settings.keep_computer_awake_while_agents_work;
                                        },
                                        cx,
                                    );
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                        ],
                    )
                    .id(("settings-group-anchor", 2usize))
                    .anchor_scroll(settings_group_anchor(anchors, SettingsPane::Agents, 2)),
                ),
        )
        .into_any_element()
}

fn agent_awake_description() -> &'static str {
    if cfg!(target_os = "windows") {
        "Keeps this computer and display awake while agents are working. Lid-close behavior follows this device's power settings."
    } else {
        "Keeps this computer and display awake while agents are working. Alera also asks this device to stay awake when the lid is closed, subject to its power policy."
    }
}
