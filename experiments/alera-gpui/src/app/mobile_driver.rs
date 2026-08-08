use std::collections::BTreeMap;

use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, FontWeight,
    InteractiveElement as _, IntoElement as _, MouseButton, MouseDownEvent, ParentElement as _,
    SharedString, Styled as _,
};
use serde_json::{json, Value};

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct MobileTerminalDriver {
    pub(super) device_id: Option<String>,
    pub(super) device_name: Option<String>,
}

impl MobileTerminalDriver {
    fn from_value(value: &Value) -> Option<Self> {
        (value.get("kind").and_then(Value::as_str) == Some("mobile")).then(|| Self {
            device_id: value
                .get("deviceId")
                .and_then(Value::as_str)
                .map(str::to_owned),
            device_name: value
                .get("deviceName")
                .and_then(Value::as_str)
                .map(str::to_owned),
        })
    }
}

fn parse_terminal_driver_list(value: &Value) -> BTreeMap<String, MobileTerminalDriver> {
    value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            let session_id = entry.get("sessionId")?.as_str()?.to_owned();
            let driver = MobileTerminalDriver::from_value(entry.get("driver")?)?;
            Some((session_id, driver))
        })
        .collect()
}

impl AleraApp {
    pub(super) fn refresh_terminal_drivers(&mut self, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("terminal.driver.list", json!({}))
                .await
                .map(|value| parse_terminal_driver_list(&value));
            let _ = this.update(cx, |this, cx| {
                if let Ok(drivers) = result {
                    // A change event racing this bootstrap wins. The list only
                    // fills sessions whose live state is not known yet.
                    for (session_id, driver) in drivers {
                        this.terminal_drivers.entry(session_id).or_insert(driver);
                    }
                    cx.notify();
                }
            });
        })
        .detach();
    }

    pub(super) fn handle_terminal_driver_changed(
        &mut self,
        payload: &Value,
        cx: &mut Context<Self>,
    ) -> bool {
        let Some(session_id) = payload.get("sessionId").and_then(Value::as_str) else {
            return false;
        };
        if let Some(driver) = payload
            .get("driver")
            .and_then(MobileTerminalDriver::from_value)
        {
            self.terminal_drivers.insert(session_id.to_owned(), driver);
        } else {
            self.terminal_drivers.remove(session_id);
            self.terminal_driver_collapsed.remove(session_id);
            self.terminal_driver_reclaiming.remove(session_id);
        }
        cx.notify();
        true
    }

    pub(super) fn is_terminal_mobile_driven(&self, session_id: &str) -> bool {
        self.terminal_drivers.contains_key(session_id)
    }

    pub(super) fn reclaim_mobile_terminal(&mut self, session_id: String, cx: &mut Context<Self>) {
        if !self.terminal_driver_reclaiming.insert(session_id.clone()) {
            return;
        }
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "terminal.reclaim",
                    json!({ "sessionId": session_id.clone() }),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                this.terminal_driver_reclaiming.remove(&session_id);
                match result {
                    Ok(_) => {
                        this.terminal_drivers.remove(&session_id);
                        this.terminal_driver_collapsed.remove(&session_id);
                    }
                    Err(error) => this.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn reclaim_all_mobile_terminals(&mut self, cx: &mut Context<Self>) {
        let session_ids = self.terminal_drivers.keys().cloned().collect::<Vec<_>>();
        if session_ids.is_empty()
            || session_ids
                .iter()
                .any(|session_id| self.terminal_driver_reclaiming.contains(session_id))
        {
            return;
        }
        self.terminal_driver_reclaiming
            .extend(session_ids.iter().cloned());
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let mut first_error = None;
            let mut reclaimed = Vec::new();
            for session_id in &session_ids {
                match bridge
                    .request("terminal.reclaim", json!({ "sessionId": session_id }))
                    .await
                {
                    Ok(_) => reclaimed.push(session_id.clone()),
                    Err(error) => {
                        first_error.get_or_insert(error);
                    }
                }
            }
            let _ = this.update(cx, |this, cx| {
                for session_id in &session_ids {
                    this.terminal_driver_reclaiming.remove(session_id);
                }
                for session_id in reclaimed {
                    this.terminal_drivers.remove(&session_id);
                    this.terminal_driver_collapsed.remove(&session_id);
                }
                if let Some(error) = first_error {
                    this.error = Some(error.into());
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_mobile_driver_overlay(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let driver = self.terminal_drivers.get(session_id)?;
        let collapsed = self.terminal_driver_collapsed.contains(session_id);
        let busy = self.terminal_driver_reclaiming.contains(session_id);
        let device_name = driver.device_name.as_deref().unwrap_or("A Phone");
        let driven_count = self.terminal_drivers.len();
        let overlay = if collapsed {
            self.render_mobile_driver_chip(session_id, busy, cx)
        } else {
            self.render_mobile_driver_banner(session_id, device_name, driven_count, busy, cx)
        };
        Some(
            div()
                .absolute()
                .top_0()
                .right_0()
                .bottom_0()
                .left_0()
                .flex()
                .items_start()
                .justify_center()
                .pt(gpui::px(12.0))
                .font_family("Inter")
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(|_, _: &MouseDownEvent, _, cx| cx.stop_propagation()),
                )
                .child(overlay)
                .into_any_element(),
        )
    }

    fn render_mobile_driver_banner(
        &self,
        session_id: &str,
        device_name: &str,
        driven_count: usize,
        busy: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let collapse_session_id = session_id.to_owned();
        let reclaim_session_id = session_id.to_owned();
        let title = format!("{device_name} Is Driving This Terminal");
        div()
            .p(gpui::px(12.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(icon(AleraIcon::MobileDevice, 16.0, theme::info()))
                    .child(
                        div()
                            .text_size(gpui::px(13.0))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(title),
                    )
                    .child(
                        mobile_driver_icon_button(
                            SharedString::from(format!(
                                "collapse-mobile-driver-{collapse_session_id}"
                            )),
                            AleraIcon::CloseFullscreen,
                            16.0,
                        )
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                this.terminal_driver_collapsed
                                    .insert(collapse_session_id.clone());
                                cx.stop_propagation();
                                cx.notify();
                            }),
                        ),
                    ),
            )
            .child(
                div()
                    .mt_1()
                    .text_size(gpui::px(13.0))
                    .text_color(theme::text_muted())
                    .child("Desktop Keyboard Is Paused"),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .mt_3()
                    .child(
                        design_system::button_with_loading(
                            SharedString::from(format!(
                                "take-back-mobile-terminal-{reclaim_session_id}"
                            )),
                            "Take Back This Terminal",
                            ButtonKind::Filled,
                            busy,
                            busy,
                        )
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                this.reclaim_mobile_terminal(reclaim_session_id.clone(), cx);
                                cx.stop_propagation();
                            }),
                        ),
                    )
                    .when(driven_count > 1, |actions| {
                        actions.child(
                            design_system::button_with_loading(
                                "take-back-all-mobile-terminals",
                                "Take Back All Terminals",
                                ButtonKind::Outlined,
                                busy,
                                busy,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                    this.reclaim_all_mobile_terminals(cx);
                                    cx.stop_propagation();
                                }),
                            ),
                        )
                    }),
            )
            .into_any_element()
    }

    fn render_mobile_driver_chip(
        &self,
        session_id: &str,
        busy: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let reclaim_session_id = session_id.to_owned();
        let expand_session_id = session_id.to_owned();
        div()
            .flex()
            .items_center()
            .px(gpui::px(12.0))
            .py(gpui::px(4.0))
            .rounded(gpui::px(999.0))
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .child(icon(AleraIcon::MobileDevice, 12.0, theme::info()))
            .child(
                div()
                    .ml(gpui::px(6.0))
                    .text_size(gpui::px(13.0))
                    .text_color(theme::text_muted())
                    .child("Phone Driving"),
            )
            .child(
                design_system::button_with_loading(
                    SharedString::from(format!(
                        "take-back-mobile-terminal-chip-{reclaim_session_id}"
                    )),
                    "Take Back",
                    ButtonKind::Text,
                    busy,
                    busy,
                )
                .h(gpui::px(28.0))
                .px(gpui::px(8.0))
                .ml_2()
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                        this.reclaim_mobile_terminal(reclaim_session_id.clone(), cx);
                        cx.stop_propagation();
                    }),
                ),
            )
            .child(
                mobile_driver_icon_button(
                    SharedString::from(format!("expand-mobile-driver-{expand_session_id}")),
                    AleraIcon::OpenInFull,
                    12.0,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                        this.terminal_driver_collapsed.remove(&expand_session_id);
                        cx.stop_propagation();
                        cx.notify();
                    }),
                ),
            )
            .into_any_element()
    }
}

