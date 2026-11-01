//! Claude's `AskUserQuestion` input as Alera questions, read leniently as
//! T3 Code does: a question without text or an option without a label is
//! skipped, a missing description reads as blank, and a missing header
//! reads as "Question N". Option previews ride
//! beside the questions in the payload's [USER_INPUT_OPTION_PREVIEWS]
//! side channel, `{questionId: [preview | null, ...]}`.

use alera_provider_protocol::{UserInputOption, UserInputQuestion};
use serde_json::{json, Map, Value};

fn trimmed(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

/// The questions, and their option previews when any option has one.
pub(super) fn claude_questions(input: &Value) -> (Vec<UserInputQuestion>, Option<Value>) {
    let Some(entries) = input.get("questions").and_then(Value::as_array) else {
        return (Vec::new(), None);
    };
    let mut questions = Vec::new();
    let mut previews = Map::new();
    for (index, entry) in entries.iter().enumerate() {
        if !entry.is_object() {
            continue;
        }
        let Some(question) = trimmed(entry.get("question")) else {
            continue;
        };
        let header = trimmed(entry.get("header"));
        // The id order answers are keyed by.
        let id = trimmed(entry.get("id"))
            .or_else(|| header.clone())
            .unwrap_or_else(|| question.clone());
        // Questions need a header; Codex numbers the ones without.
        let header = header.unwrap_or_else(|| format!("Question {}", index + 1));
        let mut options = Vec::new();
        let mut option_previews = Vec::new();
        for option in entry
            .get("options")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let Some(label) = trimmed(option.get("label")) else {
                continue;
            };
            options.push(UserInputOption {
                label,
                description: trimmed(option.get("description")).unwrap_or_default(),
                value: None,
            });
            let preview = option
                .get("preview")
                .and_then(Value::as_str)
                .filter(|preview| !preview.trim().is_empty());
            option_previews.push(preview.map_or(Value::Null, |preview| json!(preview)));
        }
        if option_previews.iter().any(|preview| !preview.is_null()) {
            previews.insert(id.clone(), Value::Array(option_previews));
        }
        questions.push(UserInputQuestion {
            id,
            header,
            question,
            options,
            allow_custom_answer: None,
            initial_answer: None,
            multi_select: entry.get("multiSelect").and_then(Value::as_bool) == Some(true),
        });
    }
    let previews = (!previews.is_empty()).then_some(Value::Object(previews));
    (questions, previews)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn previews_survive_verbatim_beside_their_options() {
        let preview = "\n  **Proposed change**\n\n```ts\n\tconst enabled = true;\n```\n  ";
        let (questions, previews) = claude_questions(&json!({"questions": [{
            "header": "Approach", "question": "Which approach?",
            "options": [
                {"label": "Small", "description": "Patch it", "preview": preview},
                {"label": "Large", "description": "Rewrite it"},
            ],
        }]}));
        assert_eq!(questions[0].id, "Approach");
        assert_eq!(previews, Some(json!({"Approach": [preview, null]})));
    }

    #[test]
    fn blank_parts_are_read_leniently() {
        let (questions, previews) = claude_questions(&json!({"questions": [
            "not an object",
            {"question": "   ", "options": []},
            {"question": " Pick one ", "multiSelect": "yes", "options": [
                {"label": "A"},
                {"label": "B", "description": null},
                {"label": "C", "description": "   "},
                {"label": "  ", "description": "dropped"},
                {"label": "D", "preview": "   "},
            ]},
            {"question": "Many?", "multiSelect": true, "options": []},
        ]}));
        assert_eq!(questions.len(), 2);
        let first = &questions[0];
        assert_eq!(first.header, "Question 3");
        assert_eq!(first.id, "Pick one");
        assert_eq!(first.question, "Pick one");
        assert!(!first.multi_select);
        assert_eq!(first.options.len(), 4);
        assert!(first
            .options
            .iter()
            .all(|option| option.description.is_empty()));
        assert!(questions[1].multi_select);
        assert_eq!(previews, None);
    }
}
