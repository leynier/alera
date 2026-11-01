//! The models and thinking levels an Antigravity ACP session offers.

use alera_provider_acp::{config_reasoning_efforts, default_config_reasoning_effort};
use serde_json::Value;
use std::collections::BTreeMap;

/// One model a session offers, with the thinking levels it takes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AntigravityModel {
    pub id: String,
    pub label: String,
    /// The session's own model when nothing is selected.
    pub provider_default: bool,
    pub thinking: AntigravityThinking,
}

/// The thinking levels of a model: the values of the session's
/// `thought_level` option while it is selected (runtime 1.4).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AntigravityThinking {
    pub levels: Vec<String>,
    pub default: Option<String>,
}

/// The thinking levels the session's config options advertise.
pub fn thinking_from_options(options: &[Value]) -> AntigravityThinking {
    AntigravityThinking {
        levels: config_reasoning_efforts(options),
        default: default_config_reasoning_effort(options),
    }
}

/// The session's models: unique ids, the current model as the default, and
/// a name several models share labelled with each id.
pub fn models_from_session(
    choices: &[(String, String)],
    current: Option<&str>,
    thinking: &BTreeMap<String, AntigravityThinking>,
) -> Vec<AntigravityModel> {
    let mut unique: Vec<&(String, String)> = Vec::new();
    for choice in choices {
        if !choice.0.trim().is_empty() && !unique.iter().any(|kept| kept.0 == choice.0) {
            unique.push(choice);
        }
    }
    unique
        .iter()
        .map(|(id, name)| {
            let shared = unique.iter().filter(|(_, other)| other == name).count() > 1;
            AntigravityModel {
                id: id.clone(),
                label: if shared {
                    format!("{name} ({id})")
                } else {
                    name.clone()
                },
                provider_default: current == Some(id.as_str()),
                thinking: thinking.get(id).cloned().unwrap_or_default(),
            }
        })
        .collect()
}
