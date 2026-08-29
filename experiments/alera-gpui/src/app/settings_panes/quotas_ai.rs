fn quotas_pane(
    settings: &SettingsState,
    inputs: &SettingsInputs,
    environment_presence: &BTreeMap<String, bool>,
    environment_loading: bool,
    anchors: &SettingsGroupAnchors,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
    div()
        .child(
            exact_settings_group(
                "Provider Quotas",
                "Choose Which Usage Sources Appear For The Active Workspace Host.",
                vec![
                exact_settings_row(
                    "Active Quota Host",
                    "Run Quota Commands Locally Or Through The Installed Alera Runtime For This Workspace.",
                    div().font_family("JetBrains Mono").child("Local"),
                ),
                quota_provider_row(
                    "codex",
                    "Codex Quotas",
                    "Read Codex Rate Limits Through The Official App Server.",
                    settings,
                    cx,
                ),
                quota_provider_row(
                    "kimi",
                    "Kimi Quotas",
                    "Read Kimi Coding Plan Usage With An API Key From The Host Environment.",
                    settings,
                    cx,
                ),
                quota_provider_row(
                    "grok",
                    "Grok Build Quotas",
                    "Read Grok Build Usage Through Its Official Interactive CLI.",
                    settings,
                    cx,
                ),
                quota_provider_row(
                    "cursor",
                    "Cursor Quotas",
                    "Read Cursor Plan Usage From The Local Cursor CLI Session.",
                    settings,
                    cx,
                ),
                quota_provider_row(
                    "antigravity",
                    "Antigravity Quotas",
                    "Read Antigravity Usage Through The Official Agy CLI.",
                    settings,
                    cx,
                ),
                quota_provider_row(
                    "minimax",
                    "MiniMax Quotas",
                    "Read MiniMax Token Plan Usage With An API Key From The Host Environment.",
                    settings,
                    cx,
                ),
                quota_provider_row(
                    "zai",
                    "Z.ai Quotas",
                    "Read Z.ai Limits With An API Key From The Host Environment.",
                    settings,
                    cx,
                ),
                quota_provider_row(
                    "opencode",
                    "OpenCode Quotas",
                    "Read OpenCode Go And Zen Usage From The Host Environment.",
                    settings,
                    cx,
                ),
                exact_settings_row_width(
                    "Quota Display Order",
                    "Set The Left-To-Right Order Of Enabled Providers In The Status Bar.",
                    420.0,
                    provider_order_control(settings, cx),
                ),
                ],
            )
            .id(("settings-group-anchor", 0usize))
            .anchor_scroll(settings_group_anchor(anchors, SettingsPane::Quotas, 0)),
        )
        .child(
            div()
                .mt_4()
                .child(
                    exact_settings_group(
                        "Claude",
                        "Configure The Default Claude Account And Every CCS Profile Together.",
                        vec![
                        exact_settings_row(
                            "Claude Code Quotas",
                            "Read Default Claude Code Usage And Any Configured CCS Profiles.",
                            settings_switch(
                                "claude-provider-enabled",
                                "Claude Code Quotas",
                                settings
                                    .quota_enabled_providers
                                    .iter()
                                    .any(|provider| provider == "claude"),
                            )
                            .on_click(
                                cx.listener(|this, _, _, cx| {
                                    this.update_quota_settings(
                                        |settings| toggle_quota_provider(settings, "claude"),
                                        cx,
                                    );
                                }),
                            ),
                        ),
                        exact_settings_row(
                            "Claude Default Quotas",
                            "Query The Default Claude Account Separately From Configured CCS Profiles.",
                            div()
                                .flex()
                                .items_center()
                                .gap_3()
                                .child(
                                    settings_icon_button(
                                        "pin-claude-default",
                                        if settings
                                            .quota_unpinned_keys
                                            .contains("claude:default")
                                        {
                                            AleraIcon::PinOff
                                        } else {
                                            AleraIcon::Pin
                                        },
                                        "Toggle Default Claude Quota Pin",
                                    )
                                    .on_click(
                                        cx.listener(|this, _, _, cx| {
                                            this.update_quota_settings(
                                                |settings| {
                                                    toggle_quota_pin(settings, "claude:default")
                                                },
                                                cx,
                                            );
                                        }),
                                    ),
                                )
                                .child(
                                    settings_switch(
                                        "claude-default-enabled",
                                        "Default Claude Code Quota",
                                        settings.claude_default_enabled,
                                    )
                                    .on_click(
                                        cx.listener(|this, _, _, cx| {
                                            this.update_quota_settings(
                                                |settings| {
                                                    settings.claude_default_enabled =
                                                        !settings.claude_default_enabled;
                                                },
                                                cx,
                                            );
                                        }),
                                    ),
                                ),
                        ),
                        exact_settings_row(
                            "Claude Default In Usage",
                            "Include The Default Claude Account In Usage Independently Of Quota Polling.",
                            settings_switch(
                                "claude-default-show-in-usage",
                                "Claude Default In Usage",
                                settings.claude_default_show_in_usage,
                            )
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.update_quota_settings(
                                    |settings| {
                                        settings.claude_default_show_in_usage =
                                            !settings.claude_default_show_in_usage;
                                    },
                                    cx,
                                );
                            })),
                        ),
                        exact_settings_row_width(
                            "Claude CCS Profiles",
                            "Add CCS Alias And Profile Pairs. These Remain Available When Default Claude Is Disabled.",
                            420.0,
                            claude_profiles_control(settings, cx),
                        ),
                        ],
                    )
                    .id(("settings-group-anchor", 1usize))
                    .anchor_scroll(settings_group_anchor(anchors, SettingsPane::Quotas, 1)),
                ),
        )
        .child(
            div()
                .mt_4()
                .child(
                    exact_settings_group(
                        "Credential Environment",
                        "Configure Environment Variable Names For The Active Workspace Host.",
                        vec![
                        credential_environment_row(
                            "Kimi API Key Variable",
                            settings_input(inputs, "quota-env-kimiApiKey"),
                        ),
                        credential_environment_row(
                            "Z.ai API Key Variable",
                            settings_input(inputs, "quota-env-zaiApiKey"),
                        ),
                        credential_environment_row(
                            "Z.ai Base URL Variable",
                            settings_input(inputs, "quota-env-zaiBaseUrl"),
                        ),
                        credential_environment_row(
                            "MiniMax API Key Variable",
                            settings_input(inputs, "quota-env-minimaxApiKey"),
                        ),
                        credential_environment_row(
                            "MiniMax API Host Variable",
                            settings_input(inputs, "quota-env-minimaxApiHost"),
                        ),
                        exact_settings_row_width(
                            "Credential Availability",
                            "Check Whether Each Configured Variable Exists Without Reading Its Secret Value.",
                            420.0,
                            quota_environment_presence_control(
                                settings,
                                environment_presence,
                                environment_loading,
                                cx,
                            ),
                        ),
                        ],
                    )
                    .id(("settings-group-anchor", 2usize))
                    .anchor_scroll(settings_group_anchor(anchors, SettingsPane::Quotas, 2)),
                ),
        )
        .into_any_element()
}