fn mobile_driver_icon_button(
    id: SharedString,
    icon_kind: AleraIcon,
    icon_size: f32,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .w(gpui::px(28.0))
        .h(gpui::px(28.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_selected()))
        .child(icon(icon_kind, icon_size, theme::text_muted()))
}

#[cfg(test)]
mod tests {
    use super::{parse_terminal_driver_list, MobileTerminalDriver};
    use serde_json::json;

    #[test]
    fn parses_only_mobile_drivers() {
        let drivers = parse_terminal_driver_list(&json!([
            {
                "sessionId": "mobile",
                "driver": {
                    "kind": "mobile",
                    "deviceId": "phone-1",
                    "deviceName": "Leynier Phone"
                }
            },
            {"sessionId": "desktop", "driver": {"kind": "desktop"}},
            {"sessionId": "idle", "driver": {"kind": "idle"}}
        ]));

        assert_eq!(
            drivers.get("mobile"),
            Some(&MobileTerminalDriver {
                device_id: Some("phone-1".to_owned()),
                device_name: Some("Leynier Phone".to_owned()),
            })
        );
        assert_eq!(drivers.len(), 1);
    }

    #[test]
    fn ignores_malformed_entries() {
        let drivers = parse_terminal_driver_list(&json!([
            null,
            {"driver": {"kind": "mobile"}},
            {"sessionId": 7, "driver": {"kind": "mobile"}},
            {"sessionId": "missing-driver"}
        ]));

        assert!(drivers.is_empty());
    }
}
