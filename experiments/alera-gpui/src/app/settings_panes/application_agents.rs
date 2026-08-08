fn application_pane(
    workspace_directory_input: &Entity<InputState>,
    settings: &SettingsState,
    inputs: &SettingsInputs,
    anchors: &SettingsGroupAnchors,
    diagnostics_log_level_select: &SettingsSelect,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
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
                            "Save app and runtime logs with version details as a zip. Secrets such as tokens are masked before anything is written.",
                            settings_button("export-diagnostics", "Export").on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, window, cx| {
                                    this.export_diagnostics(window, cx);
                                    cx.stop_propagation();
                                }),
                            ),
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
                        "Managed Hooks Let Terminal Tabs Show Agent State.",
                        vec![
                        agent_hook_row(
                            "codex",
                            "Codex Hooks",
                            "Use An Alera-Managed Codex Runtime Home With Status Hooks.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "claude",
                            "Claude Code Hooks",
                            "Use An Alera-Managed Claude Code Config With Status Hooks.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "copilot",
                            "GitHub Copilot Hooks",
                            "Use An Alera-Managed GitHub Copilot Home Overlay.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "cursor",
                            "Cursor Hooks",
                            "Use An Alera-Managed Cursor Agent Plugin Wrapper.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "agy",
                            "Antigravity Hooks",
                            "Install Alera-Managed Antigravity Hooks For The Agy CLI.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "opencode",
                            "OpenCode Hooks",
                            "Use An Alera-Managed OpenCode Config Overlay With Status Plugin.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "pi",
                            "Pi Hooks",
                            "Use An Alera-Managed Pi Agent Overlay With Status Extension.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "amp",
                            "Amp Hooks",
                            "Use An Alera-Managed Amp Config Overlay.",
                            settings,
                            cx,
                        ),
                        agent_hook_row(
                            "grok",
                            "Grok Build Hooks",
                            "Install Alera-Managed Grok Build Hooks In A Dedicated Global File.",
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
                        "How Alera Reacts While Agents Are Running.",
                        vec![
                        exact_settings_row(
                            "Agent Status Notifications",
                            "Show Native Notifications When An Agent Needs Attention. Bursts Are Grouped Into One Notification.",
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
                            "Also Notify When An Agent Finishes. Most Agents Report The End Of A Turn, Not The End Of A Task.",
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
                            "Keep This Computer And Display Awake While Agents Are Working.",
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
