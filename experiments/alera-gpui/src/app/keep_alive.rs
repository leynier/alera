use gpui::{Context, SharedString};

use super::AleraApp;

impl AleraApp {
    pub(super) fn toggle_keep_alive(&mut self, cx: &mut Context<Self>) {
        if self.keep_alive_busy {
            return;
        }
        self.apply_keep_alive(!self.settings_state.keep_alive_enabled, true, cx);
    }

    pub(super) fn set_keep_alive_enabled(&mut self, enabled: bool, cx: &mut Context<Self>) {
        if self.keep_alive_busy || self.settings_state.keep_alive_enabled == enabled {
            return;
        }
        self.apply_keep_alive(enabled, true, cx);
    }

    pub(super) fn sync_keep_alive_from_settings(&mut self, cx: &mut Context<Self>) {
        if self.keep_alive_busy {
            return;
        }
        let enabled = self.settings_state.keep_alive_enabled;
        if self.keep_alive_active == enabled && self.keep_alive_error.is_none() {
            return;
        }
        self.apply_keep_alive(enabled, false, cx);
    }

    fn apply_keep_alive(
        &mut self,
        enabled: bool,
        persist_on_success: bool,
        cx: &mut Context<Self>,
    ) {
        self.keep_alive_generation = self.keep_alive_generation.wrapping_add(1);
        let generation = self.keep_alive_generation;
        self.keep_alive_busy = true;
        cx.notify();
        cx.spawn(async move |this, cx| {
            let status = alera_native::api::keep_alive::set_keep_alive(enabled);
            let _ = this.update(cx, |this, cx| {
                if this.keep_alive_generation != generation {
                    return;
                }
                this.keep_alive_busy = false;
                this.keep_alive_active = status.active;
                this.keep_alive_error = status.error.clone().map(SharedString::from);
                let applied = !enabled || status.active;
                if persist_on_success && applied {
                    this.settings_state.keep_alive_enabled = enabled;
                    this.persist_settings();
                    this.persist_shared_flutter_settings(
                        this.settings_state.shared_flutter_local_payload(),
                        cx,
                    );
                }
                if enabled && !status.active {
                    this.local_message = Some(
                        match status.error.as_deref().filter(|error| !error.trim().is_empty()) {
                            Some(error) => {
                                format!("Could not keep this computer awake. {error}").into()
                            }
                            None => "Could not keep this computer awake.".into(),
                        },
                    );
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn keep_alive_color(&self) -> gpui::Rgba {
        if self.keep_alive_error.is_some() && !self.keep_alive_active {
            crate::theme::warning()
        } else if self.keep_alive_active || self.settings_state.keep_alive_enabled {
            crate::theme::success()
        } else {
            crate::theme::text_muted()
        }
    }

    pub(super) fn keep_alive_tooltip(&self) -> SharedString {
        if let Some(error) = self
            .keep_alive_error
            .as_ref()
            .filter(|_| !self.keep_alive_active)
        {
            return error.clone();
        }
        if self.keep_alive_active || self.settings_state.keep_alive_enabled {
            "Keeping this computer and display awake".into()
        } else {
            "Keep this computer and display awake".into()
        }
    }
}
