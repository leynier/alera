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
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "automation.list",
                    json!({
                        "includeTrashed": include_trashed,
                        "search": Value::Null,
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
                if include_trashed != this.automation_include_trashed {
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
                        this.reconcile_automation_selection(true, cx);
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

    pub(super) fn load_automation_detail(&mut self, id: String, cx: &mut Context<Self>) {
        if !self.show_automations_dialog { return; }
        let request_epoch = self.automation_requests.begin_detail();
        self.automation_selected_id = Some(id.clone());
        self.automation_detail = None;
        self.automation_detail_loading = true;
        self.automation_detail_error = None;
        self.automation_detail_tab = Default::default();
        self.automation_prompt_selection = gpui_base::TextSelectionHandle::new("", cx);
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
                    Ok(value) => {
                        this.automation_prompt_selection.set_fallback_copy_text(value["automation"]["promptTemplate"].as_str().unwrap_or_default(), cx);
                        this.automation_detail = Some(value);
                    },
                    Err(error) => this.automation_detail_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn run_automation_request(
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
