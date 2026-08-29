use super::*;

pub(super) fn is_snapshot_event(name: &str) -> bool {
    matches!(
        name,
        "projectsChanged"
            | "workspacesChanged"
            | "workspaceTabsChanged"
            | "workbenchLayoutsChanged"
            | "workspaceTagsChanged"
            | "workspaceRelationsChanged"
            | "codexThreadChanged"
    )
}

pub(super) fn flutter_state_error(error: impl Into<String>) -> String {
    let error = error.into();
    if error.starts_with("Bad state: ") {
        error
    } else {
        format!("Bad state: {error}")
    }
}

pub(super) fn settings_select(
    window: &mut Window,
    cx: &mut Context<AleraApp>,
    options: &[&str],
    selected: &str,
    searchable: bool,
) -> Entity<SelectState<SearchableVec<SettingsSelectOption>>> {
    let items = options
        .iter()
        .map(|option| SettingsSelectOption::new((*option).to_string()))
        .collect::<Vec<_>>();
    let selected_index = options
        .iter()
        .position(|option| option.eq_ignore_ascii_case(selected))
        .map(|index| IndexPath::default().row(index));
    cx.new(|cx| {
        SelectState::new(SearchableVec::new(items), selected_index, window, cx)
            .searchable(searchable)
    })
}

pub(super) fn settings_select_owned(
    window: &mut Window,
    cx: &mut Context<AleraApp>,
    options: Vec<String>,
    selected: &str,
    searchable: bool,
) -> Entity<SelectState<SearchableVec<SettingsSelectOption>>> {
    let items = options
        .iter()
        .cloned()
        .map(SettingsSelectOption::new)
        .collect::<Vec<_>>();
    let selected_index = options
        .iter()
        .position(|option| option.eq_ignore_ascii_case(selected))
        .map(|index| IndexPath::default().row(index));
    cx.new(|cx| {
        SelectState::new(SearchableVec::new(items), selected_index, window, cx)
            .searchable(searchable)
    })
}

pub(super) fn merged_terminal_font_options(cx: &Context<AleraApp>, selected: &str) -> Vec<String> {
    let fallback = if cfg!(target_os = "macos") {
        &[
            "SF Mono",
            "Menlo",
            "Monaco",
            "JetBrains Mono",
            "Fira Code",
            "monospace",
        ][..]
    } else if cfg!(target_os = "windows") {
        &[
            "Cascadia Mono",
            "Consolas",
            "Lucida Console",
            "JetBrains Mono",
            "Fira Code",
            "monospace",
        ][..]
    } else {
        &[
            "JetBrains Mono",
            "Fira Code",
            "DejaVu Sans Mono",
            "Liberation Mono",
            "Ubuntu Mono",
            "Noto Sans Mono",
            "monospace",
        ][..]
    };
    let mut by_normalized_name = BTreeMap::new();
    for font in cx
        .text_system()
        .all_font_names()
        .into_iter()
        .chain(fallback.iter().map(|font| (*font).to_string()))
        .chain(std::iter::once(selected.to_string()))
    {
        let trimmed = font.trim();
        if trimmed.is_empty() || trimmed.starts_with('.') {
            continue;
        }
        by_normalized_name
            .entry(trimmed.to_lowercase())
            .or_insert_with(|| trimmed.to_string());
    }
    by_normalized_name.into_values().collect()
}

