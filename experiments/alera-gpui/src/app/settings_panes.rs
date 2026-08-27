use gpui::{
    div, prelude::FluentBuilder as _, px, rgb, AnyElement, AppContext as _, Context, CursorStyle,
    Entity, InteractiveElement as _, IntoElement, IsZero as _, MouseButton, MouseDownEvent,
    ParentElement as _, ScrollWheelEvent, SharedString, StatefulInteractiveElement as _,
    Styled as _,
};
use gpui_component::input::InputState;
use gpui_component::scroll::{ScrollableElement as _, Scrollbar};
use gpui_component::select::{SearchableVec, Select, SelectEvent, SelectState};
use gpui_component::tooltip::Tooltip;
use std::collections::{BTreeMap, BTreeSet};

use super::settings_select_option::SettingsSelectOption;
use super::settings_state::{GitHubStarState, SettingsState};
use super::{AleraApp, SettingsGroupAnchors};
use crate::activity::SettingsPane;
use crate::{
    design_system,
    icons::{agent_icon, icon, loading_indicator, AleraIcon},
    terminal_theme_catalog::{terminal_theme_palette, TERMINAL_THEME_NAMES},
    theme,
};

type SettingsSelect = Entity<SelectState<SearchableVec<SettingsSelectOption>>>;
type SettingsInputs = BTreeMap<String, Entity<InputState>>;

// Computer Use's macOS wheel event is larger than Flutter's ListView delta.
// Keep the correction in one named token so every Settings pane uses the same
// logical scroll distance while the native thumb still tracks the real range.
const SETTINGS_SCROLL_DELTA_FACTOR: f32 = 0.42;

