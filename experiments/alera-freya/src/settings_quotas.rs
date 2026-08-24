use std::collections::BTreeMap;

use alera_desktop_core::RuntimeBridge;
use freya::{icons, prelude::*};

use crate::{MUTED, TEXT, settings_group_described, settings_row_shell};

pub(super) mod actions;
mod components;
mod credentials;
pub(super) mod model;
mod profile_editor;

use actions::{load_snapshot, persist_settings};
use components::{
    icon_action, loading_row, pin_action, provider_label, provider_mark, toggle_control,
};
use credentials::credential_rows;
use model::{PROVIDERS, QuotaSettings};
use profile_editor::profile_editor;

#[derive(Clone, Copy)]
pub(super) struct QuotaSignals {
    busy: State<bool>,
    message: State<Option<String>>,
    revision: State<u64>,
}

pub fn content(active: bool, bridge: RuntimeBridge) -> Element {
    let load_result = use_state(|| None::<Result<(), String>>);
    let settings = use_state(QuotaSettings::default);
    let presence = use_state(BTreeMap::<String, bool>::new);
    let revision = use_state(|| 0_u64);
    let busy = use_state(|| false);
    let message = use_state(|| None::<String>);
    let editor_index = use_state(|| None::<usize>);
    let editor_alias = use_state(String::new);
    let editor_profile = use_state(String::new);
    let kimi_key = use_state(|| "KIMI_API_KEY".to_string());
    let zai_key = use_state(|| "ZAI_API_KEY".to_string());
    let zai_base = use_state(|| "ZAI_BASE_URL".to_string());
    let minimax_key = use_state(|| "MINIMAX_API_KEY".to_string());
    let minimax_host = use_state(|| "MINIMAX_API_HOST".to_string());
    let signals = QuotaSignals {
        busy,
        message,
        revision,
    };

    let deps = (active, *revision.read());
    let bridge_for_load = bridge.clone();
    let mut result_for_load = load_result;
    let mut settings_for_load = settings;
    let mut env_inputs = [kimi_key, zai_key, zai_base, minimax_key, minimax_host];
    use_side_effect_with_deps(&deps, move |(active, _)| {
        if !*active {
            return;
        }
        let bridge = bridge_for_load.clone();
        spawn(async move {
            match load_snapshot(bridge).await {
                Ok(value) => {
                    env_inputs[0].set(value.environment.kimi_api_key.clone());
                    env_inputs[1].set(value.environment.zai_api_key.clone());
                    env_inputs[2].set(value.environment.zai_base_url.clone());
                    env_inputs[3].set(value.environment.minimax_api_key.clone());
                    env_inputs[4].set(value.environment.minimax_api_host.clone());
                    settings_for_load.set(value);
                    result_for_load.set(Some(Ok(())));
                }
                Err(error) => result_for_load.set(Some(Err(error))),
            }
        });
    });

    let body = match load_result.read().as_ref() {
        None => loading_row("Loading Quota Settings"),
        Some(Err(error)) => loading_row(error),
        Some(Ok(())) => render_settings(
            settings,
            presence,
            bridge,
            signals,
            editor_index,
            editor_alias,
            editor_profile,
            [kimi_key, zai_key, zai_base, minimax_key, minimax_host],
        ),
    };

    rect()
        .width(Size::fill())
        .vertical()
        .spacing(10.)
        .child(body)
        .maybe_child(
            message
                .read()
                .clone()
                .map(|value| label().font_size(10.).color(MUTED).max_lines(4).text(value)),
        )
        .into_element()
}

