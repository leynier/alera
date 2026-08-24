use std::collections::BTreeMap;

use alera_desktop_core::RuntimeBridge;
use freya::{icons, prelude::*};

use crate::{MUTED, SUCCESS, settings_row_shell};

use super::actions::check_environment;
use super::components::settings_input;
use super::model::QuotaSettings;
use super::{QuotaSignals, save};

#[derive(Clone, Copy)]
enum EnvironmentField {
    KimiKey,
    ZaiKey,
    ZaiBase,
    MinimaxKey,
    MinimaxHost,
}

pub(super) fn credential_rows(
    current: QuotaSettings,
    settings: State<QuotaSettings>,
    presence: State<BTreeMap<String, bool>>,
    bridge: RuntimeBridge,
    signals: QuotaSignals,
    inputs: [State<String>; 5],
) -> Vec<Element> {
    let specs = [
        (
            "Kimi API Key Variable",
            "Environment variable read on the active host. Secret values are never stored.",
            EnvironmentField::KimiKey,
        ),
        (
            "Z.ai API Key Variable",
            "Environment variable read on the active host. Secret values are never stored.",
            EnvironmentField::ZaiKey,
        ),
        (
            "Z.ai Base URL Variable",
            "Optional variable for the Coding Plan API base URL.",
            EnvironmentField::ZaiBase,
        ),
        (
            "MiniMax API Key Variable",
            "Environment variable read on the active host. Secret values are never stored.",
            EnvironmentField::MinimaxKey,
        ),
        (
            "MiniMax API Host Variable",
            "Optional variable selecting the global or China endpoint.",
            EnvironmentField::MinimaxHost,
        ),
    ];
    let mut rows = Vec::new();
    for (index, (title, description, field)) in specs.into_iter().enumerate() {
        let bridge_for_input = bridge.clone();
        let value_state = inputs[index];
        rows.push(
            settings_row_shell(title, description)
                .child(
                    settings_input(value_state, 220.).on_submit(move |value: String| {
                        let mut next = settings.read().clone();
                        match field {
                            EnvironmentField::KimiKey => next.environment.kimi_api_key = value,
                            EnvironmentField::ZaiKey => next.environment.zai_api_key = value,
                            EnvironmentField::ZaiBase => next.environment.zai_base_url = value,
                            EnvironmentField::MinimaxKey => {
                                next.environment.minimax_api_key = value
                            }
                            EnvironmentField::MinimaxHost => {
                                next.environment.minimax_api_host = value
                            }
                        }
                        save(next, settings, bridge_for_input.clone(), signals);
                    }),
                )
                .into_element(),
        );
    }
    let names = [
        current.environment.kimi_api_key,
        current.environment.zai_api_key,
        current.environment.zai_base_url,
        current.environment.minimax_api_key,
        current.environment.minimax_api_host,
    ];
    let mut indicators = rect().vertical().cross_align(Alignment::End).spacing(3.);
    for name in names {
        let available = presence.read().get(&name).copied();
        indicators = indicators.child(
            rect()
                .horizontal()
                .spacing(5.)
                .child(
                    SvgViewer::new(if available == Some(true) {
                        icons::lucide::circle_check()
                    } else {
                        icons::lucide::circle()
                    })
                    .width(Size::px(12.))
                    .height(Size::px(12.))
                    .color(if available == Some(true) {
                        SUCCESS
                    } else {
                        MUTED
                    }),
                )
                .child(label().font_size(9.).color(MUTED).text(name)),
        );
    }
    let bridge_for_refresh = bridge;
    rows.push(
        settings_row_shell(
            "Credential Availability",
            "Check whether each configured variable exists without reading its secret value.",
        )
        .child(
            rect()
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(8.)
                .child(indicators)
                .child(
                    Button::new()
                        .compact()
                        .outline()
                        .enabled(!*signals.busy.read())
                        .on_press(move |_| {
                            check_environment(bridge_for_refresh.clone(), presence, signals)
                        })
                        .child("Refresh"),
                ),
        )
        .into_element(),
    );
    rows
}