fn quota_environment_presence_control(
    settings: &SettingsState,
    presence: &BTreeMap<String, bool>,
    loading: bool,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let names = [
        "kimiApiKey",
        "zaiApiKey",
        "zaiBaseUrl",
        "minimaxApiKey",
        "minimaxApiHost",
    ]
    .into_iter()
    .filter_map(|key| settings.quota_environment.get(key))
    .cloned()
    .collect::<Vec<_>>();
    div()
        .flex()
        .flex_col()
        .gap_1()
        .children(names.into_iter().map(|name| {
            let present = presence.get(&name).copied().unwrap_or(false);
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(icon(
                    if present {
                        AleraIcon::Check
                    } else {
                        AleraIcon::Close
                    },
                    13.0,
                    if present {
                        theme::success()
                    } else {
                        theme::text_faint()
                    },
                ))
                .child(
                    div()
                        .font_family("JetBrains Mono")
                        .text_size(px(11.0))
                        .child(name),
                )
        }))
        .child(
            settings_icon_button(
                "check-quota-environment",
                if loading {
                    AleraIcon::Loading
                } else {
                    AleraIcon::Refresh
                },
                "Check Environment",
            )
            .on_click(
                cx.listener(|this, _, _, cx| {
                    if !this.status_data.quota_loading {
                        this.refresh_quota_status(true, cx);
                    }
                }),
            ),
        )
}