#[allow(clippy::too_many_arguments)]
fn render_settings(
    settings: State<QuotaSettings>,
    presence: State<BTreeMap<String, bool>>,
    bridge: RuntimeBridge,
    signals: QuotaSignals,
    editor_index: State<Option<usize>>,
    editor_alias: State<String>,
    editor_profile: State<String>,
    env_inputs: [State<String>; 5],
) -> Element {
    let current = settings.read().clone();
    let mut provider_rows = vec![
        settings_row_shell(
            "Active Quota Host",
            "Run quota commands locally or through the runtime for this workspace.",
        )
        .child(label().font_size(11.).color(TEXT).text("Local"))
        .into_element(),
    ];
    for (provider, label, description) in PROVIDERS {
        if provider == "claude" {
            continue;
        }
        let enabled = current
            .enabled_providers
            .iter()
            .any(|value| value == provider);
        let pinned = current.is_pinned(provider);
        let settings_for_toggle = settings;
        let bridge_for_toggle = bridge.clone();
        let settings_for_pin = settings;
        let bridge_for_pin = bridge.clone();
        provider_rows.push(
            settings_row_shell(label, description)
                .child(
                    rect()
                        .horizontal()
                        .cross_align(Alignment::Center)
                        .spacing(5.)
                        .child(provider_mark(provider))
                        .child(pin_action(pinned, enabled, move |_| {
                            let mut next = settings_for_pin.read().clone();
                            next.toggle_pin(provider);
                            save(next, settings_for_pin, bridge_for_pin.clone(), signals);
                        }))
                        .child(toggle_control(enabled, true, move |event| {
                            event.stop_propagation();
                            let mut next = settings_for_toggle.read().clone();
                            next.toggle_provider(provider);
                            save(
                                next,
                                settings_for_toggle,
                                bridge_for_toggle.clone(),
                                signals,
                            );
                        })),
                )
                .into_element(),
        );
    }
    provider_rows.push(provider_order_row(
        current.clone(),
        settings,
        bridge.clone(),
        signals,
    ));

    let claude_enabled = current
        .enabled_providers
        .iter()
        .any(|value| value == "claude");
    let settings_for_claude = settings;
    let bridge_for_claude = bridge.clone();
    let settings_for_default = settings;
    let bridge_for_default = bridge.clone();
    let settings_for_default_pin = settings;
    let bridge_for_default_pin = bridge.clone();
    let claude_rows = vec![
        settings_row_shell("Claude Code Quotas", PROVIDERS[0].2)
            .child(toggle_control(claude_enabled, true, move |event| {
                event.stop_propagation();
                let mut next = settings_for_claude.read().clone();
                next.toggle_provider("claude");
                save(
                    next,
                    settings_for_claude,
                    bridge_for_claude.clone(),
                    signals,
                );
            }))
            .into_element(),
        settings_row_shell(
            "Claude Default Quotas",
            "Query the default Claude account separately from configured CCS profiles.",
        )
        .child(
            rect()
                .horizontal()
                .spacing(5.)
                .child(pin_action(
                    current.is_pinned("claude:default"),
                    claude_enabled && current.claude_default_enabled,
                    move |_| {
                        let mut next = settings_for_default_pin.read().clone();
                        next.toggle_pin("claude:default");
                        save(
                            next,
                            settings_for_default_pin,
                            bridge_for_default_pin.clone(),
                            signals,
                        );
                    },
                ))
                .child(toggle_control(
                    current.claude_default_enabled,
                    true,
                    move |event| {
                        event.stop_propagation();
                        let mut next = settings_for_default.read().clone();
                        next.claude_default_enabled = !next.claude_default_enabled;
                        save(
                            next,
                            settings_for_default,
                            bridge_for_default.clone(),
                            signals,
                        );
                    },
                )),
        )
        .into_element(),
        profiles_row(
            current.clone(),
            settings,
            bridge.clone(),
            signals,
            editor_index,
            editor_alias,
            editor_profile,
        ),
    ];

    let credential_rows = credential_rows(
        current,
        settings,
        presence,
        bridge.clone(),
        signals,
        env_inputs,
    );
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(12.)
        .child(settings_group_described(
            "Provider Quotas",
            "Choose which usage sources appear for the active workspace host.",
            provider_rows,
        ))
        .child(settings_group_described(
            "Claude",
            "Configure the default Claude account and every CCS profile together.",
            claude_rows,
        ))
        .child(settings_group_described(
            "Credential Environment",
            "Configure environment variable names for the active workspace host.",
            credential_rows,
        ))
        .into_element()
}

fn provider_order_row(
    current: QuotaSettings,
    settings: State<QuotaSettings>,
    bridge: RuntimeBridge,
    signals: QuotaSignals,
) -> Element {
    let mut order = rect().vertical().cross_align(Alignment::End).spacing(3.);
    for (index, provider) in current.enabled_providers.iter().enumerate() {
        let provider = provider.clone();
        let provider_for_earlier = provider.clone();
        let provider_for_later = provider.clone();
        let earlier_state = settings;
        let later_state = settings;
        let earlier_bridge = bridge.clone();
        let later_bridge = bridge.clone();
        order = order.child(
            rect()
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(4.)
                .child(provider_mark(&provider))
                .child(
                    label()
                        .width(Size::px(94.))
                        .font_size(10.)
                        .color(TEXT)
                        .text(provider_label(&provider)),
                )
                .child(icon_action(
                    icons::lucide::chevron_up(),
                    format!("Move {} Earlier", provider_label(&provider)),
                    index > 0,
                    move |_| {
                        let mut next = earlier_state.read().clone();
                        next.move_provider(&provider_for_earlier, -1);
                        save(next, earlier_state, earlier_bridge.clone(), signals);
                    },
                ))
                .child(icon_action(
                    icons::lucide::chevron_down(),
                    format!("Move {} Later", provider_label(&provider)),
                    index + 1 < current.enabled_providers.len(),
                    move |_| {
                        let mut next = later_state.read().clone();
                        next.move_provider(&provider_for_later, 1);
                        save(next, later_state, later_bridge.clone(), signals);
                    },
                )),
        );
    }
    settings_row_shell(
        "Quota Display Order",
        "Set the left-to-right order of enabled providers in the status bar.",
    )
    .child(order)
    .into_element()
}

