use std::time::Duration;

use alera_desktop_core::RuntimeBridge;
use freya::prelude::*;
use serde_json::{Value, json};

use super::{MUTED, ResourceCloseConfirmation, SURFACE, TEXT};

const DIALOG_BORDER: (u8, u8, u8) = (39, 39, 39);

pub(crate) fn close_confirmation_dialog(
    bridge: RuntimeBridge,
    confirmation: State<Option<ResourceCloseConfirmation>>,
    action_busy: State<bool>,
    action_message: State<Option<String>>,
    resource_snapshot: State<Option<Result<Value, String>>>,
    workbench_revision: State<u64>,
) -> Option<Element> {
    let current = confirmation.read().clone()?;
    let mut confirmation_for_cancel = confirmation;
    let mut confirmation_for_close = confirmation;
    let mut busy = action_busy;
    let busy_now = *action_busy.read();
    let mut message = action_message;
    let mut resources = resource_snapshot;
    let mut revision = workbench_revision;
    let mut confirmation_for_barrier = confirmation;
    let mut confirmation_for_escape = confirmation;
    let tab_id_for_press = current.tab_id.clone();
    Some(
        rect()
            .position(Position::new_absolute())
            .layer(Layer::Overlay)
            .width(Size::percent(100.))
            .height(Size::percent(100.))
            .background(Color::from_af32rgb(0.54, 0, 0, 0))
            .on_global_key_down(move |event: Event<KeyboardEventData>| {
                if matches!(event.key, Key::Named(NamedKey::Escape)) && !busy_now {
                    event.prevent_default();
                    event.stop_propagation();
                    confirmation_for_escape.set(None);
                }
            })
            .on_pointer_down(move |_| {
                if !busy_now {
                    confirmation_for_barrier.set(None);
                }
            })
            .child(
                rect()
                    .position(Position::new_absolute())
                    .width(Size::percent(100.))
                    .height(Size::percent(100.))
                    .center()
                    .child(
                        rect()
                            .width(Size::px(420.))
                            .vertical()
                            .padding(Gaps::new_all(20.))
                            .background(SURFACE)
                            .border(Border::new().width(1.).fill(DIALOG_BORDER))
                            .corner_radius(12.)
                            .shadow(Shadow::new().x(0.).y(8.).blur(24.).color((0, 0, 0, 0.32)))
                            .on_pointer_down(|event: Event<PointerEventData>| {
                                event.stop_propagation()
                            })
                            .child(
                                label()
                                    .font_size(16.)
                                    .font_weight(FontWeight::SEMI_BOLD)
                                    .color(TEXT)
                                    .text("Close Terminal Session"),
                            )
                            .child(
                                label()
                                    .margin(Gaps::new(0., 12., 0., 0.))
                                    .font_size(13.)
                                    .color(MUTED)
                                    .max_lines(4)
                                    .text(format!(
                                        "Force-quits {}. Anything running in that terminal is lost.",
                                        current.label
                                    )),
                            )
                            .child(
                                rect()
                                    .margin(Gaps::new(0., 20., 0., 0.))
                                    .horizontal()
                                    .main_align(Alignment::End)
                                    .spacing(8.)
                                    .child(
                                        rect()
                                            .width(Size::flex(1.))
                                            .a11y_role(AccessibilityRole::Button)
                                            .a11y_alt("Cancel")
                                            .on_pointer_enter(|_| {
                                                Cursor::set(CursorIcon::Pointer)
                                            })
                                            .on_pointer_leave(|_| {
                                                Cursor::set(CursorIcon::default())
                                            })
                                            .on_pointer_down(
                                                move |event: Event<PointerEventData>| {
                                                    event.stop_propagation();
                                                    if !busy_now {
                                                        confirmation_for_cancel.set(None);
                                                    }
                                                },
                                            )
                                            .child(resource_dialog_button(
                                                "Cancel",
                                                false,
                                                false,
                                            )),
                                    )
                                    .child(
                                        rect()
                                            .width(Size::flex(1.))
                                            .a11y_role(AccessibilityRole::Button)
                                            .a11y_alt("Close")
                                            .on_pointer_enter(|_| {
                                                Cursor::set(CursorIcon::Pointer)
                                            })
                                            .on_pointer_leave(|_| {
                                                Cursor::set(CursorIcon::default())
                                            })
                                            .on_pointer_down(
                                                move |event: Event<PointerEventData>| {
                                                    event.stop_propagation();
                                                    if busy_now {
                                                        return;
                                                    }
                                                    busy.set(true);
                                                    message.set(None);
                                                    confirmation_for_close.set(None);
                                                    let bridge = bridge.clone();
                                                    let tab_id = tab_id_for_press.clone();
                                                    spawn(async move {
                                                        let result = bridge
                                                            .request_with_timeout(
                                                                "tab.remove",
                                                                json!({"id": tab_id}),
                                                                Duration::from_secs(30),
                                                            )
                                                            .await;
                                                        match result {
                                                            Ok(_) => {
                                                                let next_revision = revision
                                                                    .read()
                                                                    .saturating_add(1);
                                                                revision.set(next_revision);
                                                                resources.set(Some(
                                                                    fetch_snapshot(&bridge).await,
                                                                ));
                                                            }
                                                            Err(error) => {
                                                                message.set(Some(error))
                                                            }
                                                        }
                                                        busy.set(false);
                                                    });
                                                },
                                            )
                                            .child(resource_dialog_button(
                                                "Close",
                                                true,
                                                busy_now,
                                            )),
                                    ),
                            ),
                    ),
            )
            .into_element(),
    )
}

