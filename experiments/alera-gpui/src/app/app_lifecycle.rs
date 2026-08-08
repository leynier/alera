use super::app_helpers::is_snapshot_event;
use super::*;

impl AleraApp {
    pub fn start(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.connection_label = "Runtime Starting".into();
        self.apply_saved_keyboard_overrides(cx);
        let app = cx.entity().downgrade();
        self._subscriptions
            .push(cx.intercept_keystrokes(move |event, window, cx| {
                let Some(app) = app.upgrade() else {
                    return;
                };
                let keystroke = event.keystroke.clone();
                app.update(cx, |this, cx| {
                    if this.keyboard_settings.recording_id.is_some() {
                        this.capture_keyboard_keystroke(&keystroke, window, cx);
                    }
                });
            }));
        let events = self.bridge.events();
        self._cursor_blink_task = cx.spawn_in(window, async move |this, cx| loop {
            Timer::after(Duration::from_millis(530)).await;
            let Some(this) = this.upgrade() else {
                break;
            };
            let result = this.update(cx, |this, cx| {
                if !this.settings_state.terminal_cursor_blink
                    || this.selected_terminal_session_id().is_none()
                {
                    if !this.terminal_cursor_visible {
                        this.terminal_cursor_visible = true;
                        cx.notify();
                    }
                    return;
                }
                if this.terminal_cursor_last_activity.elapsed() < Duration::from_millis(530) {
                    if !this.terminal_cursor_visible {
                        this.terminal_cursor_visible = true;
                        cx.notify();
                    }
                    return;
                }
                this.terminal_cursor_visible = !this.terminal_cursor_visible;
                cx.notify();
            });
            if result.is_err() {
                break;
            }
        });
        self._event_task = cx.spawn_in(window, async move |this, cx| {
            while let Ok(event) = events.recv().await {
                let Some(this) = this.upgrade() else {
                    break;
                };
                let should_refresh = match &event {
                    BridgeEvent::Connected => true,
                    BridgeEvent::Notification { name, .. } => is_snapshot_event(name),
                    _ => false,
                };
                let connected = matches!(&event, BridgeEvent::Connected);
                let quotas_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. } if name == "agentQuotasChanged"
                );
                let presence_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. } if name == "agentPresenceChanged"
                );
                let agent_profiles_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. } if name == "agentProfilesChanged"
                );
                let mobile_access_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. }
                        if matches!(
                            name.as_str(),
                            "mobileSettingsChanged"
                                | "mobilePairingsChanged"
                                | "mobileDevicesChanged"
                                | "mobileGatewayChanged"
                        )
                );
                let project_configs_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. } if name == "projectConfigsChanged"
                );
                let view_prefs_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. } if name == "workbenchViewPrefsChanged"
                );
                let _ = this.update_in(cx, |this, window, cx| {
                    match event {
                        BridgeEvent::Connected => {
                            this.connection_label = "Runtime Connected".into();
                            this.error = None;
                            this.refresh_terminal_drivers(cx);
                        }
                        BridgeEvent::Unavailable => {
                            this.connection_label = "Runtime Unavailable".into();
                        }
                        BridgeEvent::Disconnected { reason } => {
                            this.connection_label = "Runtime Reconnecting".into();
                            this.error = Some(reason.into());
                        }
                        BridgeEvent::Notification { name, payload } => {
                            this.handle_terminal_notification(&name, &payload, cx);
                        }
                        BridgeEvent::TerminalOutput { session_id, data } => {
                            this.handle_terminal_output(&session_id, &data, cx);
                        }
                    }
                    if should_refresh {
                        this.refresh(cx);
                    }
                    if connected {
                        this.refresh_status_data(cx);
                        this.load_sidebar_view_prefs(cx);
                    } else {
                        if quotas_changed {
                            this.refresh_quota_status(false, cx);
                        }
                        if presence_changed {
                            this.refresh_presence_status(cx);
                        }
                    }
                    if view_prefs_changed {
                        this.load_sidebar_view_prefs(cx);
                    }
                    if agent_profiles_changed
                        && this.show_settings_dialog
                        && this.settings_pane == SettingsPane::AgentProfiles
                    {
                        this.refresh_agent_profiles(window, cx);
                    }
                    if mobile_access_changed
                        && this.show_settings_dialog
                        && this.settings_pane == SettingsPane::MobileDevices
                    {
                        this.refresh_mobile_access(window, cx);
                    }
                    if project_configs_changed
                        && this.show_settings_dialog
                        && this.settings_pane == SettingsPane::Projects
                    {
                        this.refresh_project_config_settings(window, cx);
                    }
                    cx.notify();
                });
            }
        });
        self.refresh(cx);
        self.ensure_explorer_watcher(cx);
    }

    pub(super) fn refresh(&mut self, cx: &mut Context<Self>) {
        self.refresh_generation += 1;
        let generation = self.refresh_generation;
        let bridge = self.bridge.clone();
        let selected_workspace_id = self.selected_workspace_id.clone();
        cx.spawn(async move |this, cx| {
            let snapshot = WorkbenchSnapshot::load(&bridge, selected_workspace_id.as_deref()).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.refresh_generation {
                    return;
                }
                match snapshot {
                    Ok(mut snapshot) => {
                        let next_workspace_id = this
                            .selected_workspace_id
                            .clone()
                            .filter(|id| snapshot.workspace(id).is_some())
                            .or_else(|| {
                                snapshot
                                    .projects
                                    .iter()
                                    .flat_map(|project| &project.workspaces)
                                    .next()
                                    .map(|workspace| workspace.id.clone())
                            });
                        if this.selected_workspace_id != next_workspace_id {
                            this.selected_workspace_id = next_workspace_id;
                            this.selected_tab_id = None;
                            this.snapshot = snapshot;
                            this.reset_local_workspace(cx);
                            this.ensure_explorer_watcher(cx);
                            this.refresh(cx);
                            return;
                        }
                        this.selected_tab_id = this
                            .selected_tab_id
                            .clone()
                            .filter(|id| snapshot.tabs.iter().any(|tab| &tab.id == id))
                            .or_else(|| {
                                snapshot.layout.as_ref().and_then(|layout| {
                                    layout
                                        .groups
                                        .get(&layout.active_group_id)
                                        .and_then(|group| group.active_tab_id.clone())
                                })
                            })
                            .or_else(|| snapshot.tabs.first().map(|tab| tab.id.clone()));
                        this.error = None;
                        snapshot.projects.sort_by(|a, b| a.name.cmp(&b.name));
                        let create_terminal_for_selection =
                            this.pending_workspace_terminal_id.as_deref()
                                == this.selected_workspace_id.as_deref()
                                && !snapshot.tabs.iter().any(|tab| tab.kind == "terminal");
                        if create_terminal_for_selection {
                            this.pending_workspace_terminal_id = None;
                        }
                        this.snapshot = snapshot;
                        this.ensure_selected_terminal(cx);
                        if create_terminal_for_selection {
                            this.create_terminal_tab(cx);
                        }
                        if let Some(tab) = this
                            .selected_tab_id
                            .as_deref()
                            .and_then(|id| this.snapshot.tabs.iter().find(|tab| tab.id == id))
                            .filter(|tab| tab.kind == "gitDiff")
                            .filter(|tab| {
                                this.git_diff_loaded_tab.as_deref() != Some(tab.id.as_str())
                                    && this.git_diff_loading_tab.as_deref() != Some(tab.id.as_str())
                            })
                            .cloned()
                        {
                            this.load_git_diff_tab(tab.id, tab.payload, cx);
                        }
                    }
                    Err(error) => this.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn select_workspace(&mut self, workspace_id: String, cx: &mut Context<Self>) {
        let already_selected = self.selected_workspace_id.as_deref() == Some(&workspace_id);
        if already_selected {
            self.pending_workspace_terminal_id = None;
        } else {
            self.pending_workspace_terminal_id = Some(workspace_id.clone());
        }
        self.selected_workspace_id = Some(workspace_id);
        self.selected_tab_id = None;
        self.ensure_context_panel_has_source_control();
        self.ensure_selected_terminal(cx);
        // A workspace can legitimately have no tabs after its last terminal
        // is closed. Selecting it must still provide an actionable workbench,
        // including when it was already the selected workspace.
        if already_selected {
            let has_terminal = self.snapshot.tabs.iter().any(|tab| tab.kind == "terminal");
            if !has_terminal {
                self.create_terminal_tab(cx);
            }
        }
        self.reset_local_workspace(cx);
        self.ensure_explorer_watcher(cx);
        if !already_selected {
            self.refresh(cx);
        }
        cx.notify();
    }

    pub(super) fn select_context_panel(&mut self, panel: ContextPanel, cx: &mut Context<Self>) {
        if matches!(
            panel,
            ContextPanel::SourceControl | ContextPanel::PullRequest
        ) && self.selected_source_control_scope().is_none()
        {
            self.source_control_unavailable_message(cx);
            return;
        }
        if self.context_panel == panel {
            return;
        }
        self.context_panel = panel;
        self.persist_sidebar_view_prefs(cx);
        self.refresh_local_activity(cx);
        self.ensure_explorer_watcher(cx);
        cx.notify();
    }
}