#[allow(clippy::too_many_arguments)]
fn profiles_row(
    current: QuotaSettings,
    settings: State<QuotaSettings>,
    bridge: RuntimeBridge,
    signals: QuotaSignals,
    mut editor_index: State<Option<usize>>,
    mut editor_alias: State<String>,
    mut editor_profile: State<String>,
) -> Element {
    let mut rows = rect()
        .width(Size::px(420.))
        .vertical()
        .cross_align(Alignment::End)
        .spacing(5.);
    if current.claude_profiles.is_empty() {
        rows = rows.child(
            label()
                .font_size(10.)
                .color(MUTED)
                .text("No CCS Profiles Configured"),
        );
    }
    for (index, profile) in current.claude_profiles.iter().enumerate() {
        let pin_key = format!("claude:{}", profile.profile);
        let pinned = current.is_pinned(&pin_key);
        let pin_state = settings;
        let pin_bridge = bridge.clone();
        let up_state = settings;
        let up_bridge = bridge.clone();
        let down_state = settings;
        let down_bridge = bridge.clone();
        let remove_state = settings;
        let remove_bridge = bridge.clone();
        let alias = profile.alias.clone();
        let profile_name = profile.profile.clone();
        let alias_for_edit = alias.clone();
        let profile_for_edit = profile_name.clone();
        rows = rows.child(
            rect()
                .width(Size::fill())
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(4.)
                .child(provider_mark("claude"))
                .child(
                    rect()
                        .width(Size::flex(1.))
                        .vertical()
                        .child(label().font_size(10.).color(TEXT).text(alias))
                        .child(label().font_size(9.).color(MUTED).text(profile_name)),
                )
                .child(pin_action(pinned, true, move |_| {
                    let mut next = pin_state.read().clone();
                    next.toggle_pin(&pin_key);
                    save(next, pin_state, pin_bridge.clone(), signals);
                }))
                .child(icon_action(
                    icons::lucide::chevron_up(),
                    "Move Profile Earlier",
                    index > 0,
                    move |_| {
                        let mut next = up_state.read().clone();
                        next.claude_profiles.swap(index, index - 1);
                        save(next, up_state, up_bridge.clone(), signals);
                    },
                ))
                .child(icon_action(
                    icons::lucide::chevron_down(),
                    "Move Profile Later",
                    index + 1 < current.claude_profiles.len(),
                    move |_| {
                        let mut next = down_state.read().clone();
                        next.claude_profiles.swap(index, index + 1);
                        save(next, down_state, down_bridge.clone(), signals);
                    },
                ))
                .child(icon_action(
                    icons::lucide::pencil(),
                    "Edit CCS Profile",
                    true,
                    move |_| {
                        editor_alias.set(alias_for_edit.clone());
                        editor_profile.set(profile_for_edit.clone());
                        editor_index.set(Some(index));
                    },
                ))
                .child(icon_action(
                    icons::lucide::trash_2(),
                    "Remove CCS Profile",
                    true,
                    move |_| {
                        let mut next = remove_state.read().clone();
                        next.claude_profiles.remove(index);
                        next.normalize_profiles();
                        save(next, remove_state, remove_bridge.clone(), signals);
                    },
                )),
        );
    }
    let mut editor_index_for_add = editor_index;
    let mut alias_for_add = editor_alias;
    let mut profile_for_add = editor_profile;
    rows = rows.child(
        Button::new()
            .compact()
            .flat()
            .on_press(move |_| {
                alias_for_add.set(String::new());
                profile_for_add.set(String::new());
                editor_index_for_add.set(Some(usize::MAX));
            })
            .child("Add CCS Profile"),
    );
    if editor_index.read().is_some() {
        rows = rows.child(profile_editor(
            settings,
            bridge,
            signals,
            editor_index,
            editor_alias,
            editor_profile,
        ));
    }
    settings_row_shell(
        "Claude CCS Profiles",
        "Add CCS alias and profile pairs. They remain available when default Claude is disabled.",
    )
    .child(rows)
    .into_element()
}

fn save(
    value: QuotaSettings,
    mut state: State<QuotaSettings>,
    bridge: RuntimeBridge,
    signals: QuotaSignals,
) {
    state.set(value.clone());
    persist_settings(bridge, value, signals);
}