impl AleraApp {
    pub(super) fn render_settings_pane(&self, cx: &mut Context<Self>) -> AnyElement {
        self.settings_scroll_last_offset
            .set(self.settings_scroll_handle.offset().y);
        let content = match self.settings_pane {
            SettingsPane::Application => application_pane(
                &self.workspace_directory_input,
                &self.settings_state,
                &self.settings_inputs,
                &self.settings_group_anchors,
                self.diagnostics_export_busy,
                self.settings_selects
                    .get("diagnostics-log-level")
                    .expect("diagnostics select should exist"),
                cx,
            ),
            SettingsPane::Agents => agents_pane(
                &self.settings_state,
                &self.settings_selects,
                &self.skill_runners,
                &self.settings_group_anchors,
                cx,
            ),
            SettingsPane::Quotas => quotas_pane(
                &self.settings_state,
                &self.settings_inputs,
                &self.status_data.quota_environment,
                self.status_data.quota_loading,
                &self.settings_group_anchors,
                cx,
            ),
            SettingsPane::AiText => ai_text_pane(
                &self.settings_state,
                &self.settings_inputs,
                &self.settings_selects,
                &self.ai_model_discovery_busy,
                &self.ai_model_discovery_errors,
                &self.settings_group_anchors,
                cx,
            ),
            SettingsPane::Editor => editor_pane(
                &self.editor_theme_search_input,
                &self.settings_inputs,
                &self.settings_state,
                cx,
            ),
            SettingsPane::Terminal => terminal_pane(
                &self.settings_state,
                &self.settings_inputs,
                self.settings_selects
                    .get("terminal-font")
                    .expect("terminal font select should exist"),
                &self.terminal_theme_search_input,
                &self.settings_group_anchors,
                cx,
            ),
            SettingsPane::Keyboard => self.render_keyboard_settings_pane(cx),
            SettingsPane::Projects => self.render_project_config_settings_pane(cx),
            SettingsPane::MobileDevices => self.render_mobile_devices_settings_pane(cx),
            SettingsPane::AgentProfiles => self.render_agent_profiles_settings_pane(cx),
        };
        let pane = div()
            .id("settings-content")
            .flex()
            .flex_col()
            .min_w_0()
            .px_6()
            // Flutter's non-resource SettingsContent uses a 24 px ListView
            // inset around every pane. Keep that inset outside the pane
            // groups so group anchors and the scrollbar share the same
            // viewport geometry.
            .py_6()
            .child(content)
            .when(self.settings_state.loading, |pane| {
                pane.child(
                    div()
                        .ml_auto()
                        .px_3()
                        .py_2()
                        .rounded_md()
                        .bg(theme::surface_raised())
                        .text_xs()
                        .text_color(theme::text_muted())
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap_2()
                                .child(loading_indicator(13.0, theme::text_muted()))
                                .child("Refreshing Live Settings"),
                        ),
                )
            })
            .when_some(self.settings_state.error.clone(), |pane, error| {
                pane.child(
                    div()
                        .ml_auto()
                        .mt_2()
                        .px_3()
                        .py_2()
                        .rounded_md()
                        .bg(theme::surface_raised())
                        .text_size(px(12.0))
                        .text_color(theme::danger())
                        .child(error),
                )
            })
            .when_some(self.settings_state.toast.clone(), |pane, message| {
                pane.child(
                    div()
                        .ml_auto()
                        .mt_2()
                        .px_3()
                        .py_2()
                        .rounded_md()
                        .bg(theme::surface_raised())
                        .text_size(px(12.0))
                        .text_color(theme::success())
                        .child(message),
                )
            });
        if self.settings_pane == SettingsPane::AgentProfiles {
            pane.flex_1().min_h_0().overflow_hidden().into_any_element()
        } else {
            let scroll_handle = self.settings_scroll_handle.clone();
            div()
                .id("settings-scroll-container")
                .relative()
                .flex_1()
                .min_w_0()
                .min_h_0()
                .flex()
                .flex_col()
                .child(
                    div()
                        .id("settings-scroll-area")
                        .flex_1()
                        .min_w_0()
                        .min_h_0()
                        .track_scroll(&scroll_handle)
                        .flex_col()
                        // The offset is owned by the child wheel handler
                        // below. Keeping this node clipped but non-scrollable
                        // prevents GPUI's automatic listener from adding the
                        // raw wheel delta a second time; ScrollHandle still
                        // computes its real max range for the thumb.
                        .overflow_hidden()
                        // Keep the scroll content intrinsic. Forcing the pane
                        // to flex to the viewport hides the final rows from
                        // the scroll range when a settings section is taller
                        // than the window.
                        .child(
                            pane.flex_shrink_0().on_scroll_wheel(
                                cx.listener(|this, event: &ScrollWheelEvent, window, cx| {
                                    let delta = event.delta.pixel_delta(window.line_height()).y;
                                    if delta.is_zero() {
                                        return;
                                    }
                                    let current = this.settings_scroll_handle.offset();
                                    let max_y = this.settings_scroll_handle.max_offset().height;
                                    // The macOS Computer Use backend reports a
                                    // larger synthetic page delta than Flutter's
                                    // ListView. Use the persisted pre-event offset
                                    // so the adjustment remains stable and stop
                                    // propagation before `overflow_y_scroll` can
                                    // apply the raw delta a second time.
                                    let previous = this.settings_scroll_last_offset.get();
                                    let next_y = (previous
                                        + delta * SETTINGS_SCROLL_DELTA_FACTOR)
                                        .clamp(-max_y, px(0.0));
                                    this.settings_scroll_handle
                                        .set_offset(gpui::point(current.x, next_y));
                                    this.settings_scroll_last_offset.set(next_y);
                                    cx.stop_propagation();
                                    cx.notify();
                                }),
                            ),
                        ),
                )
                .child(Scrollbar::vertical(&scroll_handle).id("settings-scrollbar"))
                .into_any_element()
        }
    }
}

include!("settings_panes/application_agents.rs");
include!("settings_panes/quotas_ai.rs");
include!("settings_panes/editor.rs");
include!("settings_panes/terminal.rs");
include!("settings_panes/resources.rs");
include!("settings_panes/exact_components.rs");
include!("settings_panes/input_components.rs");
include!("settings_panes/basic_components.rs");
