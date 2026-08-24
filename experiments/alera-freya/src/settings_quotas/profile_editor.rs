use alera_desktop_core::RuntimeBridge;
use freya::prelude::*;

use super::components::settings_input;
use super::model::{ClaudeProfile, QuotaSettings};
use super::{QuotaSignals, save};

pub(super) fn profile_editor(
    settings: State<QuotaSettings>,
    bridge: RuntimeBridge,
    signals: QuotaSignals,
    editor_index: State<Option<usize>>,
    editor_alias: State<String>,
    editor_profile: State<String>,
) -> Element {
    let mut index_for_cancel = editor_index;
    let mut index_for_save = editor_index;
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(6.)
        .padding(Gaps::new_all(8.))
        .child(settings_input(editor_alias, 390.))
        .child(settings_input(editor_profile, 390.))
        .child(
            rect()
                .horizontal()
                .main_align(Alignment::End)
                .spacing(6.)
                .child(
                    Button::new()
                        .compact()
                        .flat()
                        .on_press(move |_| index_for_cancel.set(None))
                        .child("Cancel"),
                )
                .child(
                    Button::new()
                        .compact()
                        .on_press(move |_| {
                            let alias = editor_alias.read().trim().to_string();
                            let profile = editor_profile.read().trim().to_string();
                            let Some(index) = *index_for_save.read() else {
                                return;
                            };
                            let mut next = settings.read().clone();
                            let duplicate = next.claude_profiles.iter().enumerate().any(
                                |(candidate_index, candidate)| {
                                    candidate_index != index
                                        && (candidate.alias == alias
                                            || candidate.profile == profile)
                                },
                            );
                            if alias.is_empty() || profile.is_empty() || duplicate {
                                let mut message = signals.message;
                                message.set(Some(
                                    "Alias and profile are required and must be unique."
                                        .to_string(),
                                ));
                                return;
                            }
                            let value = ClaudeProfile { alias, profile };
                            if index == usize::MAX {
                                next.claude_profiles.push(value);
                            } else if let Some(slot) = next.claude_profiles.get_mut(index) {
                                *slot = value;
                            }
                            next.normalize_profiles();
                            save(next, settings, bridge.clone(), signals);
                            index_for_save.set(None);
                        })
                        .child("Save Profile"),
                ),
        )
        .into_element()
}