pub(super) fn build_settings_inputs(
    settings: &SettingsState,
    window: &mut Window,
    cx: &mut Context<AleraApp>,
) -> (
    BTreeMap<String, Entity<InputState>>,
    BTreeMap<String, Entity<TextareaState>>,
) {
    let values = vec![
        (
            "host-empty-seconds",
            settings.host_empty_shutdown_delay_seconds.to_string(),
            "30",
            false,
        ),
        (
            "host-detached-seconds",
            settings.host_detached_shutdown_delay_seconds.to_string(),
            "3600",
            false,
        ),
        (
            "editor-tab-size",
            settings.editor_tab_size.to_string(),
            "4",
            false,
        ),
        (
            "editor-autosave-delay",
            settings
                .editor_autosave_delay_seconds
                .clamp(1, 60)
                .to_string(),
            "1",
            false,
        ),
        (
            "terminal-font-size",
            settings.terminal_font_size.to_string(),
            "13",
            false,
        ),
        (
            "terminal-font-weight",
            settings.terminal_font_weight.to_string(),
            "400",
            false,
        ),
        (
            "terminal-line-height",
            settings.terminal_line_height.to_string(),
            "1.3",
            false,
        ),
        (
            "terminal-cursor-opacity",
            settings.terminal_cursor_opacity.to_string(),
            "1",
            false,
        ),
        (
            "terminal-background-opacity",
            settings.terminal_background_opacity.to_string(),
            "1",
            false,
        ),
        (
            "terminal-padding-x",
            settings.terminal_padding_x.to_string(),
            "12",
            false,
        ),
        (
            "terminal-padding-y",
            settings.terminal_padding_y.to_string(),
            "12",
            false,
        ),
        (
            "terminal-tui-scroll",
            settings.terminal_tui_scroll_sensitivity.to_string(),
            "1",
            false,
        ),
        (
            "terminal-scrollback-lines",
            settings.terminal_scrollback_lines.to_string(),
            "10000",
            false,
        ),
        (
            "terminal-host-scrollback-mb",
            (settings.terminal_host_scrollback_bytes / 1_000_000).to_string(),
            "10",
            false,
        ),
        (
            "terminal-buffer-budget-mb",
            settings.terminal_buffer_budget_megabytes.to_string(),
            "256",
            false,
        ),
        (
            "terminal-word-separators",
            settings
                .terminal_word_separators
                .clone()
                .unwrap_or_default(),
            " ()[]{},\"'`",
            false,
        ),
        (
            "terminal-color-foreground",
            settings
                .terminal_color_overrides
                .get("foreground")
                .cloned()
                .unwrap_or_default(),
            "#f5f5f5",
            false,
        ),
        (
            "terminal-color-background",
            settings
                .terminal_color_overrides
                .get("background")
                .cloned()
                .unwrap_or_default(),
            "#101010",
            false,
        ),
        (
            "terminal-color-cursor",
            settings
                .terminal_color_overrides
                .get("cursor")
                .cloned()
                .unwrap_or_default(),
            "#e0e0e0",
            false,
        ),
        (
            "terminal-color-selection",
            settings
                .terminal_color_overrides
                .get("selection")
                .cloned()
                .unwrap_or_default(),
            "#3e4451",
            false,
        ),
        (
            "ai-custom-command",
            settings.ai_assist_custom_command.clone(),
            "llm --system commit-message",
            false,
        ),
        (
            "ai-instructions-commitMessage",
            settings
                .ai_assist_instructions_by_operation
                .get("commitMessage")
                .cloned()
                .unwrap_or_default(),
            "Extra Guidance",
            true,
        ),
        (
            "ai-instructions-pullRequestDetails",
            settings
                .ai_assist_instructions_by_operation
                .get("pullRequestDetails")
                .cloned()
                .unwrap_or_default(),
            "Extra Guidance",
            true,
        ),
        (
            "ai-instructions-workspaceIdentity",
            settings
                .ai_assist_instructions_by_operation
                .get("workspaceIdentity")
                .cloned()
                .unwrap_or_default(),
            "Extra Guidance",
            true,
        ),
        (
            "quota-env-kimiApiKey",
            settings
                .quota_environment
                .get("kimiApiKey")
                .cloned()
                .unwrap_or_else(|| "KIMI_API_KEY".to_string()),
            "KIMI_API_KEY",
            false,
        ),
        (
            "quota-env-zaiApiKey",
            settings
                .quota_environment
                .get("zaiApiKey")
                .cloned()
                .unwrap_or_else(|| "ZAI_API_KEY".to_string()),
            "ZAI_API_KEY",
            false,
        ),
        (
            "quota-env-zaiBaseUrl",
            settings
                .quota_environment
                .get("zaiBaseUrl")
                .cloned()
                .unwrap_or_else(|| "ZAI_BASE_URL".to_string()),
            "ZAI_BASE_URL",
            false,
        ),
        (
            "quota-env-minimaxApiKey",
            settings
                .quota_environment
                .get("minimaxApiKey")
                .cloned()
                .unwrap_or_else(|| "MINIMAX_API_KEY".to_string()),
            "MINIMAX_API_KEY",
            false,
        ),
        (
            "quota-env-minimaxApiHost",
            settings
                .quota_environment
                .get("minimaxApiHost")
                .cloned()
                .unwrap_or_else(|| "MINIMAX_API_HOST".to_string()),
            "MINIMAX_API_HOST",
            false,
        ),
    ];

    let mut inputs = BTreeMap::new();
    let mut textareas = BTreeMap::new();
    for (key, value, placeholder, multi_line) in values {
        if multi_line {
            let input = cx.new(|cx| {
                let mut input = TextareaState::new(window, cx)
                    .placeholder(placeholder)
                    .soft_wrap(true);
                input.set_value(value, window, cx);
                input
            });
            textareas.insert(key.to_string(), input);
        } else {
            let input = cx.new(|cx| {
                let mut input = InputState::new(window, cx).placeholder(placeholder);
                input.set_value(value, window, cx);
                input
            });
            inputs.insert(key.to_string(), input);
        }
    }
    (inputs, textareas)
}

pub(super) fn ai_agent_label_for_key(agent: &str) -> &'static str {
    ai_assist_settings_catalog::agent_label(agent)
}