fn claude_profiles_control(
    settings: &SettingsState,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let mut control = div().flex().flex_col().items_end().gap_2();
    if settings.claude_profiles.is_empty() {
        control = control.child(
            div()
                .text_size(px(12.0))
                .text_color(theme::text_faint())
                .child("No CCS Profiles Configured"),
        );
    } else {
        for (index, profile) in settings.claude_profiles.iter().enumerate() {
            let profile_name = profile.profile.clone();
            let edit_index = index;
            let remove_index = index;
            let move_up_index = index;
            let move_down_index = index;
            let pinned = !settings
                .quota_unpinned_keys
                .contains(&format!("claude:{profile_name}"));
            control = control.child(
                div()
                    .flex()
                    .items_center()
                    .w_full()
                    .gap_1()
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .child(div().truncate().child(profile.alias.clone()))
                            .child(
                                div()
                                    .truncate()
                                    .font_family("JetBrains Mono")
                                    .text_size(px(11.0))
                                    .text_color(theme::text_muted())
                                    .child(profile.profile.clone()),
                            )
                            .child(
                                div()
                                    .truncate()
                                    .text_size(px(10.0))
                                    .text_color(theme::text_faint())
                                    .child(if profile.show_in_usage {
                                        format!("Usage: {}", profile.usage_label())
                                    } else {
                                        "Not Shown In Usage".to_owned()
                                    }),
                            ),
                    )
                    .child(
                        project_icon_button(
                            SharedString::from(format!("pin-claude-profile-{index}")),
                            if pinned {
                                AleraIcon::Pin
                            } else {
                                AleraIcon::PinOff
                            },
                            pinned,
                            if pinned {
                                "Shown In Status Bar".to_owned()
                            } else {
                                "Hidden From Status Bar - Available In The Quota Panel".to_owned()
                            },
                        )
                        .on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.update_quota_settings(
                                    |settings| {
                                        toggle_quota_pin(
                                            settings,
                                            &format!("claude:{profile_name}"),
                                        )
                                    },
                                    cx,
                                );
                            }),
                        ),
                    )
                    .child(
                        project_icon_button(
                            SharedString::from(format!("move-claude-profile-up-{index}")),
                            AleraIcon::ChevronUp,
                            false,
                            format!("Move {} Earlier", profile.alias),
                        )
                        .on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.move_claude_profile(move_up_index, -1, cx);
                            }),
                        ),
                    )
                    .child(
                        project_icon_button(
                            SharedString::from(format!("move-claude-profile-down-{index}")),
                            AleraIcon::ChevronDown,
                            false,
                            format!("Move {} Later", profile.alias),
                        )
                        .on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.move_claude_profile(move_down_index, 1, cx);
                            }),
                        ),
                    )
                    .child(
                        project_icon_button(
                            SharedString::from(format!("edit-claude-profile-{index}")),
                            AleraIcon::Edit,
                            false,
                            "Edit CCS Profile",
                        )
                        .on_click(
                            cx.listener(move |this, _, window, cx| {
                                this.open_claude_profile_dialog(Some(edit_index), window, cx);
                            }),
                        ),
                    )
                    .child(
                        project_icon_button(
                            SharedString::from(format!("remove-claude-profile-{index}")),
                            AleraIcon::Delete,
                            false,
                            "Remove CCS Profile",
                        )
                        .on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.remove_claude_profile(remove_index, cx);
                            }),
                        ),
                    ),
            );
        }
    }
    control.child(
        div()
            .id("add-claude-profile")
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label("Add CCS Profile")
            .flex()
            .items_center()
            .h(px(34.0))
            .px_2()
            .gap_2()
            .rounded_lg()
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .on_click(
                cx.listener(|this, _, window, cx| {
                    this.open_claude_profile_dialog(None, window, cx);
                }),
            )
            .child(icon(AleraIcon::Add, 14.0, theme::text_muted()))
            .child("Add CCS Profile"),
    )
}

