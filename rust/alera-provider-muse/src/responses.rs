use super::events::PendingRequest;
use super::MuseProvider;
use alera_provider_protocol::{ApprovalDecision, ProviderError, UserInputAnswers};
use serde_json::{Map, Value};

impl MuseProvider {
    pub(crate) async fn respond_approval(
        &mut self,
        request: PendingRequest,
        decision: ApprovalDecision,
    ) -> Result<(), ProviderError> {
        let Some(choices) = request
            .params
            .get("availableChoices")
            .and_then(Value::as_array)
        else {
            return Err(ProviderError::Unsupported(
                "Muse approval has no native choices".into(),
            ));
        };
        let wanted = match decision {
            ApprovalDecision::Accept => &["approved"][..],
            ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways => {
                &["approvedForSession", "approvedPolicyAmendment"][..]
            }
            ApprovalDecision::Decline | ApprovalDecision::Cancel => &["abort", "denied"][..],
        };
        let choice_id = choices.iter().find_map(|choice| {
            let native = choice.get("decision").and_then(Value::as_str)?;
            if !wanted.contains(&native) {
                return None;
            }
            choice.get("choiceId")?.as_str().map(str::to_owned)
        });
        let choice_id = choice_id.ok_or_else(|| {
            ProviderError::Unsupported("Muse approval did not offer a compatible choice".into())
        })?;
        let mut params = Map::new();
        params.insert(
            "sessionId".into(),
            Value::String(self.session_ref()?.native_thread_id.clone()),
        );
        params.insert(
            "approvalId".into(),
            Value::String(request.logical_id.to_string()),
        );
        params.insert("choiceId".into(), Value::String(choice_id));
        let requirement = request
            .params
            .get("currentRequirementId")
            .cloned()
            .ok_or_else(|| {
                ProviderError::Validation("Muse approval is missing currentRequirementId".into())
            })?;
        params.insert("requirementId".into(), requirement);
        self.client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
            .command("approval/decide", params, None)
            .await
            .map_err(Self::sdk_error)?;
        self.pending.remove(&request.logical_id);
        Ok(())
    }

