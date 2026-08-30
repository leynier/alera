impl AleraApp {
    pub(super) fn refresh_project_config_settings(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let mut projects = self.snapshot.projects.iter().collect::<Vec<_>>();
        projects.sort_by(super::sidebar_view_options::compare_project_selection);
        let selected = self
            .project_config_settings
            .selected_project_id
            .clone()
            .filter(|id| {
                self.snapshot
                    .projects
                    .iter()
                    .any(|project| &project.id == id)
            })
            .or_else(|| projects.first().map(|project| project.id.clone()));
        let Some(project_id) = selected else {
            self.project_config_settings.loading = false;
            self.project_config_settings.reset_selection();
            cx.notify();
            return;
        };
        self.load_automation_project_policy(Some(&project_id), cx);
        self.project_config_settings.select_project(project_id.clone());
        self.project_config_settings.generation += 1;
        let generation = self.project_config_settings.generation;
        let scope = ProjectConfigRequestScope::new(project_id.clone(), self.project_config_settings.selection_epoch, self.project_config_settings.draft_signature(cx));
        self.project_config_settings.loading = true;
        self.project_config_settings.error = None;
        let bridge = self.bridge.clone();
        let request_project_id = project_id.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = async {
                let overrides = bridge.request("projectConfig.list", json!({})).await?;
                let effective = bridge
                    .request(
                        "projectConfig.effective",
                        json!({"projectId": request_project_id}),
                    )
                    .await?;
                let override_ids = overrides
                    .as_object()
                    .ok_or_else(|| "Project Config List Must Be An Object".to_string())?
                    .keys()
                    .cloned()
                    .collect::<BTreeSet<_>>();
                let effective = serde_json::from_value::<EffectiveProjectConfig>(effective)
                    .map_err(|error| format!("Invalid Effective Project Config: {error}"))?;
                Ok::<_, String>((override_ids, effective))
            }
            .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                if generation != this.project_config_settings.generation
                    || !scope.is_selected(this.project_config_settings.selected_project_id.as_deref(), this.project_config_settings.selection_epoch) {
                    return;
                }
                this.project_config_settings.loading = false;
                match result {
                    Ok((override_ids, effective)) => {
                        this.project_config_settings.override_project_ids = override_ids;
                        let replace_draft = scope.may_replace_draft(&this.project_config_settings.draft_signature(cx), this.project_config_settings.seeded_draft.as_deref());
                        this.project_config_settings
                            .seed(effective, &project_id, replace_draft, window, cx);
                    }
                    Err(error) => this.project_config_settings.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn run_project_config_request(
        &mut self,
        verb: &'static str,
        payload: Value,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.project_config_settings.saving { return; }
        let Some(project_id) = payload.get("projectId").and_then(Value::as_str).map(str::to_owned) else { return; };
        let scope = ProjectConfigRequestScope::new(project_id.clone(), self.project_config_settings.selection_epoch, self.project_config_settings.draft_signature(cx));
        self.project_config_settings.saving = true;
        self.project_config_settings.error = None;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(verb, payload, Duration::from_secs(10))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                this.project_config_settings.saving = false;
                if !scope.is_selected(this.project_config_settings.selected_project_id.as_deref(), this.project_config_settings.selection_epoch) {
                    cx.notify();
                    return;
                }
                match result {
                    Ok(_) => {
                        let draft = this.project_config_settings.draft_signature(cx);
                        if scope.draft_is_unchanged(&draft) {
                            this.project_config_settings.seeded_draft = Some(draft);
                        }
                        this.refresh_project_config_settings(window, cx);
                    }
                    Err(error) => this.project_config_settings.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }
}