fn project_icon_button(
    id: SharedString,
    icon_kind: AleraIcon,
    active: bool,
    tooltip: impl Into<SharedString>,
) -> gpui::Stateful<gpui::Div> {
    let tooltip = tooltip.into();
    let aria_label = tooltip.clone();
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(aria_label)
        .flex()
        .items_center()
        .justify_center()
        .w(px(28.0))
        .h(px(28.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .tooltip(move |_, cx| {
            let label = tooltip.clone();
            cx.new(move |_| Tooltip::new(label)).into()
        })
        .hover(|style| style.bg(theme::surface_raised()))
        .child(icon(
            icon_kind,
            14.0,
            if active {
                theme::accent()
            } else {
                theme::text_muted()
            },
        ))
}

#[allow(clippy::too_many_arguments)]
fn ai_text_pane(
    settings: &SettingsState,
    inputs: &SettingsInputs,
    textareas: &SettingsTextareas,
    selects: &BTreeMap<String, SettingsSelect>,
    discovery_busy: &BTreeSet<String>,
    discovery_errors: &BTreeMap<String, SharedString>,
    anchors: &SettingsGroupAnchors,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
    let agent_select = selects.get("ai-agent").expect("AI agent select should exist");
    let model_select = selects.get("ai-model").expect("AI model select should exist");
    let thinking_select = selects
        .get("ai-thinking")
        .expect("AI thinking select should exist");
    let model_id =
        super::ai_text_settings_catalog::selected_model_id(settings, &settings.ai_text_agent);
    let model_choices =
        super::ai_text_settings_catalog::model_choices(settings, &settings.ai_text_agent);
    let selected_model = model_choices.iter().find(|model| model.id == model_id);
    let mut generation_rows = vec![
        exact_settings_row(
            "Enable AI Text",
            "Show generation actions in source control and pull requests.",
            settings_switch("ai-text-enabled", "Enable AI Text", settings.ai_text_enabled)
                .on_click(
                cx.listener(|this, _, _, cx| {
                    this.update_ai_text_settings(
                        |settings| settings.ai_text_enabled = !settings.ai_text_enabled,
                        cx,
                    );
                }),
            ),
        ),
        exact_settings_row(
            "Agent",
            "CLI used for generated source control text.",
            settings_select_control("Agent", agent_select, false, true),
        ),
    ];
    if settings.ai_text_agent == "custom" {
        generation_rows.push(exact_settings_row(
            "Custom Command",
            "Use {prompt} to pass the prompt as an argument; otherwise Alera sends it on stdin.",
            settings_text_input(
                "Custom Command",
                settings_input(inputs, "ai-custom-command"),
                320.0,
                48.0,
            ),
        ));
    } else {
        generation_rows.push(exact_settings_row(
            "Model",
            discovery_errors
                .get(&settings.ai_text_agent)
                .cloned()
                .unwrap_or_else(|| {
                    format!(
                        "Model passed to {}.",
                        super::ai_text_settings_catalog::agent_label(&settings.ai_text_agent)
                    )
                    .into()
                }),
            ai_model_select_control(
                model_select,
                &settings.ai_text_agent,
                "global",
                discovery_busy,
                cx,
            ),
        ));
        if selected_model.is_some_and(|model| !model.thinking_levels.is_empty()) {
            generation_rows.push(exact_settings_row(
                "Thinking",
                "Reasoning effort for models that support it.",
                settings_select_control("Thinking", thinking_select, false, false),
            ));
        }
    }
    if settings.ai_text_agent != "custom"
        && settings
            .ai_text_prompt_settings_by_operation
            .values()
            .any(|prompt| prompt.agent.as_deref() == Some("custom"))
    {
        generation_rows.push(exact_settings_row(
            "Custom Command",
            "Used By Prompts That Override The Global Agent With Custom Command.",
            settings_text_input(
                "Custom Command",
                settings_input(inputs, "ai-custom-command"),
                320.0,
                48.0,
            ),
        ));
    }
    let mut pane = div().child(
        exact_settings_group(
            "Generation",
            "Local agent CLIs generate text from source control context.",
            generation_rows,
        )
        .id(("settings-group-anchor", 0usize))
        .anchor_scroll(settings_group_anchor(anchors, SettingsPane::AiText, 0)),
    );
    for (index, (operation, title)) in [
        ("commitMessage", "Commit Messages"),
        ("pullRequestDetails", "Pull Request Details"),
        ("workspaceIdentity", "Workspace Identity"),
        ("readingDiff", "Reading Diffs"),
    ]
    .into_iter()
    .enumerate()
    {
        pane = pane.child(
            div().mt_4().child(
                exact_settings_group(
                    title,
                    "Configure The Agent, Model, Reasoning And Instructions For This Prompt.",
                    prompt_operation_rows(
                        settings,
                        textareas,
                        selects,
                        operation,
                        discovery_busy,
                        discovery_errors,
                        cx,
                    ),
                )
                .id(("settings-group-anchor", index + 1))
                .anchor_scroll(settings_group_anchor(
                    anchors,
                    SettingsPane::AiText,
                    index + 1,
                )),
            ),
        );
    }
    pane.into_any_element()
}

fn prompt_operation_rows(
    settings: &SettingsState,
    textareas: &SettingsTextareas,
    selects: &BTreeMap<String, SettingsSelect>,
    operation: &str,
    discovery_busy: &BTreeSet<String>,
    discovery_errors: &BTreeMap<String, SharedString>,
    cx: &mut Context<AleraApp>,
) -> Vec<gpui::Div> {
    let mut rows = Vec::new();
    let prompt = settings
        .ai_text_prompt_settings_by_operation
        .get(operation);
    let effective_agent = prompt
        .and_then(|prompt| prompt.agent.as_deref())
        .unwrap_or(&settings.ai_text_agent);
    let agent_select = selects
        .get(&format!("ai-prompt-{operation}-agent"))
        .expect("AI prompt agent select should exist");
    rows.push(exact_settings_row(
        "Agent",
        "Override The Global Agent For This Prompt.",
        settings_select_control("Agent", agent_select, false, true),
    ));
    if effective_agent != "custom" {
        let model_select = selects
            .get(&format!("ai-prompt-{operation}-model"))
            .expect("AI prompt model select should exist");
        rows.push(exact_settings_row(
            "Model",
            discovery_errors
                .get(effective_agent)
                .cloned()
                .unwrap_or_else(|| "Override The Global Model For This Prompt.".into()),
            ai_model_select_control(
                model_select,
                effective_agent,
                operation,
                discovery_busy,
                cx,
            ),
        ));
        if let Some(thinking_select) = selects.get(&format!("ai-prompt-{operation}-thinking")) {
            let effective_model_id = prompt
                .and_then(|prompt| prompt.model.as_deref())
                .map(str::to_owned)
                .unwrap_or_else(|| {
                    super::ai_text_settings_catalog::selected_model_id(settings, effective_agent)
                });
            let has_thinking = super::ai_text_settings_catalog::model_choices(
                settings,
                effective_agent,
            )
            .into_iter()
            .find(|model| model.id == effective_model_id)
            .is_some_and(|model| !model.thinking_levels.is_empty());
            if has_thinking {
                rows.push(exact_settings_row(
                    "Reasoning",
                    "Reasoning Effort For Models That Support It.",
                    settings_select_control("Reasoning", thinking_select, false, false),
                ));
            }
        }
    }
    rows.push(instruction_row(
        "Instructions",
        settings_textarea(textareas, &format!("ai-instructions-{operation}")),
    ));
    rows
}

fn ai_model_select_control(
    select: &SettingsSelect,
    agent: &str,
    scope: &str,
    discovery_busy: &BTreeSet<String>,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let can_discover = super::settings_actions::supports_ai_model_discovery(agent);
    let busy = discovery_busy.contains(agent);
    let agent = agent.to_string();
    let refresh_id = SharedString::from(format!("refresh-ai-models-{scope}"));
    div()
        .flex()
        .items_center()
        .gap_2()
        .child(
            div()
                .flex_1()
                .child(settings_select_control("Model", select, false, true)),
        )
        .when(can_discover, |row| {
            row.child(
                div()
                    .id(refresh_id)
                    .focusable()
                    .tab_stop(!busy)
                    .role(Role::Button)
                    .aria_label(if busy {
                        "Refreshing Models"
                    } else {
                        "Refresh Models"
                    })
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(24.0))
                    .h(px(34.0))
                    .rounded_md()
                    .text_color(if busy {
                        theme::text_faint()
                    } else {
                        theme::text_muted()
                    })
                    .when(!busy, |button| {
                        let agent = agent.clone();
                        button
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(
                                cx.listener(move |this, _, window, cx| {
                                    this.discover_ai_text_models(agent.clone(), window, cx);
                                }),
                            )
                    })
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh Models")).into())
                    .child(icon(
                        if busy {
                            AleraIcon::Loading
                        } else {
                            AleraIcon::Refresh
                        },
                        14.0,
                        theme::text_muted(),
                    )),
            )
        })
}
