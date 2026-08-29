use super::app_helpers::is_snapshot_event;
use super::*;
use std::path::Path;

impl AleraApp {
    fn mark_terminal_sessions_unavailable(&mut self, message: String) {
        for session in self.terminal_sessions.values_mut() {
            session.attaching = false;
            session.operation = None;
            session.operation_started_at = None;
            session.error = Some(message.clone());
        }
    }

    pub fn start(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.connection_label = "Runtime Starting".into();
        self.apply_saved_keyboard_overrides(cx);
        self._subscriptions
            .push(cx.observe_window_activation(window, |this, window, cx| {
                this.terminal_app_foreground = window.is_window_active();
                if !window.is_window_active() {
                    this.cancel_window_pointer_gestures(cx);
                } else {
                    this.flush_terminal_output_frames(cx);
                    this.refresh_terminal_frame_views(cx);
                }
            }));
        let app = cx.entity().downgrade();
        self._subscriptions
            .push(cx.intercept_keystrokes(move |event, window, cx| {
                let Some(app) = app.upgrade() else {
                    return;
                };
                let keystroke = event.keystroke.clone();
                app.update(cx, |this, cx| {
                    if !this.show_settings_dialog
                        && keystroke.key.eq_ignore_ascii_case("escape")
                        && this.dismiss_top_overlay_on_escape(window, cx)
                    {
                        cx.stop_propagation();
                        return;
                    }
                    if this.keyboard_settings.recording_id.is_some() {
                        this.capture_keyboard_keystroke(&keystroke, window, cx);
                    }
                });
            }));
        let events = self.bridge.events();
        self._cursor_blink_task = cx.spawn_in(window, async move |this, cx| loop {
            cx.background_executor()
                .timer(Duration::from_millis(530))
                .await;
            let Some(this) = this.upgrade() else {
                break;
            };
            this.update(cx, |this, cx| {
                let toast_changed = this.expire_local_message();
                let operation_active = this
                    .terminal_sessions
                    .values()
                    .any(|session| session.operation.is_some());
                if !this.settings_state.terminal_cursor_blink
                    || this.selected_terminal_session_id().is_none()
                {
                    let cursor_was_hidden = !this.terminal_cursor_visible;
                    if !this.terminal_cursor_visible {
                        this.terminal_cursor_visible = true;
                    }
                    if operation_active || cursor_was_hidden || toast_changed {
                        cx.notify();
                    }
                    return;
                }
                if this.terminal_cursor_last_activity.elapsed() < Duration::from_millis(530) {
                    let cursor_was_hidden = !this.terminal_cursor_visible;
                    if !this.terminal_cursor_visible {
                        this.terminal_cursor_visible = true;
                    }
                    if operation_active || cursor_was_hidden || toast_changed {
                        cx.notify();
                    }
                    return;
                }
                this.terminal_cursor_visible = !this.terminal_cursor_visible;
                cx.notify();
            });
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
                let terminal_output = matches!(&event, BridgeEvent::TerminalOutput { .. });
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
                let runtime_settings_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. } if name == "runtimeSettingsChanged"
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
                let automations_changed = matches!(
                    &event,
                    BridgeEvent::Notification { name, .. }
                        if matches!(name.as_str(), "automationsChanged" | "automationRunChanged")
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
                            // Quota visibility, provider ordering and agent
                            // hooks are shared runtime preferences. Hydrate
                            // them on every connection so a GPUI client
                            // opened beside Flutter renders the same state
                            // before the user visits Settings.
                            this.refresh_settings_values(cx);
                        }
                        BridgeEvent::Unavailable => {
                            this.connection_label = "Runtime Unavailable".into();
                            // Flutter does not invalidate its keep-alive quota
                            // provider when the runtime lifecycle changes. Keep
                            // the last successful quota snapshot until its own
                            // scheduled or manual refresh succeeds or fails.
                            this.status_data.resource_generation += 1;
                            this.status_data.resources = None;
                            this.status_data.resource_error =
                                Some("Alera Runtime Is Unavailable.".to_owned());
                            this.status_data.presence_generation += 1;
                            this.status_data.presence.clear();
                            this.status_data.runtime_generation += 1;
                            this.status_data.runtime = None;
                            this.status_data.runtime_loading = false;
                            this.status_data.runtime_error = None;
                            this.mark_terminal_sessions_unavailable(
                                "Terminal host unavailable: Alera Runtime Is Unavailable.".into(),
                            );
                        }
                        BridgeEvent::Disconnected { reason } => {
                            this.connection_label = "Runtime Reconnecting".into();
                            this.status_data.resource_generation += 1;
                            this.status_data.resources = None;
                            this.status_data.resource_error = Some(reason.clone());
                            this.status_data.presence_generation += 1;
                            this.status_data.presence.clear();
                            this.status_data.runtime_generation += 1;
                            this.status_data.runtime = None;
                            this.status_data.runtime_loading = false;
                            this.status_data.runtime_error = Some(reason.clone());
                            this.mark_terminal_sessions_unavailable(format!(
                                "Terminal host unavailable: {reason}"
                            ));
                            this.error = Some(reason.into());
                        }
                        BridgeEvent::Notification { name, payload } => {
                            if name == "codexThreadChanged" {
                                this.handle_codex_notification(&payload, window, cx);
                            }
                            if name == "codexCatalogChanged" {
                                // Skills and apps can change while the Codex
                                // tab is open. The next render re-queries the
                                // catalog for the selected tab instead of
                                // leaving stale slash-command choices visible.
                                this.codex_catalogs_loaded = false;
                                this.codex_catalogs_loading = false;
                            }
                            if name == "agentCanvasChanged"
                                && this.context_panel == ContextPanel::AgentCanvas
                            {
                                this.refresh_agent_canvas(cx);
                            }
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
                    if runtime_settings_changed {
                        this.refresh_settings_values(cx);
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
                    if automations_changed && this.show_automations_dialog {
                        this.load_automations(cx);
                    }
                    if !terminal_output {
                        cx.notify();
                    }
                });
            }
        });
        self.refresh(cx);
        // The bridge can finish connecting before the window subscribes to its
        // event stream. Hydrate shared/local view preferences explicitly so a
        // relaunch cannot fall back to GPUI defaults while Flutter restores
        // the persisted sidebar widths and grouping immediately.
        self.load_sidebar_view_prefs(cx);
        self.refresh_status_data(cx);
        self.ensure_explorer_watcher(cx);
    }

    fn cancel_window_pointer_gestures(&mut self, cx: &mut Context<Self>) {
        let changed = self.tab_pointer_drag.take().is_some()
            || self.tab_drop_target.take().is_some()
            || self.pane_drop_target.take().is_some()
            || self.panel_resize.take().is_some()
            || self.split_resize.take().is_some()
            || self.explorer_drop_target.take().is_some()
            || self.explorer_pointer_down.take().is_some()
            || std::mem::take(&mut self.explorer_pointer_dragged)
            || self.preview_drag.take().is_some()
            || self.terminal_selection_drag.take().is_some()
            || self.terminal_scrollbar_drag.take().is_some();
        if changed {
            self.tab_pointer_drag_generation = self.tab_pointer_drag_generation.wrapping_add(1);
            cx.notify();
        }
    }

    /// Keep transient feedback aligned with Flutter's toast host. Every
    /// global `local_message` assignment is observed here, so call sites keep
    /// their existing success/error semantics while stale toasts disappear
    /// after the same four-second duration. The host keeps the latest three
    /// entries instead of replacing a visible toast when another action
    /// completes immediately afterwards.
    fn expire_local_message(&mut self) -> bool {
        const TOAST_DURATION: Duration = Duration::from_secs(4);
        const TOAST_EXIT_DURATION: Duration = Duration::from_millis(180);
        let mut changed = false;
        if let Some(message) = self.local_message.clone() {
            if self.local_message_timer_message.as_ref() != Some(&message) {
                self.local_message_timer_message = Some(message.clone());
                self.local_message_started_at = Some(Instant::now());
                self.toast_entries.push_back((message, Instant::now()));
                changed = true;
            }
        } else {
            changed = self.local_message_started_at.is_some()
                || self.local_message_timer_message.is_some();
            self.local_message_started_at = None;
            self.local_message_timer_message = None;
        }

        let was_exiting = self
            .toast_entries
            .iter()
            .any(|(_, shown_at)| shown_at.elapsed() >= TOAST_DURATION);
        let previous_len = self.toast_entries.len();
        self.toast_entries
            .retain(|(_, shown_at)| shown_at.elapsed() < TOAST_DURATION + TOAST_EXIT_DURATION);
        while self.toast_entries.len() > 3 {
            self.toast_entries.pop_front();
            changed = true;
        }
        let is_exiting = self
            .toast_entries
            .iter()
            .any(|(_, shown_at)| shown_at.elapsed() >= TOAST_DURATION);
        changed |= previous_len != self.toast_entries.len() || was_exiting != is_exiting;

        if self
            .local_message_started_at
            .is_some_and(|started_at| started_at.elapsed() >= TOAST_DURATION)
        {
            self.local_message = None;
            self.local_message_started_at = None;
            self.local_message_timer_message = None;
            changed = true;
        }
        changed
    }

    pub(super) fn visible_toast_entries(&self) -> Vec<(SharedString, bool)> {
        const TOAST_DURATION: Duration = Duration::from_secs(4);
        const TOAST_EXIT_DURATION: Duration = Duration::from_millis(180);
        let mut messages = self
            .toast_entries
            .iter()
            .filter_map(|(message, shown_at)| {
                let elapsed = shown_at.elapsed();
                (elapsed < TOAST_DURATION + TOAST_EXIT_DURATION)
                    .then_some((message.clone(), elapsed >= TOAST_DURATION))
            })
            .collect::<Vec<_>>();
        if let Some(message) = self.local_message.clone() {
            if messages
                .last()
                .is_none_or(|(current, _)| current != &message)
            {
                messages.push((message, false));
            }
        }
        if messages.len() > 3 {
            messages.split_off(messages.len() - 3)
        } else {
            messages
        }
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
            this.update(cx, |this, cx| {
                if generation != this.refresh_generation {
                    return;
                }
                match snapshot {
                    Ok(mut snapshot) => {
                        let next_workspace_id = match this.selected_workspace_id.clone() {
                            Some(id) if snapshot.workspace(&id).is_some() => Some(id),
                            Some(_) => None,
                            None if !this.workspace_selection_initialized => {
                                fallback_workspace_id(&snapshot)
                            }
                            None => None,
                        };
                        this.workspace_selection_initialized = true;
                        if this.selected_workspace_id != next_workspace_id {
                            this.selected_workspace_id = next_workspace_id;
                            this.selected_tab_id = None;
                            this.snapshot = snapshot;
                            this.reset_local_workspace(cx);
                            this.ensure_explorer_watcher(cx);
                            this.refresh(cx);
                            return;
                        }
                        let requested_tab_id = this
                            .pending_workspace_tab_id
                            .take()
                            .filter(|id| snapshot.tabs.iter().any(|tab| &tab.id == id));
                        this.selected_tab_id = requested_tab_id
                            .or_else(|| this.selected_tab_id.clone())
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
                        // From Prompt owns its inline error while the dialog
                        // is open. Workspace creation broadcasts a snapshot
                        // refresh before Agent Profile launch completes, and
                        // clearing the shared slot here would hide the launch
                        // failure and leave Retry Agent without an explanation.
                        if !this.show_new_workspace_dialog {
                            this.error = None;
                        }
                        snapshot.projects.sort_by(|a, b| a.name.cmp(&b.name));
                        let create_terminal_for_selection =
                            this.pending_workspace_terminal_id.as_deref()
                                == this.selected_workspace_id.as_deref()
                                && !snapshot.tabs.iter().any(|tab| tab.kind == "terminal");
                        if create_terminal_for_selection {
                            this.pending_workspace_terminal_id = None;
                        }
                        let workspace_scope_changed = this
                            .selected_workspace_id
                            .as_deref()
                            .map(|workspace_id| {
                                this.snapshot
                                    .workspace(workspace_id)
                                    .map(|workspace| workspace.path.as_str())
                                    != snapshot
                                        .workspace(workspace_id)
                                        .map(|workspace| workspace.path.as_str())
                            })
                            .unwrap_or(true);
                        this.snapshot = snapshot;
                        this.prune_worktree_navigation_history();
                        this.open_pending_workspace_setup(cx);
                        // The selected workspace can change while the
                        // snapshot request is in flight. Rehydrate the
                        // contextual surface from the new workspace path so
                        // Explorer/Git/PR never retain rows or errors from the
                        // previous workspace.
                        if workspace_scope_changed
                            || (this.context_panel != ContextPanel::Search
                                && this.explorer_loaded_workspace_id.as_deref()
                                    != this.selected_workspace_id.as_deref())
                        {
                            this.refresh_local_activity(cx);
                        }
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
                    Err(error) => {
                        crate::app_log::warning(
                            "workbench_snapshot",
                            &format!("snapshot refresh failed: {error}"),
                        );
                        this.error = Some(error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn select_workspace(&mut self, workspace_id: String, cx: &mut Context<Self>) {
        let already_selected = self.selected_workspace_id.as_deref() == Some(&workspace_id);
        if !already_selected && !self.worktree_navigation_replaying {
            self.record_worktree_navigation(&workspace_id);
        }
        if already_selected {
            self.pending_workspace_terminal_id = None;
        } else {
            self.pending_workspace_terminal_id = Some(workspace_id.clone());
        }
        self.selected_workspace_id = Some(workspace_id);
        self.selected_tab_id = None;
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
        } else {
            self.refresh_local_activity(cx);
        }
        cx.notify();
    }

    pub(super) fn go_back(&mut self, cx: &mut Context<Self>) {
        self.prune_worktree_navigation_history();
        let Some(target) = self.worktree_navigation_back.pop() else {
            return;
        };
        if let Some(current) = self.selected_workspace_id.clone() {
            self.worktree_navigation_forward.push(current);
        }
        self.worktree_navigation_replaying = true;
        self.select_workspace(target, cx);
        self.worktree_navigation_replaying = false;
    }

    pub(super) fn go_forward(&mut self, cx: &mut Context<Self>) {
        self.prune_worktree_navigation_history();
        let Some(target) = self.worktree_navigation_forward.pop() else {
            return;
        };
        if let Some(current) = self.selected_workspace_id.clone() {
            self.worktree_navigation_back.push(current);
        }
        self.worktree_navigation_replaying = true;
        self.select_workspace(target, cx);
        self.worktree_navigation_replaying = false;
    }

    fn record_worktree_navigation(&mut self, target: &str) {
        if self.selected_workspace_id.as_deref() == Some(target) {
            return;
        }
        if let Some(current) = self.selected_workspace_id.clone() {
            if self.worktree_navigation_back.last() != Some(&current) {
                self.worktree_navigation_back.push(current);
            }
        }
        self.worktree_navigation_forward.clear();
    }

    fn prune_worktree_navigation_history(&mut self) {
        let live = self
            .snapshot
            .projects
            .iter()
            .flat_map(|project| project.workspaces.iter())
            .map(|workspace| workspace.id.as_str())
            .collect::<std::collections::BTreeSet<_>>();
        self.worktree_navigation_back
            .retain(|workspace_id| live.contains(workspace_id.as_str()));
        self.worktree_navigation_forward
            .retain(|workspace_id| live.contains(workspace_id.as_str()));
    }

    pub(super) fn select_workspace_tab(
        &mut self,
        workspace_id: String,
        tab_id: String,
        cx: &mut Context<Self>,
    ) {
        if self.selected_workspace_id.as_deref() == Some(workspace_id.as_str())
            && self.snapshot.tabs.iter().any(|tab| tab.id == tab_id)
        {
            self.pending_workspace_tab_id = None;
            self.activate_workspace_tab(tab_id, cx);
            return;
        }
        self.select_workspace(workspace_id, cx);
        self.pending_workspace_tab_id = Some(tab_id);
        cx.notify();
    }

    pub(super) fn select_context_panel(&mut self, panel: ContextPanel, cx: &mut Context<Self>) {
        if self.context_panel == panel {
            return;
        }
        self.context_panel = panel;
        self.persist_sidebar_view_prefs(cx);
        self.refresh_local_activity(cx);
        if panel == ContextPanel::AgentCanvas {
            self.refresh_agent_canvas(cx);
        }
        self.ensure_explorer_watcher(cx);
        cx.notify();
    }
}

fn fallback_workspace_id(snapshot: &WorkbenchSnapshot) -> Option<String> {
    let mut workspaces = snapshot
        .projects
        .iter()
        .flat_map(|project| &project.workspaces);
    workspaces
        .clone()
        .find(|workspace| workspace.is_pinned && workspace_is_available(workspace))
        .or_else(|| {
            workspaces.clone().find(|workspace| {
                workspace.kind.eq_ignore_ascii_case("main") && workspace_is_available(workspace)
            })
        })
        .or_else(|| {
            workspaces
                .clone()
                .find(|workspace| workspace_is_available(workspace))
        })
        .or_else(|| workspaces.next())
        .map(|workspace| workspace.id.clone())
}

fn workspace_is_available(workspace: &crate::model::Workspace) -> bool {
    workspace.host_id != "local" || Path::new(&workspace.path).exists()
}
