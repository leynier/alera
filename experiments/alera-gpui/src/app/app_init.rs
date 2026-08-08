use super::app_helpers::{
    ai_agent_label_for_key, build_settings_inputs, merged_terminal_font_options, settings_select,
    settings_select_owned,
};
use super::*;

impl AleraApp {
    pub fn new(bridge: RuntimeBridge, window: &mut Window, cx: &mut Context<Self>) -> Self {
        cx.on_next_frame(window, |this, window, cx| this.start(window, cx));
        let (settings_store, settings_state) = SettingsStore::start();
        crate::app_log::set_level(&settings_state.diagnostics_log_level);
        crate::app_log::set_crash_reporting_enabled(settings_state.crash_reporting_enabled);
        let terminal_focus = cx.focus_handle();
        let sidebar_filter_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search workspaces")
                .clean_on_escape()
        });
        let sidebar_project_filter_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Add Project...")
                .clean_on_escape()
        });
        let sidebar_view_tag_filter_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Add Tag...")
                .clean_on_escape()
        });
        let local_project_path_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("/Path/To/Project"));
        let clone_project_url_input = cx.new(|cx| {
            InputState::new(window, cx).placeholder("https://github.com/owner/repository.git")
        });
        let clone_project_destination_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("/Path/To/Repository"));
        let project_display_name_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Display Name (Optional)"));
        let workspace_prompt_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Describe What The Agent Should Build")
                .multi_line(true)
                .soft_wrap(true)
        });
        let workspace_dropdown_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search")
                .clean_on_escape()
        });
        let workspace_project_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Projects")
                .clean_on_escape()
        });
        let workspace_branch_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Source Branches")
                .clean_on_escape()
        });
        let workspace_branch_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("e.g. feature/terminal-tabs"));
        let workspace_name_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Workspace Name (Optional)"));
        let agent_profile_settings = AgentProfileSettingsState::new(window, cx);
        let settings_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search settings")
                .clean_on_escape()
        });
        let workspace_directory_input = cx.new(|cx| {
            let mut input = InputState::new(window, cx).placeholder("~/.alera/workspaces");
            input.set_value("~/.alera/workspaces", window, cx);
            input
        });
        let editor_theme_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Syntax Themes")
                .clean_on_escape()
        });
        let terminal_theme_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Built-In Themes")
                .clean_on_escape()
        });
        let claude_profile_alias_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("ccwork"));
        let claude_profile_name_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("work"));
        let settings_inputs = build_settings_inputs(&settings_state, window, cx);
        let keyboard_settings = KeyboardSettingsUiState::new(cx);
        let mobile_access = MobileAccessState::new(window, cx);
        let project_config_settings = ProjectConfigSettingsState::new(window, cx);
        let ai_model_id = ai_text_settings_catalog::selected_model_id(
            &settings_state,
            &settings_state.ai_text_agent,
        );
        let ai_model_choices =
            ai_text_settings_catalog::model_choices(&settings_state, &settings_state.ai_text_agent);
        let ai_model = ai_model_choices
            .iter()
            .find(|model| model.id == ai_model_id);
        let ai_model_label = ai_model
            .map(|model| model.label.clone())
            .unwrap_or_else(|| ai_model_id.clone());
        let mut ai_model_options = ai_model_choices
            .iter()
            .map(|model| model.label.clone())
            .collect::<Vec<_>>();
        if !ai_model_id.is_empty() && !ai_model_options.iter().any(|model| model == &ai_model_id) {
            ai_model_options.push(ai_model_id.clone());
        }
        let ai_thinking_options = ai_model
            .map(|model| {
                model
                    .thinking_levels
                    .iter()
                    .map(|(_, label)| label.clone())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let ai_thinking_id = settings_state
            .ai_text_selected_thinking_by_model
            .get(&ai_model_id)
            .map(String::as_str)
            .or_else(|| ai_model.and_then(|model| model.default_thinking.as_deref()));
        let ai_thinking_label = ai_model
            .and_then(|model| {
                model
                    .thinking_levels
                    .iter()
                    .find(|(id, _)| Some(id.as_str()) == ai_thinking_id)
                    .map(|(_, label)| label.clone())
            })
            .unwrap_or_default();
        let terminal_font_options =
            merged_terminal_font_options(cx, &settings_state.terminal_font_family);
        let mut settings_selects = [
            (
                "diagnostics-log-level",
                settings_select(
                    window,
                    cx,
                    &["Errors Only", "Warnings", "Normal", "Verbose"],
                    match settings_state.diagnostics_log_level.as_str() {
                        "Error" => "Errors Only",
                        "Warning" => "Warnings",
                        "Debug" => "Verbose",
                        _ => "Normal",
                    },
                    false,
                ),
            ),
            (
                "ai-agent",
                settings_select(
                    window,
                    cx,
                    &[
                        "Codex",
                        "Claude Code",
                        "GitHub Copilot",
                        "Cursor",
                        "Antigravity",
                        "OpenCode",
                        "Pi",
                        "Amp",
                        "Grok Build",
                        "Custom Command",
                    ],
                    ai_agent_label_for_key(&settings_state.ai_text_agent),
                    false,
                ),
            ),
            (
                "ai-model",
                settings_select_owned(window, cx, ai_model_options, &ai_model_label, false),
            ),
            (
                "ai-thinking",
                settings_select_owned(window, cx, ai_thinking_options, &ai_thinking_label, false),
            ),
            (
                "terminal-font",
                settings_select_owned(
                    window,
                    cx,
                    terminal_font_options,
                    &settings_state.terminal_font_family,
                    true,
                ),
            ),
        ]
        .into_iter()
        .map(|(key, state)| (key.to_string(), state))
        .collect::<BTreeMap<_, _>>();
        let skill_runners = ["all", "cli", "orchestration", "computer-use", "emulator"]
            .into_iter()
            .map(|skill| (skill.to_string(), "Auto".to_string()))
            .collect::<BTreeMap<_, _>>();
        for skill in skill_runners.keys() {
            settings_selects.insert(
                format!("skill-runner-{skill}"),
                settings_select(window, cx, &["Auto", "npx", "bunx"], "Auto", false),
            );
        }
        for operation in ["commitMessage", "pullRequestDetails", "workspaceIdentity"] {
            let prompt = settings_state
                .ai_text_prompt_settings_by_operation
                .get(operation);
            let effective_agent = prompt
                .and_then(|prompt| prompt.agent.as_deref())
                .unwrap_or(&settings_state.ai_text_agent);
            let global_agent_label = format!(
                "Global ({})",
                ai_text_settings_catalog::agent_label(&settings_state.ai_text_agent)
            );
            let selected_agent_label = prompt
                .and_then(|prompt| prompt.agent.as_deref())
                .map(ai_text_settings_catalog::agent_label)
                .map(str::to_string)
                .unwrap_or_else(|| global_agent_label.clone());
            let agent_options = std::iter::once(global_agent_label)
                .chain(
                    ai_text_settings_catalog::agents()
                        .iter()
                        .map(|(_, label)| (*label).to_string()),
                )
                .collect();
            settings_selects.insert(
                format!("ai-prompt-{operation}-agent"),
                settings_select_owned(window, cx, agent_options, &selected_agent_label, false),
            );

            let inherited_model_id =
                ai_text_settings_catalog::selected_model_id(&settings_state, effective_agent);
            let model_choices =
                ai_text_settings_catalog::model_choices(&settings_state, effective_agent);
            let inherited_model_label = model_choices
                .iter()
                .find(|model| model.id == inherited_model_id)
                .map(|model| model.label.as_str())
                .unwrap_or(&inherited_model_id);
            let global_model_label = format!("Global ({inherited_model_label})");
            let selected_model_label = prompt
                .and_then(|prompt| prompt.model.as_deref())
                .map(|model| {
                    model_choices
                        .iter()
                        .find(|choice| choice.id == model)
                        .map(|choice| choice.label.clone())
                        .unwrap_or_else(|| model.to_string())
                })
                .unwrap_or_else(|| global_model_label.clone());
            let mut model_options = std::iter::once(global_model_label)
                .chain(model_choices.iter().map(|model| model.label.clone()))
                .collect::<Vec<_>>();
            if let Some(model) = prompt.and_then(|prompt| prompt.model.as_deref()) {
                if !model_options.iter().any(|candidate| candidate == model) {
                    model_options.push(model.to_string());
                }
            }
            settings_selects.insert(
                format!("ai-prompt-{operation}-model"),
                settings_select_owned(window, cx, model_options, &selected_model_label, false),
            );
        }
        let tab_rename_input = cx.new(|cx| InputState::new(window, cx).placeholder("Tab Name"));
        let sidebar_action_input = cx.new(|cx| InputState::new(window, cx).placeholder("New Name"));
        let sidebar_tag_input = cx.new(|cx| InputState::new(window, cx).placeholder("New Tag"));
        let sidebar_parent_filter_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Search workspaces"));
        let explorer_name_input = cx.new(|cx| InputState::new(window, cx));
        let editor_input = cx.new(|cx| {
            InputState::new(window, cx)
                .code_editor("text")
                .soft_wrap(false)
        });
        let search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search")
                .clean_on_escape()
        });
        let replace_input = cx.new(|cx| InputState::new(window, cx).placeholder("Replace"));
        let search_include_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Files to include"));
        let search_exclude_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Files to exclude"));
        let commit_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Message")
                .multi_line(true)
                .soft_wrap(true)
        });
        let source_amend_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Message")
                .multi_line(true)
                .soft_wrap(true)
        });
        let source_control_filter_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Filter Files..."));
        let forge_title_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Pull Request Title"));
        let forge_body_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Pull Request Description")
                .multi_line(true)
                .soft_wrap(true)
        });
        let forge_base_input = cx.new(|cx| InputState::new(window, cx).placeholder("Base Branch"));
        let forge_comment_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Add A Comment"));
        let forge_link_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("#123 Or Pull Request URL"));
        let run_policy_reason_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Rejection Reason"));
        forge_base_input.update(cx, |input, cx| {
            input.set_value("main", window, cx);
        });
        forge_title_input.update(cx, |input, cx| {
            input.set_value("main", window, cx);
        });
        let mut subscriptions = vec![
            cx.subscribe_in(
                &editor_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) && this.editor_document.is_some() {
                        this.editor_dirty = true;
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &sidebar_filter_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &sidebar_project_filter_input,
                window,
                |this, _, event: &InputEvent, window, cx| {
                    if matches!(event, InputEvent::PressEnter { .. }) {
                        this.add_first_sidebar_project_filter(window, cx);
                    } else if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &sidebar_view_tag_filter_input,
                window,
                |this, _, event: &InputEvent, window, cx| {
                    if matches!(event, InputEvent::PressEnter { .. }) {
                        this.add_first_sidebar_view_tag_filter(window, cx);
                    } else if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &local_project_path_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &clone_project_url_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &clone_project_destination_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &sidebar_parent_filter_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &workspace_directory_input,
                window,
                |this, input, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Blur | InputEvent::PressEnter { .. }) {
                        this.set_workspace_directory(input.read(cx).value().to_string(), cx);
                    }
                },
            ),
            cx.subscribe_in(
                &editor_theme_search_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &terminal_theme_search_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &settings_search_input,
                window,
                |this, input, event: &InputEvent, window, cx| {
                    if !matches!(event, InputEvent::Change) {
                        return;
                    }
                    let query = input.read(cx).value().trim().to_lowercase();
                    if !settings_search_catalog::pane_matches(this.settings_pane, &query) {
                        if let Some(pane) = SettingsPane::ALL
                            .into_iter()
                            .find(|pane| settings_search_catalog::pane_matches(*pane, &query))
                        {
                            this.settings_pane = pane;
                            if pane == SettingsPane::MobileDevices {
                                this.refresh_mobile_access(window, cx);
                            }
                            if pane == SettingsPane::Projects {
                                this.refresh_project_config_settings(window, cx);
                            }
                            if pane == SettingsPane::AiText {
                                this.auto_discover_configured_ai_models(window, cx);
                            }
                        }
                    }
                    cx.notify();
                },
            ),
            cx.subscribe_in(
                &workspace_project_search_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &workspace_branch_search_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &workspace_branch_input,
                window,
                |this, input, event: &InputEvent, window, cx| {
                    if !matches!(event, InputEvent::Change) || this.workspace_reuse_existing_branch
                    {
                        return;
                    }
                    let branch = input.read(cx).value().trim().to_string();
                    let current_name = this
                        .workspace_name_input
                        .read(cx)
                        .value()
                        .trim()
                        .to_string();
                    if current_name.is_empty()
                        || this.workspace_synced_name.as_deref() == Some(current_name.as_str())
                    {
                        this.workspace_name_input.update(cx, |input, cx| {
                            input.set_value(branch.clone(), window, cx);
                        });
                        this.workspace_synced_name = (!branch.is_empty()).then_some(branch);
                    }
                    cx.notify();
                },
            ),
            cx.subscribe_in(
                &mobile_access.bind_host_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &mobile_access.endpoint_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &mobile_access.device_name_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &project_config_settings.prompt_append_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(&commit_input, window, |_, _, event: &InputEvent, _, cx| {
                if matches!(event, InputEvent::Change) {
                    cx.notify();
                }
            }),
            cx.subscribe_in(
                &source_control_filter_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &search_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::PressEnter { .. }) {
                        this.search_workspace(cx);
                    } else if matches!(event, InputEvent::Change) {
                        this.replace_confirmation = None;
                        this.schedule_workspace_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &replace_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.replace_confirmation = None;
                        this.schedule_workspace_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &search_include_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.replace_confirmation = None;
                        this.schedule_workspace_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &search_exclude_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.replace_confirmation = None;
                        this.schedule_workspace_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &workspace_dropdown_search_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                    if matches!(event, InputEvent::PressEnter { .. }) {
                        this.confirm_workspace_prompt_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &agent_profile_settings.name_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &agent_profile_settings.command_input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &agent_profile_settings.dropdown_filter_input,
                window,
                |this, _, event: &InputEvent, window, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.agent_profile_settings.dropdown_highlighted_index = 0;
                        cx.notify();
                    }
                    if matches!(event, InputEvent::PressEnter { .. }) {
                        this.confirm_agent_profile_dropdown_filter(window, cx);
                    }
                },
            ),
            cx.subscribe_in(
                &forge_link_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.forge_form_error = None;
                        cx.notify();
                    }
                },
            ),
        ];
        for (key, input) in agent_profile_settings.managed_inputs() {
            subscriptions.push(cx.subscribe_in(
                &input,
                window,
                move |this, input, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.apply_agent_profile_managed_input(
                            key,
                            input.read(cx).value().to_string(),
                            cx,
                        );
                    }
                },
            ));
        }
        for (key, select) in &settings_selects {
            let key = key.clone();
            subscriptions.push(cx.subscribe_in(
                select,
                window,
                move |this,
                      _,
                      event: &SelectEvent<SearchableVec<SettingsSelectOption>>,
                      window,
                      cx| {
                    if let SelectEvent::Confirm(Some(value)) = event {
                        this.apply_settings_select(&key, value.to_string(), window, cx);
                    }
                },
            ));
        }
        for (key, input) in &settings_inputs {
            let key = key.clone();
            subscriptions.push(cx.subscribe_in(
                input,
                window,
                move |this, input, event: &InputEvent, _, cx| {
                    let commit = matches!(event, InputEvent::Blur | InputEvent::PressEnter { .. });
                    if commit || matches!(event, InputEvent::Change) {
                        this.apply_settings_input(
                            &key,
                            input.read(cx).value().to_string(),
                            commit,
                            cx,
                        );
                    }
                },
            ));
        }
        workspace_directory_input.update(cx, |input, cx| {
            input.set_value(settings_state.workspace_directory.clone(), window, cx);
        });
        let workspace_service = WorkspaceService::start(bridge.clone());
        let settings_scroll_handle = ScrollHandle::new();
        let settings_group_anchors = SettingsPane::ALL
            .into_iter()
            .flat_map(|pane| {
                settings_dialog::settings_pane_groups(pane)
                    .iter()
                    .enumerate()
                    .map({
                        let settings_scroll_handle = settings_scroll_handle.clone();
                        move |(index, _)| {
                            (
                                (pane, index),
                                ScrollAnchor::for_handle(settings_scroll_handle.clone()),
                            )
                        }
                    })
            })
            .collect();
        Self {
            bridge,
            snapshot: WorkbenchSnapshot::default(),
            selected_workspace_id: None,
            pending_workspace_terminal_id: None,
            selected_tab_id: None,
            tab_rename_input,
            show_tab_rename_dialog: false,
            tab_mutation_busy: false,
            tab_close_armed: None,
            workbench_menu: None,
            tab_drop_target: None,
            pane_drop_target: None,
            tab_pointer_drag: None,
            tab_pointer_drag_generation: 0,
            tab_bar_bounds: BTreeMap::new(),
            tab_chip_bounds: BTreeMap::new(),
            pane_bounds: BTreeMap::new(),
            split_resize: None,
            panel_resize: None,
            resize_persist_generation: 0,
            connection_label: "Runtime Connecting".into(),
            error: None,
            refresh_generation: 0,
            terminal_sessions: BTreeMap::new(),
            terminal_drivers: BTreeMap::new(),
            terminal_driver_collapsed: BTreeSet::new(),
            terminal_driver_reclaiming: BTreeSet::new(),
            terminal_surface_bounds: BTreeMap::new(),
            terminal_focus,
            terminal_input_text: String::new(),
            terminal_marked_text: None,
            terminal_scrollbar_drag: None,
            terminal_hovered_link: None,
            terminal_restart_confirmation: None,
            terminal_cursor_visible: true,
            terminal_cursor_last_activity: Instant::now(),
            sidebar_collapsed: false,
            sidebar_width: 300.0,
            collapsed_project_ids: BTreeSet::new(),
            sidebar_collapsed_parent_workspace_ids: BTreeSet::new(),
            sidebar_expanded_workspace_ids: BTreeSet::new(),
            sidebar_pinned_collapsed: false,
            sidebar_all_collapsed: false,
            show_sidebar_view_options: false,
            sidebar_group_by: SidebarGroupBy::default(),
            sidebar_project_sort: SidebarSortBy::default(),
            sidebar_workspace_sort: SidebarSortBy::default(),
            sidebar_selected_project_ids: BTreeSet::new(),
            sidebar_view_selected_tag_ids: BTreeSet::new(),
            sidebar_workspace_kind: SidebarWorkspaceKind::default(),
            sidebar_repeat_pinned: true,
            sidebar_sort_dropdown: None,
            sidebar_menu: None,
            sidebar_menu_position: gpui::point(px(70.0), px(116.0)),
            sidebar_dialog: None,
            sidebar_action_input,
            sidebar_tag_input,
            sidebar_parent_filter_input,
            sidebar_action_busy: false,
            sidebar_selected_tag_ids: BTreeSet::new(),
            sidebar_selected_parent_id: None,
            sidebar_tag_delete_armed: None,
            sidebar_parent_dropdown_open: false,
            context_panel: ContextPanel::Explorer,
            context_sidebar_collapsed: false,
            context_sidebar_width: 400.0,
            workbench_view_prefs_raw: serde_json::json!({}),
            status_popover: StatusPopover::None,
            status_popover_pinned: false,
            status_popover_trigger_hovered: None,
            status_popover_panel_hovered: false,
            status_popover_hover_suppressed: None,
            status_popover_transition_generation: 0,
            status_popover_anchor_x: 8.0,
            status_data: StatusData::default(),
            codex_reset_offer_revision: None,
            codex_reset_busy: false,
            quota_tui_busy_key: None,
            resource_sort_column: "memory".to_owned(),
            resource_collapsed_project_ids: BTreeSet::new(),
            resource_close_confirmation: None,
            show_settings_dialog: false,
            settings_previous_focus: None,
            settings_pane: SettingsPane::Application,
            settings_scroll_handle,
            settings_group_anchors,
            settings_state,
            settings_store,
            keyboard_settings,
            mobile_access,
            project_config_settings,
            ai_model_discovery_busy: BTreeSet::new(),
            ai_model_discovery_errors: BTreeMap::new(),
            ai_model_auto_discovered: BTreeSet::new(),
            workspace_service,
            explorer_rows: Vec::new(),
            explorer_hide_ignored: true,
            explorer_name_input,
            explorer_create_directory: None,
            explorer_create_parent: String::new(),
            explorer_rename_path: None,
            explorer_delete_path: None,
            explorer_menu: None,
            explorer_menu_position: gpui::point(px(820.0), px(120.0)),
            explorer_selected_path: None,
            explorer_clipboard: None,
            explorer_action_busy: false,
            explorer_watch_generation: 0,
            editor_document: None,
            opened_file_path: None,
            editor_loading_path: None,
            pending_editor_cursor: None,
            preview_asset: None,
            show_preview: false,
            sidebar_filter_input,
            sidebar_project_filter_input,
            sidebar_view_tag_filter_input,
            local_project_path_input,
            clone_project_url_input,
            clone_project_destination_input,
            project_display_name_input,
            add_project_mode: AddProjectMode::default(),
            show_add_project_dialog: false,
            add_project_busy: false,
            workspace_prompt_input,
            workspace_dropdown_search_input,
            workspace_project_search_input,
            workspace_branch_search_input,
            workspace_branch_input,
            workspace_name_input,
            settings_search_input,
            workspace_directory_input,
            editor_theme_search_input,
            terminal_theme_search_input,
            settings_inputs,
            settings_selects,
            skill_runners,
            claude_profile_alias_input,
            claude_profile_name_input,
            show_claude_profile_dialog: false,
            editing_claude_profile_index: None,
            claude_profile_error: None,
            new_workspace_mode: NewWorkspaceMode::default(),
            new_workspace_step: NewWorkspaceStep::default(),
            selected_workspace_project_id: None,
            selected_workspace_source_branch: None,
            workspace_source_branches: Vec::new(),
            workspace_local_branches: Vec::new(),
            workspace_branches_loading: false,
            workspace_reuse_existing_branch: false,
            workspace_synced_name: None,
            workspace_prompt_dropdown: None,
            workspace_selected_parent_id: None,
            workspace_agent_profiles: Vec::new(),
            workspace_selected_agent_profile_id: None,
            workspace_profiles_loading: false,
            agent_profile_settings,
            create_another_workspace: false,
            show_new_workspace_dialog: false,
            workspace_creation_busy: false,
            workspace_prompt_phase: None,
            workspace_prompt_active_operation_id: None,
            workspace_prompt_created: None,
            editor_input,
            editor_dirty: false,
            editor_conflict: false,
            search_input,
            replace_input,
            search_include_input,
            search_exclude_input,
            search_replace_expanded: false,
            search_details_expanded: false,
            search_case_sensitive: false,
            search_whole_word: false,
            search_use_regex: false,
            search_preserve_case: false,
            search_include_ignored: false,
            search_view_as_tree: false,
            search_collapsed_result_paths: BTreeSet::new(),
            search_input_generation: 0,
            commit_input,
            source_amend_input,
            source_control_filter_input,
            source_control_filter_visible: false,
            source_control_tree_mode: false,
            source_control_menu_open: false,
            source_control_collapsed_sections: BTreeSet::new(),
            source_control_collapsed_tree_nodes: BTreeSet::new(),
            forge_title_input,
            forge_body_input,
            forge_base_input,
            forge_comment_input,
            forge_link_input,
            run_policy_reason_input,
            show_execution_plans: false,
            run_policies: Vec::new(),
            run_policies_loading: false,
            run_policy_busy_id: None,
            run_policy_error: None,
            search_results: SearchResults::default(),
            replace_confirmation: None,
            git_snapshot: GitSnapshot::default(),
            git_diff: GitDiffResult::default(),
            git_diff_loading_tab: None,
            git_diff_loaded_tab: None,
            git_history_expanded: false,
            source_history_expanded_ids: BTreeSet::new(),
            source_history_loading_ids: BTreeSet::new(),
            source_history_action_menu: None,
            source_history_files: BTreeMap::new(),
            source_control_dialog: None,
            git_discard_armed: false,
            git_discard_path_armed: None,
            source_commit_ai_operation_id: None,
            source_commit_ai_busy: false,
            forge_service: ForgeService::start(),
            forge_snapshot: ForgeSnapshot::default(),
            forge_generation: 0,
            forge_busy: false,
            forge_ai_operation_id: None,
            forge_ai_busy: false,
            forge_review_action: None,
            forge_review_action_menu_open: false,
            forge_review_confirmation: None,
            forge_review_editing: false,
            forge_review_base_menu_open: false,
            forge_expanded_checks: BTreeSet::new(),
            forge_collapsed_check_groups: BTreeSet::new(),
            forge_base_menu_open: false,
            forge_create_menu_open: false,
            forge_create_draft: false,
            forge_link_form_open: false,
            forge_form_error: None,
            runtime_action_busy: false,
            runtime_action_armed: None,
            runtime_restart_after_stop: false,
            local_generation: 0,
            local_busy: false,
            local_message: None,
            _subscriptions: subscriptions,
            _event_task: Task::ready(()),
            _cursor_blink_task: Task::ready(()),
        }
    }
}