fn resource_dialog_button(text: &'static str, destructive: bool, loading: bool) -> Element {
    ResourceDialogButton {
        text,
        destructive,
        loading,
    }
    .into_element()
}

#[derive(Clone, Copy, PartialEq)]
struct ResourceDialogButton {
    text: &'static str,
    destructive: bool,
    loading: bool,
}

impl Component for ResourceDialogButton {
    fn render(&self) -> impl IntoElement {
        let mut hovered = use_state(|| false);
        rect()
            .width(Size::fill())
            .height(Size::px(34.))
            .center()
            .corner_radius(10.)
            .background(match (self.destructive, hovered()) {
                (true, true) => Color::from_rgb(255, 138, 138),
                (true, false) => Color::from_rgb(248, 113, 113),
                (false, true) => Color::from_af32rgb(0.10, 224, 224, 224),
                (false, false) => Color::TRANSPARENT,
            })
            .on_pointer_enter(move |_| hovered.set(true))
            .on_pointer_leave(move |_| hovered.set(false))
            .child(if self.loading {
                CircularLoader::new().size(13.).into_element()
            } else {
                label()
                    .font_size(12.)
                    .font_weight(FontWeight::SEMI_BOLD)
                    .color(if self.destructive { (44, 13, 13) } else { TEXT })
                    .max_lines(1)
                    .text(self.text)
                    .into_element()
            })
    }

    fn render_key(&self) -> DiffKey {
        DiffKey::from(&self.text)
    }
}

pub(super) fn terminate_sessions(
    bridge: RuntimeBridge,
    session_ids: Vec<String>,
    mut busy: State<bool>,
    mut message: State<Option<String>>,
    mut resource_snapshot: State<Option<Result<Value, String>>>,
) {
    if *busy.read() || session_ids.is_empty() {
        return;
    }
    busy.set(true);
    message.set(None);
    spawn(async move {
        let mut error = None;
        for session_id in session_ids {
            if let Err(next_error) = bridge
                .request_with_timeout(
                    "terminate",
                    json!({"sessionId": session_id}),
                    Duration::from_secs(30),
                )
                .await
            {
                error = Some(next_error);
            }
        }
        if let Some(error) = error {
            message.set(Some(error));
        }
        resource_snapshot.set(Some(fetch_snapshot(&bridge).await));
        busy.set(false);
    });
}

pub(crate) async fn fetch_snapshot(bridge: &RuntimeBridge) -> Result<Value, String> {
    bridge
        .request_with_timeout(
            "resources.snapshot",
            json!({"appPid": std::process::id()}),
            Duration::from_secs(5),
        )
        .await
}
