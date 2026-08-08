impl AleraApp {
    pub(super) fn refresh_settings_values(&mut self, cx: &mut Context<Self>) {
        self.settings_state.generation += 1;
        self.settings_state.loading = true;
        self.settings_state.error = None;
        let generation = self.settings_state.generation;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let runtime = bridge.request("runtimeSettings.get", json!({})).await;
            let status = bridge.request("status.get", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.settings_state.generation {
                    return;
                }
                this.settings_state.loading = false;
                match runtime {
                    Ok(value) => this.settings_state.apply_runtime_settings(&value),
                    Err(error) => this.settings_state.error = Some(error),
                }
                if let Ok(value) = status {
                    this.settings_state.apply_host_status(&value);
                }
                this.settings_store.save(&this.settings_state);
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn set_confirm_project_removal(&mut self, enabled: bool, cx: &mut Context<Self>) {
        self.settings_state.confirm_project_removal = enabled;
        self.update_runtime_setting("confirmProjectRemoval", Value::Bool(enabled), cx);
    }

    pub(super) fn set_workspace_directory(&mut self, directory: String, cx: &mut Context<Self>) {
        let trimmed = directory.trim();
        self.settings_state.workspace_directory = if trimmed.is_empty() {
            "~/.alera/workspaces".to_string()
        } else {
            trimmed.to_string()
        };
        self.update_runtime_setting(
            "workspaceDirectory",
            if trimmed.is_empty() {
                Value::Null
            } else {
                Value::String(trimmed.to_string())
            },
            cx,
        );
    }

    pub(super) fn set_confirm_workspace_removal(&mut self, enabled: bool, cx: &mut Context<Self>) {
        self.settings_state.confirm_workspace_removal = enabled;
        self.update_runtime_setting("confirmWorkspaceRemoval", Value::Bool(enabled), cx);
    }

    pub(super) fn set_keep_runtime_open_on_quit(&mut self, enabled: bool, cx: &mut Context<Self>) {
        self.settings_state.keep_runtime_open_on_quit = enabled;
        self.persist_settings();
        cx.notify();
    }

    pub(super) fn set_crash_reporting_enabled(&mut self, enabled: bool, cx: &mut Context<Self>) {
        self.settings_state.crash_reporting_enabled = enabled;
        crate::app_log::set_crash_reporting_enabled(enabled);
        self.persist_settings();
        self.configure_terminal_host(cx);
    }

    pub(super) fn set_editor_theme(&mut self, theme: String, cx: &mut Context<Self>) {
        self.settings_state.editor_theme = theme;
        self.persist_settings();
        cx.notify();
    }

    pub(super) fn set_terminal_theme(&mut self, theme: String, cx: &mut Context<Self>) {
        self.update_terminal_settings(|settings| settings.terminal_theme_name = theme, cx);
    }

    pub(super) fn update_agent_settings(
        &mut self,
        update: impl FnOnce(&mut SettingsState),
        cx: &mut Context<Self>,
    ) {
        update(&mut self.settings_state);
        self.persist_settings();
        let hooks = serde_json::to_value(&self.settings_state.agent_status_hooks)
            .unwrap_or_else(|_| json!({}));
        self.update_runtime_setting("agentStatusHooks", hooks, cx);
    }

    pub(super) fn update_quota_settings(
        &mut self,
        update: impl FnOnce(&mut SettingsState),
        cx: &mut Context<Self>,
    ) {
        update(&mut self.settings_state);
        self.persist_settings();
        let quotas = self.settings_state.runtime_quota_payload();
        self.update_runtime_setting("agentQuotas", quotas, cx);
    }

    pub(super) fn update_ai_text_settings(
        &mut self,
        update: impl FnOnce(&mut SettingsState),
        cx: &mut Context<Self>,
    ) {
        update(&mut self.settings_state);
        self.persist_settings();
        let ai_text = self.settings_state.runtime_ai_text_payload();
        self.update_runtime_setting("aiTextGeneration", ai_text, cx);
    }

    pub(super) fn update_editor_settings(
        &mut self,
        update: impl FnOnce(&mut SettingsState),
        cx: &mut Context<Self>,
    ) {
        update(&mut self.settings_state);
        self.persist_settings();
        cx.notify();
    }

    pub(super) fn update_terminal_settings(
        &mut self,
        update: impl FnOnce(&mut SettingsState),
        cx: &mut Context<Self>,
    ) {
        update(&mut self.settings_state);
        self.persist_settings();
        self.configure_terminal_host(cx);
    }

    pub(super) fn reset_ai_text_settings(&mut self, cx: &mut Context<Self>) {
        let defaults = SettingsState::default();
        self.update_ai_text_settings(
            |settings| {
                settings.ai_text_enabled = defaults.ai_text_enabled;
                settings.ai_text_agent = defaults.ai_text_agent;
                settings.ai_text_selected_model_by_agent = defaults.ai_text_selected_model_by_agent;
                settings.ai_text_selected_thinking_by_model =
                    defaults.ai_text_selected_thinking_by_model;
                settings.ai_text_custom_command = defaults.ai_text_custom_command;
                settings.ai_text_instructions_by_operation =
                    defaults.ai_text_instructions_by_operation;
                settings.ai_text_prompt_settings_by_operation =
                    defaults.ai_text_prompt_settings_by_operation;
                settings.ai_text_timeout_seconds = defaults.ai_text_timeout_seconds;
            },
            cx,
        );
    }

    pub(super) fn reset_editor_settings(&mut self, cx: &mut Context<Self>) {
        let defaults = SettingsState::default();
        self.update_editor_settings(
            |settings| {
                settings.editor_theme = defaults.editor_theme;
                settings.editor_tab_size = defaults.editor_tab_size;
            },
            cx,
        );
    }

    pub(super) fn reset_terminal_settings(&mut self, cx: &mut Context<Self>) {
        let defaults = SettingsState::default();
        self.update_terminal_settings(
            |settings| {
                settings.terminal_font_family = defaults.terminal_font_family;
                settings.terminal_font_size = defaults.terminal_font_size;
                settings.terminal_font_weight = defaults.terminal_font_weight;
                settings.terminal_line_height = defaults.terminal_line_height;
                settings.terminal_padding_x = defaults.terminal_padding_x;
                settings.terminal_padding_y = defaults.terminal_padding_y;
                settings.terminal_cursor_shape = defaults.terminal_cursor_shape;
                settings.terminal_cursor_blink = defaults.terminal_cursor_blink;
                settings.terminal_cursor_opacity = defaults.terminal_cursor_opacity;
                settings.terminal_theme_name = defaults.terminal_theme_name;
                settings.terminal_background_opacity = defaults.terminal_background_opacity;
                settings.terminal_word_separators = defaults.terminal_word_separators;
                settings.terminal_color_overrides = defaults.terminal_color_overrides;
                settings.terminal_scrollback_lines = defaults.terminal_scrollback_lines;
                settings.terminal_tui_scroll_sensitivity = defaults.terminal_tui_scroll_sensitivity;
                settings.terminal_clipboard_on_select = defaults.terminal_clipboard_on_select;
                settings.terminal_allow_osc52_clipboard = defaults.terminal_allow_osc52_clipboard;
                settings.terminal_host_scrollback_bytes = defaults.terminal_host_scrollback_bytes;
                settings.terminal_buffer_budget_megabytes =
                    defaults.terminal_buffer_budget_megabytes;
                settings.terminal_login_shell = defaults.terminal_login_shell;
                settings.keep_runtime_open_on_quit = defaults.keep_runtime_open_on_quit;
                settings.host_empty_shutdown_delay_seconds =
                    defaults.host_empty_shutdown_delay_seconds;
                settings.host_detached_shutdown_delay_seconds =
                    defaults.host_detached_shutdown_delay_seconds;
            },
            cx,
        );
    }

}
