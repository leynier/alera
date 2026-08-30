impl AleraApp {
    pub(super) fn load_automations(&mut self, cx: &mut Context<Self>) {
        if self.automations_loading || !self.show_automations_dialog {
            return;
        }
        self.automations_loading = true;
        let request_epoch = self.automation_requests.begin_list();
        self.automations_error = None;
        let bridge = self.bridge.clone();
        let include_trashed = self.automation_include_trashed;
        let search = self
            .automation_search_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "automation.list",
                    json!({
                        "includeTrashed": include_trashed,
                        "search": if search.is_empty() { Value::Null } else { Value::String(search.clone()) },
                    }),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.automation_requests.accepts(request_epoch) {
                    return;
                }
                this.automations_loading = false;
                if include_trashed != this.automation_include_trashed
                    || search != this.automation_search_input.read(cx).value().trim()
                {
                    this.load_automations(cx);
                    return;
                }
                match result {
                    Ok(payload) => {
                        this.automations = payload
                            .get("items")
                            .and_then(Value::as_array)
                            .cloned()
                            .unwrap_or_default();
                        let selected = this.automation_selected_id.clone();
                        let selected = selected.filter(|id| {
                            this.automations
                                .iter()
                                .any(|item| value_string(item, "id").as_deref() == Some(id))
                        });
                        this.automation_selected_id = selected.or_else(|| {
                            this.automations
                                .first()
                                .and_then(|item| value_string(item, "id"))
                        });
                        if let Some(id) = this.automation_selected_id.clone() {
                            this.load_automation_detail(id, cx);
                        } else {
                            this.automation_requests.begin_detail();
                            this.automation_detail_loading = false;
                            this.automation_detail = None;
                        }
                    }
                    Err(error) => {
                        this.automation_detail_loading = false;
                        this.automations_error = Some(error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn load_automation_detail(&mut self, id: String, cx: &mut Context<Self>) {
        if !self.show_automations_dialog { return; }
        let request_epoch = self.automation_requests.begin_detail();
        self.automation_selected_id = Some(id.clone());
        self.automation_detail = None;
        self.automation_detail_loading = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("automation.show", json!({"id": id})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.automation_requests.accepts(request_epoch)
                    || this.automation_selected_id.as_deref() != Some(id.as_str())
                {
                    return;
                }
                this.automation_detail_loading = false;
                match result {
                    Ok(value) => this.automation_detail = Some(value),
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn run_automation_request(
        &mut self,
        request: &'static str,
        payload: Value,
        message: &'static str,
        cx: &mut Context<Self>,
    ) {
        if self.automation_action_busy || !self.show_automations_dialog {
            return;
        }
        self.automation_action_busy = true;
        self.automations_error = None;
        let bridge = self.bridge.clone();
        let view_epoch = self.automation_requests.view();
        cx.spawn(async move |this, cx| {
            let result = bridge.request(request, payload).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.automation_requests.accepts_view(view_epoch) { return; }
                this.automation_action_busy = false;
                match result {
                    Ok(_) => {
                        this.local_message = Some(message.into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                        this.refresh_automation_catalog_after_mutation(cx);
                    }
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn refresh_automation_catalog_after_mutation(&mut self, cx: &mut Context<Self>) {
        self.automation_requests.begin_list();
        self.automation_requests.begin_detail();
        self.automations_loading = false;
        self.automation_detail = None;
        self.automation_detail_loading = self.automation_selected_id.is_some();
        self.load_automations(cx);
    }
}
