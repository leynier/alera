impl AleraApp {
    fn sync_ai_text_selects(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let agent = self.settings_state.ai_text_agent.clone();
        let model_id =
            super::ai_text_settings_catalog::selected_model_id(&self.settings_state, &agent);
        let model_choices =
            super::ai_text_settings_catalog::model_choices(&self.settings_state, &agent);
        let model = model_choices.iter().find(|model| model.id == model_id);
        let model_label = model
            .map(|model| model.label.to_string())
            .unwrap_or_else(|| model_id.clone());
        if let Some(select) = self.settings_selects.get("ai-model") {
            let mut options = model_choices
                .iter()
                .map(|model| SettingsSelectOption::new(model.label.clone()))
                .collect::<Vec<_>>();
            if !model_id.is_empty()
                && !options
                    .iter()
                    .any(|candidate| candidate.as_str() == model_id)
            {
                options.push(SettingsSelectOption::new(model_id.clone()));
            }
            select.update(cx, |select, cx| {
                select.set_items(SearchableVec::new(options), window, cx);
                select.set_selected_value(&SharedString::from(model_label), window, cx);
            });
        }
        if let Some(select) = self.settings_selects.get("ai-thinking") {
            let selected = model.and_then(|model| {
                let thinking_id = self
                    .settings_state
                    .ai_text_selected_thinking_by_model
                    .get(&model_id)
                    .map(String::as_str)
                    .or(model.default_thinking.as_deref())?;
                model
                    .thinking_levels
                    .iter()
                    .find(|(id, _)| id == thinking_id)
                    .map(|(_, label)| label.clone())
            });
            select.update(cx, |select, cx| {
                select.set_items(
                    SearchableVec::new(
                        model
                            .into_iter()
                            .flat_map(|model| model.thinking_levels.iter())
                            .map(|(_, label)| SettingsSelectOption::new(label.clone()))
                            .collect::<Vec<_>>(),
                    ),
                    window,
                    cx,
                );
                if let Some(selected) = selected {
                    select.set_selected_value(
                        &SharedString::from(selected),
                        window,
                        cx,
                    );
                } else {
                    select.set_selected_index(None, window, cx);
                }
            });
        }
        for operation in ["commitMessage", "pullRequestDetails", "workspaceIdentity"] {
            let prompt = self
                .settings_state
                .ai_text_prompt_settings_by_operation
                .get(operation);
            let effective_agent = prompt
                .and_then(|prompt| prompt.agent.as_deref())
                .unwrap_or(&agent);
            let global_agent_label = format!(
                "Global ({})",
                super::ai_text_settings_catalog::agent_label(&agent)
            );
            let selected_agent = prompt
                .and_then(|prompt| prompt.agent.as_deref())
                .map(super::ai_text_settings_catalog::agent_label)
                .map(str::to_string)
                .unwrap_or_else(|| global_agent_label.clone());
            if let Some(select) = self
                .settings_selects
                .get(&format!("ai-prompt-{operation}-agent"))
            {
                let options =
                    std::iter::once(SettingsSelectOption::new(global_agent_label))
                        .chain(
                            super::ai_text_settings_catalog::agents()
                                .iter()
                                .map(|(_, label)| SettingsSelectOption::new(*label)),
                        )
                        .collect::<Vec<_>>();
                select.update(cx, |select, cx| {
                    select.set_items(SearchableVec::new(options), window, cx);
                    select.set_selected_value(
                        &SharedString::from(selected_agent.clone()),
                        window,
                        cx,
                    );
                });
            }

            let inherited_model_id = super::ai_text_settings_catalog::selected_model_id(
                &self.settings_state,
                effective_agent,
            );
            let effective_models = super::ai_text_settings_catalog::model_choices(
                &self.settings_state,
                effective_agent,
            );
            let inherited_model_label = effective_models
                .iter()
                .find(|model| model.id == inherited_model_id)
                .map(|model| model.label.as_str())
                .unwrap_or(&inherited_model_id);
            let global_model_label = format!("Global ({inherited_model_label})");
            let selected_model = prompt
                .and_then(|prompt| prompt.model.as_deref())
                .map(|model| {
                    effective_models
                        .iter()
                        .find(|candidate| candidate.id == model)
                        .map(|candidate| candidate.label.clone())
                        .unwrap_or_else(|| model.to_string())
                })
                .unwrap_or_else(|| global_model_label.clone());
            if let Some(select) = self
                .settings_selects
                .get(&format!("ai-prompt-{operation}-model"))
            {
                let mut options =
                    std::iter::once(SettingsSelectOption::new(global_model_label))
                        .chain(
                            effective_models
                                .iter()
                                .map(|model| SettingsSelectOption::new(model.label.clone())),
                        )
                        .collect::<Vec<_>>();
                if let Some(custom_model) = prompt.and_then(|prompt| prompt.model.as_deref()) {
                    if !options
                        .iter()
                        .any(|candidate| candidate.as_str() == custom_model)
                    {
                        options.push(SettingsSelectOption::new(custom_model.to_string()));
                    }
                }
                select.update(cx, |select, cx| {
                    select.set_items(SearchableVec::new(options), window, cx);
                    select.set_selected_value(
                        &SharedString::from(selected_model.clone()),
                        window,
                        cx,
                    );
                });
            }
            let effective_model_id = prompt
                .and_then(|prompt| prompt.model.as_deref())
                .unwrap_or(&inherited_model_id);
            let effective_model = effective_models
                .iter()
                .find(|model| model.id == effective_model_id);
            let selected_thinking = effective_model.and_then(|model| {
                let thinking_id = self
                    .settings_state
                    .ai_text_selected_thinking_by_model
                    .get(effective_model_id)
                    .map(String::as_str)
                    .or(model.default_thinking.as_deref())?;
                model
                    .thinking_levels
                    .iter()
                    .find(|(id, _)| id == thinking_id)
                    .map(|(_, label)| label.clone())
            });
            if let Some(select) = self
                .settings_selects
                .get(&format!("ai-prompt-{operation}-thinking"))
            {
                let options = effective_model
                    .into_iter()
                    .flat_map(|model| model.thinking_levels.iter())
                    .map(|(_, label)| SettingsSelectOption::new(label.clone()))
                    .collect::<Vec<_>>();
                select.update(cx, |select, cx| {
                    select.set_items(SearchableVec::new(options), window, cx);
                    if let Some(selected) = selected_thinking.clone() {
                        select.set_selected_value(&SharedString::from(selected), window, cx);
                    } else {
                        select.set_selected_index(None, window, cx);
                    }
                });
            }
        }
    }
}
