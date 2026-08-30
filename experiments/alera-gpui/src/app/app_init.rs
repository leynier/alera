use super::app_helpers::{
    ai_agent_label_for_key, build_settings_inputs, merged_terminal_font_options, settings_select,
    settings_select_owned,
};
use super::*;

impl AleraApp {
    pub fn new(bridge: RuntimeBridge, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let (settings_store, settings_state) = SettingsStore::start();
        let keep_alive_status =
            alera_native::api::keep_alive::set_keep_alive(settings_state.keep_alive_enabled);
        crate::editor_theme::apply_editor_theme(cx, &settings_state.editor_theme);
        crate::app_log::set_level(&settings_state.diagnostics_log_level);
        crate::app_log::set_crash_reporting_enabled(settings_state.crash_reporting_enabled);
        let terminal_focus = cx.focus_handle();
        let shell_focus = super::app_focus::initialize_shell_focus(window, cx);
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
            cx.new(|cx| InputState::new(window, cx).placeholder("/path/to/project"));
        let clone_project_url_input = cx.new(|cx| {
            InputState::new(window, cx).placeholder("https://github.com/owner/repository.git")
        });
        let clone_project_destination_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("/path/to/repository"));
        let project_display_name_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Display Name (Optional)"));
        let workspace_prompt_input = cx.new(|cx| {
            TextareaState::new(window, cx)
                .placeholder("Describe what the agent should build or paste an image")
                .soft_wrap(true)
                .auto_grow(4, 8)
        });
        let terminal_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Terminal")
                .clean_on_escape()
        });
        let terminal_pulse_command_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("r"));
        let terminal_pulse_delay_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("2.000"));
        let quick_open_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Files")
                .clean_on_escape()
        });
        let codex_resume_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Threads")
                .clean_on_escape()
        });
        let command_palette_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search Commands")
                .clean_on_escape()
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
                .placeholder("Search syntax themes")
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
        let claude_profile_usage_name_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Work"));
        let (settings_inputs, settings_textareas) =
            build_settings_inputs(&settings_state, window, cx);
        let keyboard_settings = KeyboardSettingsUiState::new(cx);
        let mobile_access = MobileAccessState::new(window, cx);
        let project_config_settings = ProjectConfigSettingsState::new(window, cx);
        let text_actions_name_input =
            cx.new(|cx| InputState::new(window, cx));
        let text_actions_prompt_input = cx.new(|cx| {
            TextareaState::new(window, cx)
                .placeholder("Describe the replacement to generate.")
                .soft_wrap(true)
                .auto_grow(5, 10)
        });
        let ai_model_id = ai_assist_settings_catalog::selected_model_id(
            &settings_state,
            &settings_state.ai_assist_agent,
        );
        let ai_model_choices = ai_assist_settings_catalog::model_choices(
            &settings_state,
            &settings_state.ai_assist_agent,
        );
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
            .ai_assist_selected_thinking_by_model
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
                    ai_agent_label_for_key(&settings_state.ai_assist_agent),
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
            (
                "terminal-toolbar-corner",
                settings_select(
                    window,
                    cx,
                    &["Top Left", "Top Right", "Bottom Left", "Bottom Right"],
                    match settings_state.terminal_toolbar_corner.as_str() {
                        "topLeft" => "Top Left",
                        "bottomLeft" => "Bottom Left",
                        "bottomRight" => "Bottom Right",
                        _ => "Top Right",
                    },
                    false,
                ),
            ),
        ]
        .into_iter()
        .map(|(key, state)| (key.to_string(), state))
        .collect::<BTreeMap<_, _>>();
        let skill_runners = [
            "all",
            "cli",
            "orchestration",
            "computer-use",
            "emulator",
            "agent-canvas",
        ]
        .into_iter()
        .map(|skill| (skill.to_string(), "Auto".to_string()))
        .collect::<BTreeMap<_, _>>();
        for skill in skill_runners.keys() {
            settings_selects.insert(
                format!("skill-runner-{skill}"),
                settings_select(window, cx, &["Auto", "npx", "bunx"], "Auto", false),
            );
        }
        for &(operation, _) in ai_assist_settings_catalog::PROMPT_OPERATIONS {
            let prompt = settings_state
                .ai_assist_prompt_settings_by_operation
                .get(operation);
            let effective_agent = prompt
                .and_then(|prompt| prompt.agent.as_deref())
                .unwrap_or(&settings_state.ai_assist_agent);
            let global_agent_label = format!(
                "Global ({})",
                ai_assist_settings_catalog::agent_label(&settings_state.ai_assist_agent)
            );
            let selected_agent_label = prompt
                .and_then(|prompt| prompt.agent.as_deref())
                .map(ai_assist_settings_catalog::agent_label)
                .map(str::to_string)
                .unwrap_or_else(|| global_agent_label.clone());
            let agent_options = std::iter::once(global_agent_label)
                .chain(
                    ai_assist_settings_catalog::agents()
                        .iter()
                        .filter(|(id, _)| operation != "speechMessage" || *id != "custom")
                        .map(|(_, label)| (*label).to_string()),
                )
                .collect();
            settings_selects.insert(
                format!("ai-prompt-{operation}-agent"),
                settings_select_owned(window, cx, agent_options, &selected_agent_label, false),
            );

            let inherited_model_id =
                ai_assist_settings_catalog::selected_model_id(&settings_state, effective_agent);
            let model_choices =
                ai_assist_settings_catalog::model_choices(&settings_state, effective_agent);
            let model = model_choices
                .iter()
                .find(|model| model.id == inherited_model_id);
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
            let thinking_options = model
                .into_iter()
                .flat_map(|model| model.thinking_levels.iter())
                .map(|(_, label)| label.clone())
                .collect::<Vec<_>>();
            let selected_thinking_label = model
                .and_then(|model| {
                    let thinking_id = settings_state
                        .ai_assist_selected_thinking_by_operation
                        .get(operation)
                        .and_then(|values| values.get(&inherited_model_id))
                        .map(String::as_str)
                        .or_else(|| {
                            settings_state
                                .ai_assist_selected_thinking_by_model
                                .get(&inherited_model_id)
                                .map(String::as_str)
                        })
                        .or(model.default_thinking.as_deref())?;
                    model
                        .thinking_levels
                        .iter()
                        .find(|(id, _)| id == thinking_id)
                        .map(|(_, label)| label.clone())
                })
                .unwrap_or_default();
            settings_selects.insert(
                format!("ai-prompt-{operation}-thinking"),
                settings_select_owned(
                    window,
                    cx,
                    thinking_options,
                    &selected_thinking_label,
                    false,
                ),
            );
        }
        let tab_rename_input = cx.new(|cx| InputState::new(window, cx).placeholder("Tab Name"));
        let sidebar_action_input = cx.new(|cx| InputState::new(window, cx).placeholder("New Name"));
        let sidebar_tag_input = cx.new(|cx| InputState::new(window, cx).placeholder("New Tag"));
        let sidebar_parent_filter_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Search workspaces"));
        let explorer_name_input = cx.new(|cx| InputState::new(window, cx));
        let editor_input = cx.new(|cx| {
            EditorState::new(window, cx)
                .language("text")
                // Flutter's CodeForge editor keeps soft wrapping enabled. The
                // same setting is important for long Markdown/code lines so
                // the editor surface and vertical rhythm stay comparable.
                .soft_wrap(true)
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
            TextareaState::new(window, cx)
                .placeholder("Message")
                .soft_wrap(true)
        });
        let source_amend_input = cx.new(|cx| {
            TextareaState::new(window, cx)
                .placeholder("Message")
                .soft_wrap(true)
        });
        let source_control_filter_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Filter Files..."));
        let forge_title_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Pull Request Title"));
        let forge_body_input = cx.new(|cx| {
            TextareaState::new(window, cx)
                .placeholder("Description")
                .soft_wrap(true)
        });
        let forge_base_input = cx.new(|cx| InputState::new(window, cx).placeholder("Base Branch"));
        let forge_comment_input = cx.new(|cx| {
            TextareaState::new(window, cx)
                .placeholder("Add A Comment")
                .soft_wrap(true)
        });
        let forge_link_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("#123 Or Pull Request URL"));
        let run_policy_reason_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Rejection Reason"));
        let automation_search_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Search automations")
                .clean_on_escape()
        });
        forge_base_input.update(cx, |input, cx| {
            input.set_value("main", window, cx);
        });
        forge_title_input.update(cx, |input, cx| {
            input.set_value("main", window, cx);
        });
        let mut subscriptions = vec![
            cx.subscribe_in(&text_actions_name_input, window, |_, _, _: &InputEvent, _, cx| cx.notify()),
            cx.subscribe_in(&text_actions_prompt_input, window, |_, _, _: &InputEvent, _, cx| cx.notify()),
            cx.subscribe_in(&workspace_prompt_input, window, |_, _, _: &InputEvent, _, cx| cx.notify()),
            cx.subscribe_in(
                &codex_resume_search_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if !matches!(event, InputEvent::Change) {
                        return;
                    }
                    if let Some(tab_id) = this.codex_resume_dialog_tab.clone() {
                        this.load_codex_resume_threads(tab_id, false, cx);
                    }
                },
            ),
            cx.subscribe_in(
                &editor_input,
                window,
                |this, input, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Focus) {
                        let path = this
                            .editor_inputs
                            .iter()
                            .find(|(_, candidate)| *candidate == input)
                            .map(|(path, _)| path.clone());
                        if let Some(path) = path {
                            this.activate_editor_path_on_focus(&path, cx);
                        }
                        return;
                    }
                    if !matches!(event, InputEvent::Change)
                        || this.editor_input_syncing
                        || this.editor_document.is_none()
                    {
                        return;
                    }
                    if let Some(path) = this.opened_file_path.clone() {
                        this.keep_preview_tab_for_path(&path, cx);
                        let content = input.read(cx).value().to_string();
                        this.editor_buffer_text
                            .insert(path.clone(), content.clone());
                        this.cache_markdown_preview_content(&path, &content);
                        this.editor_dirty_paths.insert(path);
                        this.editor_dirty = true;
                        this.schedule_editor_autosave(cx);
                        cx.notify();
                    }
                },
            ),
            cx.subscribe_in(
                &terminal_search_input,
                window,
                |this, input, event: &InputEvent, _, cx| {
                    if !matches!(event, InputEvent::Change) {
                        return;
                    }
                    this.update_terminal_search_query(input.read(cx).value().to_string(), cx);
                },
            ),
            cx.subscribe_in(
                &quick_open_input,
                window,
                |this, input, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) && this.quick_open_open {
                        this.update_quick_open_query(input.read(cx).value().to_string(), cx);
                    }
                },
            ),
            cx.subscribe_in(
                &command_palette_input,
                window,
                |this, input, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) && this.command_palette_open {
                        this.command_palette_selected_index = 0;
                        this.update_command_palette_query(input.read(cx).value().to_string(), cx);
                    }
                },
            ),
            cx.subscribe_in(
                &tab_rename_input,
                window,
                |this, input, event: &InputEvent, window, cx| {
                    if !matches!(event, InputEvent::Change) || !this.show_tab_rename_dialog {
                        return;
                    }
                    let Some(original) = this.tab_rename_replace_pending.as_deref() else {
                        return;
                    };
                    let value = input.read(cx).value().to_string();
                    let Some(replacement) = value
                        .strip_prefix(original)
                        .filter(|suffix| !suffix.is_empty())
                        .map(str::to_owned)
                    else {
                        return;
                    };
                    this.tab_rename_replace_pending = None;
                    input.update(cx, |input, cx| {
                        input.set_value(replacement, window, cx);
                    });
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
                |this, _, event: &InputEvent, window, cx| {
                    this.on_add_project_input(super::add_project_fields::ProjectField::LocalPath, event, window, cx);
                },
            ),
            cx.subscribe_in(
                &clone_project_url_input,
                window,
                |this, _, event: &InputEvent, window, cx| {
                    this.on_add_project_input(super::add_project_fields::ProjectField::CloneUrl, event, window, cx);
                },
            ),
            cx.subscribe_in(
                &clone_project_destination_input,
                window,
                |this, _, event: &InputEvent, window, cx| {
                    this.on_add_project_input(super::add_project_fields::ProjectField::Destination, event, window, cx);
                },
            ),
            cx.subscribe_in(
                &project_display_name_input,
                window,
                |this, _, event: &InputEvent, window, cx| {
                    this.on_add_project_input(super::add_project_fields::ProjectField::Name, event, window, cx);
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
                    this.settings_search_generation += 1;
                    let generation = this.settings_search_generation;
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
                            if pane == SettingsPane::AiAssist {
                                this.auto_discover_configured_ai_models(window, cx);
                            }
                        }
                    }
                    if query.is_empty() {
                        this.settings_scroll_handle
                            .set_offset(gpui::point(gpui::px(0.0), gpui::px(0.0)));
                    } else if let Some(group_index) =
                        settings_search_catalog::first_matching_group(this.settings_pane, &query)
                    {
                        if let Some(anchor) = this
                            .settings_group_anchors
                            .get(&(this.settings_pane, group_index))
                            .cloned()
                        {
                            // Flutter uses `Scrollable.ensureVisible` after the
                            // settings pane has rebuilt. GPUI's equivalent must
                            // be queued on the next frame so the anchor has a
                            // fresh origin; a timer races pane selection and
                            // can leave the viewport at the old top offset.
                            cx.on_next_frame(window, move |this, window, cx| {
                                if generation == this.settings_search_generation {
                                    anchor.scroll_to(window, cx);
                                }
                            });
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
                        this.schedule_workspace_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &replace_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.schedule_workspace_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &search_include_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        this.schedule_workspace_search(cx);
                    }
                },
            ),
            cx.subscribe_in(
                &search_exclude_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
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
            cx.subscribe_in(
                &automation_search_input,
                window,
                |this, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) && this.show_automations_dialog {
                        this.reconcile_automation_selection(false, cx);
                    }
                },
            ),
        ];
        let quit_bridge = bridge.clone();
        subscriptions.push(cx.on_app_quit(move |_, _| {
            let bridge = quit_bridge.clone();
            async move {
                let _ = alera_native::api::keep_alive::set_keep_alive(false);
                bridge.begin_app_quit();
            }
        }));
        let tab_navigation_interceptor = cx.listener(|this, event, window, cx| {
            this.intercept_tab_navigation_keystroke(event, window, cx);
        });
        subscriptions.push(cx.intercept_keystrokes(tab_navigation_interceptor));
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
                    match event {
                        SelectEvent::Confirm(Some(value)) => {
                            this.apply_settings_select(&key, value.to_string(), window, cx);
                        }
                        SelectEvent::Confirm(None) if key == "terminal-font" => {
                            this.apply_settings_select(&key, String::new(), window, cx);
                        }
                        _ => {}
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
        for (key, input) in &settings_textareas {
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
        let sidebar_scroll_handle = ScrollHandle::new();
        let explorer_scroll_handle = gpui::UniformListScrollHandle::new();
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
            active_project_id: None,
            selected_workspace_id: None,
            pending_workspace_terminal_id: None,
            pending_workspace_setup: None,
            pending_workspace_tab_id: None,
            worktree_navigation_back: Vec::new(),
            worktree_navigation_forward: Vec::new(),
            worktree_navigation_replaying: false,
            selected_tab_id: None,
            tab_rename_input,
            tab_rename_replace_pending: None,
            show_tab_rename_dialog: false,
            tab_mutation_busy: false,
            file_preview_open_path: None,
            file_preview_keep_after_open: false,
            git_preview_open_key: None,
            git_preview_keep_after_open: false,
            git_preview_last_key: None,
            git_preview_last_at: None,
            tab_close_armed: None,
            workbench_menu: None,
            workbench_menu_focus: cx.focus_handle(),
            workbench_menu_previous_focus: None,
            workbench_menu_highlighted: 0,
            tab_drop_target: None,
            pane_drop_target: None,
            tab_pointer_drag: None,
            tab_pointer_drag_generation: 0,
            tab_bar_bounds: BTreeMap::new(),
            tab_chip_bounds: BTreeMap::new(),
            tab_strip_scroll_handles: RefCell::new(BTreeMap::new()),
            pane_bounds: BTreeMap::new(),
            split_resize: None,
            panel_resize: None,
            resize_persist_generation: 0,
            connection_label: "Runtime Connecting".into(),
            error: None,
            refresh_generation: 0,
            terminal_sessions: BTreeMap::new(),
            terminal_frame_views: BTreeMap::new(),
            terminal_search_input,
            terminal_search: None,
            terminal_composer_inputs: BTreeMap::new(),
            terminal_composer_subscriptions: BTreeMap::new(),
            terminal_composer_visible: BTreeSet::new(),
            terminal_composer_menu_open: None,
            terminal_composer_attachments: BTreeMap::new(),
            terminal_composer_attachment_counter: 0,
            terminal_pulse_dialog_session: None,
            terminal_pulse_command_input,
            terminal_pulse_delay_input,
            terminal_pulse_armed: false,
            terminal_pulse_append_enter: true,
            terminal_pulse_busy: false,
            terminal_pulse_error: None,
            terminal_pulse_generation: 0,
            codex_opening_tabs: BTreeSet::new(),
            codex_snapshots: BTreeMap::new(),
            codex_thread_ids: BTreeMap::new(),
            codex_history_next_cursor: BTreeMap::new(),
            codex_history_loading: BTreeSet::new(),
            codex_recovery: BTreeMap::new(),
            codex_sessions_supported: None,
            codex_turn_policy_supported: None,
            codex_capabilities_loading: false,
            codex_session_action_busy: BTreeSet::new(),
            codex_resume_dialog_tab: None,
            codex_resume_threads: Vec::new(),
            codex_resume_next_cursor: None,
            codex_resume_workspace_only: true,
            codex_resume_loading: false,
            codex_resume_error: None,
            codex_resume_search_input,
            codex_composer_inputs: BTreeMap::new(),
            codex_attachments: BTreeMap::new(),
            codex_prompt_history: BTreeMap::new(),
            codex_prompt_history_index: BTreeMap::new(),
            codex_scroll_handle: ScrollHandle::new(),
            codex_scroll_follow: true,
            codex_working_collapsed: false,
            codex_selected_model: settings_state.codex_chat_selected_model.clone(),
            codex_models: Vec::new(),
            codex_collaboration_modes: Vec::new(),
            codex_skills: Vec::new(),
            codex_apps: Vec::new(),
            codex_saved_prompts: Vec::new(),
            codex_saved_prompts_loading: false,
            codex_saved_prompts_workspace: None,
            codex_catalogs_loaded: false,
            codex_catalogs_loading: false,
            codex_error: None,
            codex_menu_open: None,
            codex_raw_logs: false,
            codex_reasoning_effort: settings_state.codex_chat_reasoning_effort.clone(),
            codex_speed_mode: settings_state.codex_chat_speed_mode.clone(),
            codex_permission_mode: settings_state.codex_chat_permission_mode.clone(),
            codex_plan_mode: settings_state.codex_chat_plan_mode,
            codex_collaboration_mode: None,
            codex_queued_messages: BTreeMap::new(),
            codex_collapsed_cells: BTreeSet::new(),
            agent_canvas_generation: 0,
            agent_canvas_confirmation: None,
            agent_canvas_action_epoch: 0,
            agent_canvas_refresh_pending: false,
            agent_canvas_loading: false,
            agent_canvas_error: None,
            agent_canvas_capabilities: None,
            agent_canvas_values: Vec::new(),
            agent_canvas_selected_id: None,
            agent_canvas_show_history: false,
            agent_canvas_busy: false,
            quick_open_input,
            quick_open_open: false,
            quick_open_loading: false,
            quick_open_error: None,
            quick_open_session: None,
            quick_open_matches: Vec::new(),
            quick_open_selected_index: 0,
            quick_open_generation: 0,
            command_palette_input,
            command_palette_open: false,
            command_palette_selected_index: 0,
            command_terminal: None,
            terminal_output_dirty_sessions: BTreeSet::new(),
            terminal_drivers: BTreeMap::new(),
            terminal_driver_collapsed: BTreeSet::new(),
            terminal_driver_reclaiming: BTreeSet::new(),
            terminal_character_width: 7.8,
            terminal_surface_bounds: BTreeMap::new(),
            terminal_toolbar_viewport_bounds: BTreeMap::new(),
            terminal_toolbar_drag: None,
            terminal_toolbar_menu: None,
            terminal_resize_pending: BTreeMap::new(),
            terminal_resize_generation: BTreeMap::new(),
            terminal_output_frame_scheduled: false,
            terminal_output_last_frame_at: Instant::now() - Duration::from_millis(50),
            terminal_app_foreground: true,
            terminal_focus,
            shell_focus,
            terminal_selection_drag: None,
            terminal_marked_text: None,
            terminal_scrollbar_drag: None,
            terminal_scrollbar_last_activity: BTreeMap::new(),
            terminal_hovered_link: None,
            terminal_restart_confirmation: None,
            terminal_cursor_visible: true,
            terminal_cursor_last_activity: Instant::now(),
            sidebar_collapsed: false,
            collapsed_sidebar_focus: cx.focus_handle(),
            sidebar_width: 300.0,
            panel_resize_hovered: None,
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
            sidebar_active_only: false,
            sidebar_repeat_pinned: true,
            sidebar_sort_dropdown: None,
            sidebar_menu: None,
            sidebar_menu_position: gpui::point(px(70.0), px(116.0)),
            sidebar_dialog: None,
            sidebar_storage_impact: None,
            sidebar_action_input,
            sidebar_tag_input,
            sidebar_parent_filter_input,
            sidebar_action_busy: false,
            sidebar_hovered_agent_run_id: None,
            sidebar_selected_tag_ids: BTreeSet::new(),
            sidebar_selected_parent_id: None,
            sidebar_tag_delete_armed: None,
            sidebar_parent_dropdown_open: false,
            context_panel: ContextPanel::Explorer,
            context_sidebar_collapsed: false,
            // Flutter's WorkbenchViewPrefs defaults the right/context sidebar
            // to 280 px. Keep the first render identical before persisted
            // preferences are loaded.
            context_sidebar_width: 280.0,
            workbench_view_prefs_raw: serde_json::json!({}),
            status_popover: StatusPopover::None,
            status_popover_pinned: false,
            status_popover_trigger_hovered: None,
            status_popover_panel_hovered: false,
            status_popover_hover_suppressed: None,
            status_popover_transition_generation: 0,
            status_popover_anchor_x: 8.0,
            status_data: StatusData::default(),
            keep_alive_active: keep_alive_status.active,
            keep_alive_error: keep_alive_status.error.map(Into::into),
            keep_alive_busy: false,
            keep_alive_generation: 0,
            tab_completion_acknowledged: BTreeMap::new(),
            codex_reset_offer_revision: None,
            codex_reset_busy: false,
            quota_tui_busy_key: None,
            show_agent_usage_dialog: false,
            agent_usage_days: 7,
            agent_usage_loading: false,
            agent_usage_error: None,
            agent_usage_snapshot: None,
            agent_usage_cache: BTreeMap::new(),
            agent_usage_generation: 0,
            agent_usage_breakdown_mode: status_usage::UsageBreakdownMode::Profile,
            resource_sort_column: "memory".to_owned(),
            resource_collapsed_project_ids: BTreeSet::new(),
            resource_close_confirmation: None,
            show_settings_dialog: false,
            show_about_dialog: false,
            settings_previous_focus: None,
            settings_pane: SettingsPane::Application,
            settings_project_master_width: 240.0,
            settings_agent_profiles_master_width: 240.0,
            settings_text_actions_master_width: 240.0,
            settings_master_resize: None,
            settings_scroll_handle,
            settings_scroll_last_offset: Cell::new(px(0.0)),
            sidebar_scroll_handle,
            explorer_scroll_handle,
            settings_group_anchors,
            settings_state,
            text_actions_selected_id: None,
            text_actions_creating_new: false,
            text_actions_name_input,
            text_actions_prompt_input,
            text_actions_draft: Default::default(),
            text_actions_menu: None,
            text_actions_menu_epoch: 0,
            text_actions_menu_index: 0,
            text_actions_menu_focus: cx.focus_handle(),
            text_actions_menu_scroll: ScrollHandle::new(),
            text_actions_field_focus: std::array::from_fn(|_| cx.focus_handle()),
            text_actions_field_bounds: std::array::from_fn(|_| std::rc::Rc::new(std::cell::Cell::new(Default::default()))),
            text_actions_delete_id: None,
            text_actions_delete_epoch: 0,
            text_actions_confirm_focus: cx.focus_handle(),
            text_actions_confirm_previous_focus: None,
            text_actions_error: None,
            text_action_operation_id: None,
            text_action_pending: None,
            diagnostics_export_busy: false,
            settings_store,
            keyboard_settings,
            mobile_access,
            project_config_settings,
            ai_model_discovery_busy: BTreeSet::new(),
            ai_model_discovery_errors: BTreeMap::new(),
            ai_model_auto_discovered: BTreeSet::new(),
            workspace_service,
            explorer_rows: Vec::new(),
            explorer_loaded_workspace_id: None,
            explorer_expanded_paths: BTreeSet::new(),
            explorer_hide_ignored: true,
            explorer_name_input,
            explorer_create_directory: None,
            explorer_create_parent: String::new(),
            explorer_rename_path: None,
            explorer_delete_path: None,
            explorer_menu: None,
            explorer_menu_position: gpui::point(px(820.0), px(120.0)),
            explorer_menu_focus: cx.focus_handle(),
            explorer_menu_previous_focus: None,
            explorer_selected_path: None,
            explorer_reveal_pending: None,
            explorer_clipboard: None,
            explorer_drop_target: None,
            explorer_pointer_down: None,
            explorer_pointer_dragged: false,
            explorer_pointer_double_clicked: false,
            explorer_action_busy: false,
            explorer_watch_generation: 0,
            editor_document: None,
            editor_workspaces: Default::default(),
            editor_requests: Default::default(),
            editor_save_all_busy: false,
            editor_inputs: BTreeMap::new(),
            editor_input_subscriptions: BTreeMap::new(),
            editor_documents: BTreeMap::new(),
            editor_load_error_paths: BTreeSet::new(),
            editor_error_messages: BTreeMap::new(),
            editor_buffer_text: BTreeMap::new(),
            editor_dirty_paths: BTreeSet::new(),
            editor_cursor_positions: BTreeMap::new(),
            opened_file_path: None,
            editor_loading_path: None,
            pending_editor_cursor: None,
            preview_asset: None,
            editor_preview_assets: BTreeMap::new(),
            markdown_preview_content: BTreeMap::new(),
            preview_transforms: BTreeMap::new(),
            preview_drag: None,
            show_preview: false,
            sidebar_filter_input,
            sidebar_project_filter_input,
            sidebar_view_tag_filter_input,
            local_project_path_input,
            clone_project_url_input,
            clone_project_destination_input,
            project_display_name_input,
            add_project_mode: AddProjectMode::default(),
            add_project_draft: Default::default(),
            add_project_previous_focus: None,
            show_add_project_dialog: false,
            add_project_busy: false,
            workspace_prompt_input,
            workspace_prompt_scroll_handle: ScrollHandle::new(),
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
            settings_textareas,
            settings_selects,
            skill_runners,
            claude_profile_alias_input,
            claude_profile_name_input,
            claude_profile_usage_name_input,
            show_claude_profile_dialog: false,
            editing_claude_profile_name: None,
            claude_profile_show_in_usage: true,
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
            workspace_prompt_agent_launch_mutation_id: None,
            workspace_prompt_original_agent_launch_idempotent: None,
            editor_input,
            editor_input_syncing: false,
            editor_dirty: false,
            editor_conflict: false,
            editor_autosave_generation: 0,
            search_input,
            replace_input,
            search_include_input,
            search_exclude_input,
            search_replace_expanded: false,
            search_details_expanded: false,
            search_error_is_query_failure: false,
            search_case_sensitive: false,
            search_whole_word: false,
            search_use_regex: false,
            search_preserve_case: false,
            search_include_ignored: false,
            search_view_as_tree: false,
            search_collapsed_result_paths: BTreeSet::new(),
            search_list_state: ListState::new(0, ListAlignment::Top, px(512.0)),
            search_input_generation: 0,
            search_active_request_id: None,
            settings_search_generation: 0,
            commit_input,
            source_amend_input,
            source_control_filter_input,
            source_control_filter_visible: false,
            source_control_tree_mode: true,
            source_control_group_mode: false,
            source_control_menu_open: false,
            source_control_menu_focus: cx.focus_handle(),
            source_control_menu_previous_focus: None,
            source_control_menu_highlighted: 0,
            source_change_context_menu: None,
            source_change_menu_focus: cx.focus_handle(),
            source_change_menu_previous_focus: None,
            source_change_menu_highlighted: 0,
            source_control_collapsed_sections: BTreeSet::new(),
            source_control_collapsed_tree_nodes: BTreeSet::new(),
            forge_title_input,
            forge_body_input,
            forge_base_input,
            forge_comment_input,
            forge_link_input,
            run_policy_reason_input,
            show_execution_plans: false,
            show_automations_dialog: false,
            automation_requests: Default::default(),
            automations: Vec::new(),
            automations_loading: false,
            automations_error: None,
            automation_selected_id: None,
            automation_detail: None,
            automation_detail_error: None,
            automation_detail_tab: Default::default(),
            automation_detail_tab_focus: std::array::from_fn(|_| cx.focus_handle()),
            automation_prompt_selection: gpui_base::TextSelectionHandle::new("", cx),
            automation_detail_loading: false,
            automation_search_input,
            automation_previous_focus: None,
            automation_dialog_focus: cx.focus_handle(),
            automation_filters: Default::default(),
            automation_master_width: 240.0,
            automation_include_trashed: false,
            automation_action_busy: false,
            automation_editor_open: false,
            automation_editor_id: None,
            automation_editor_definition: serde_json::json!({}),
            automation_editor: None,
            automation_action_dialog: None,
            automation_editor_error: None,
            automation_settings_loading: false,
            automation_settings_saving: false,
            automation_settings_loaded: false,
            automation_settings_error: None,
            automation_profile_policy_id: None,
            automation_profile_policy_loading: false,
            automation_profile_policy_error: None,
            automation_profile_policy_activate: false,
            automation_profile_policy_execute: false,
            automation_project_policy_id: None,
            automation_project_policy_loading: false,
            automation_project_policy_error: None,
            automation_project_policy_local_approved: false,
            automation_project_policy_restrictive: false,
            automation_project_policy_repo_declared: false,
            run_policies: Vec::new(),
            run_policies_loading: false,
            run_policy_busy_id: None,
            run_policy_error: None,
            search_results: SearchResults::default(),
            search_error: None,
            git_snapshot: GitSnapshot::default(),
            explorer_git_status: ExplorerGitStatusSnapshot::default(),
            git_snapshot_loading: false,
            git_snapshot_error: None,
            git_diff: GitDiffResult::default(),
            git_diff_loading_tab: None,
            git_diff_loaded_tab: None,
            git_diff_errors: BTreeMap::new(),
            git_diff_image_sides: BTreeMap::new(),
            git_diff_image_loading: BTreeSet::new(),
            reading_diff_service: ReadingDiffService::start(),
            reading_diff_confirmation: None,
            reading_diff_busy_key: None,
            reading_diff_progress: None,
            reading_diff_results: BTreeMap::new(),
            reading_diff_errors: BTreeMap::new(),
            reading_diff_show_original: BTreeSet::new(),
            reading_diff_cancel: None,
            git_history_expanded: false,
            git_history_loaded_once: false,
            git_history_height: 256.0,
            git_history_resize: None,
            source_history_expanded_ids: BTreeSet::new(),
            source_history_loading_ids: BTreeSet::new(),
            source_history_action_menu: None,
            source_history_menu_focus: cx.focus_handle(),
            source_history_menu_previous_focus: None,
            source_history_menu_highlighted: 0,
            source_history_files: BTreeMap::new(),
            source_control_dialog: None,
            git_discard_armed: false,
            git_discard_path_armed: None,
            source_commit_ai_operation_id: None,
            source_commit_ai_busy: false,
            source_commit_ai_hovered: false,
            forge_service: ForgeService::start(),
            forge_snapshot: ForgeSnapshot::default(),
            forge_generation: 0,
            forge_busy: false,
            forge_ai_operation_id: None,
            forge_ai_busy: false,
            forge_ai_hovered: false,
            forge_review_action: None,
            forge_review_action_menu_open: false,
            forge_review_confirmation: None,
            forge_review_editing: false,
            forge_stack_editing: false,
            forge_stack_workspace_editing: false,
            forge_stack_selected_workspace_ids: BTreeSet::new(),
            forge_review_base_menu_open: false,
            forge_comment_composing: false,
            forge_expanded_checks: BTreeSet::new(),
            forge_collapsed_check_groups: BTreeSet::new(),
            forge_base_menu_open: false,
            forge_create_menu_open: false,
            forge_create_draft: false,
            forge_link_form_open: false,
            forge_form_error: None,
            forge_error: None,
            forge_comment_saving_ids: BTreeSet::new(),
            runtime_action_busy: false,
            runtime_action_armed: None,
            runtime_restart_after_stop: false,
            search_generation: 0,
            git_generation: 0,
            explorer_generation: 0,
            editor_generation: 0,
            search_busy: false,
            search_replacing: false,
            git_busy: false,
            explorer_busy: false,
            editor_busy: false,
            local_message: None,
            local_message_started_at: None,
            local_message_timer_message: None,
            toast_entries: std::collections::VecDeque::new(),
            _subscriptions: subscriptions,
            _event_task: Task::ready(()),
            _cursor_blink_task: Task::ready(()),
        }
    }
}