    pub(crate) async fn respond_user_input(
        &mut self,
        request: PendingRequest,
        answers: UserInputAnswers,
    ) -> Result<(), ProviderError> {
        let questions = request
            .params
            .get("questions")
            .and_then(Value::as_array)
            .ok_or_else(|| {
                ProviderError::Validation("Muse user input has no native questions".into())
            })?;
        let question_ids = questions
            .iter()
            .filter_map(|question| question.get("id").and_then(Value::as_str))
            .collect::<std::collections::BTreeSet<_>>();
        if answers.len() != question_ids.len()
            || answers
                .keys()
                .any(|question_id| !question_ids.contains(question_id.as_str()))
        {
            return Err(ProviderError::Validation(
                "Muse user input answers must cover each native question exactly once".into(),
            ));
        }
        let mut native_answers = Vec::new();
        for (question_id, answer) in answers {
            let mut item = Map::new();
            item.insert("questionId".into(), Value::String(question_id.clone()));
            match answer {
                Value::String(text) => {
                    let question = request
                        .params
                        .get("questions")
                        .and_then(Value::as_array)
                        .into_iter()
                        .flatten()
                        .find(|question| {
                            question.get("id").and_then(Value::as_str) == Some(question_id.as_str())
                        })
                        .ok_or_else(|| {
                            ProviderError::Validation(format!(
                                "Muse answer references unknown question {question_id}"
                            ))
                        })?;
                    let is_option = question
                        .get("options")
                        .and_then(Value::as_array)
                        .is_some_and(|options| {
                            options.iter().any(|option| {
                                option.get("label").and_then(Value::as_str) == Some(text.as_str())
                            })
                        });
                    if is_option {
                        let mode = question
                            .get("selection")
                            .and_then(|selection| selection.get("mode"))
                            .and_then(Value::as_str)
                            .unwrap_or("single");
                        if mode == "multiple" {
                            let min = question
                                .get("selection")
                                .and_then(|selection| selection.get("minSelections"))
                                .and_then(Value::as_u64)
                                .unwrap_or(0);
                            let max = question
                                .get("selection")
                                .and_then(|selection| selection.get("maxSelections"))
                                .and_then(Value::as_u64);
                            if min > 1 || max.is_some_and(|max| max < 1) {
                                return Err(ProviderError::Validation(
                                    "Muse answer violates the native selection bounds".into(),
                                ));
                            }
                            item.insert(
                                "selectedLabels".into(),
                                Value::Array(vec![Value::String(text)]),
                            );
                        } else {
                            item.insert("selectedLabel".into(), Value::String(text));
                        }
                    } else {
                        if text.chars().count() > 500 {
                            return Err(ProviderError::Validation(
                                "Muse custom user input exceeds 500 characters".into(),
                            ));
                        }
                        item.insert("freeText".into(), Value::String(text));
                    }
                }
                Value::Array(values) => {
                    let question = request
                        .params
                        .get("questions")
                        .and_then(Value::as_array)
                        .into_iter()
                        .flatten()
                        .find(|question| {
                            question.get("id").and_then(Value::as_str) == Some(question_id.as_str())
                        })
                        .ok_or_else(|| {
                            ProviderError::Validation(format!(
                                "Muse answer references unknown question {question_id}"
                            ))
                        })?;
                    let selection = question.get("selection");
                    if selection
                        .and_then(|value| value.get("mode"))
                        .and_then(Value::as_str)
                        != Some("multiple")
                    {
                        return Err(ProviderError::Validation(
                            "Muse multiple answer requires a multiple-selection question".into(),
                        ));
                    }
                    let labels = values
                        .into_iter()
                        .map(|value| {
                            value.as_str().map(str::to_owned).ok_or_else(|| {
                                ProviderError::Validation(
                                    "user input labels must be strings".into(),
                                )
                            })
                        })
                        .collect::<Result<Vec<_>, _>>()?;
                    let unique_labels = labels.iter().collect::<std::collections::BTreeSet<_>>();
                    if unique_labels.len() != labels.len() {
                        return Err(ProviderError::Validation(
                            "Muse answer cannot select the same option twice".into(),
                        ));
                    }
                    let options = question
                        .get("options")
                        .and_then(Value::as_array)
                        .cloned()
                        .unwrap_or_default();
                    if labels.iter().any(|label| {
                        !options.iter().any(|option| {
                            option.get("label").and_then(Value::as_str) == Some(label.as_str())
                        })
                    }) {
                        return Err(ProviderError::Validation(
                            "Muse answer contains a label absent from the native options".into(),
                        ));
                    }
                    let min = selection
                        .and_then(|value| value.get("minSelections"))
                        .and_then(Value::as_u64)
                        .unwrap_or(0) as usize;
                    let max = selection
                        .and_then(|value| value.get("maxSelections"))
                        .and_then(Value::as_u64)
                        .map(|value| value as usize);
                    if labels.len() < min || max.is_some_and(|max| labels.len() > max) {
                        return Err(ProviderError::Validation(
                            "Muse answer violates the native selection bounds".into(),
                        ));
                    }
                    item.insert(
                        "selectedLabels".into(),
                        serde_json::to_value(labels).unwrap(),
                    );
                }
                _ => {
                    return Err(ProviderError::Validation(
                        "Muse user input answers must be strings or arrays".into(),
                    ))
                }
            }
            native_answers.push(Value::Object(item));
        }
        let mut params = Map::new();
        params.insert(
            "sessionId".into(),
            Value::String(self.session_ref()?.native_thread_id.clone()),
        );
        params.insert(
            "userInputId".into(),
            Value::String(request.logical_id.to_string()),
        );
        params.insert("answers".into(), Value::Array(native_answers));
        self.client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
            .command("userInput/answer", params, None)
            .await
            .map_err(Self::sdk_error)?;
        self.pending.remove(&request.logical_id);
        Ok(())
    }
}
