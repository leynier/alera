impl AleraApp {
    pub(super) fn reload_shell_environment(&mut self, cx: &mut Context<Self>) {
        self.run_settings_request(
            "shellEnvironment.reload",
            json!({}),
            "Shell Environment Reloaded",
            cx,
        );
    }

    pub(super) fn refresh_cli_registration(&mut self, cx: &mut Context<Self>) {
        self.run_cli_registration_request(
            "cliRegistration.status",
            Some("CLI Registration Refreshed"),
            cx,
        );
    }

    pub(super) fn install_cli_registration(&mut self, cx: &mut Context<Self>) {
        self.run_cli_registration_request(
            "cliRegistration.install",
            Some("CLI Registration Updated"),
            cx,
        );
    }

    pub(super) fn load_cli_registration_status(&mut self, cx: &mut Context<Self>) {
        self.run_cli_registration_request("cliRegistration.status", None, cx);
    }

    pub(super) fn install_agent_skill(
        &mut self,
        skill: &'static str,
        runner: &str,
        cx: &mut Context<Self>,
    ) {
        let skill_name = match skill {
            "cli" => "Alera CLI",
            "orchestration" => "Alera Orchestration",
            "computer-use" => "Computer Use",
            "emulator" => "Alera Emulator",
            _ => skill,
        };
        self.open_command_terminal(
            CommandTerminalRequest {
                title: format!("Install {skill_name} Skill"),
                command: agent_skill_install_command(skill, runner),
                description: Some(
                    "The Installer Runs Here. Answer Any Prompt In The Terminal.".to_owned(),
                ),
                working_directory: None,
            },
            cx,
        );
    }

    pub(super) fn install_all_agent_skills(
        &mut self,
        runner: &str,
        cx: &mut Context<Self>,
    ) {
        self.settings_state.loading = true;
        self.settings_state.error = None;
        self.settings_state.toast = None;
        let bridge = self.bridge.clone();
        let runner = runner.to_string();
        cx.spawn(async move |this, cx| {
            let mut failure = None;
            for skill in ["cli", "orchestration", "computer-use", "emulator"] {
                let operation_id = format!(
                    "gpui-{skill}-{}",
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|duration| duration.as_millis())
                        .unwrap_or_default()
                );
                if let Err(error) = bridge
                    .request(
                        "agentSkill.install",
                        json!({
                            "operationId": operation_id,
                            "skill": skill,
                            "runner": runner,
                        }),
                    )
                    .await
                {
                    failure = Some(error);
                    break;
                }
            }
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.settings_state.loading = false;
                if let Some(error) = failure {
                    this.settings_state.error = Some(error);
                } else {
                    this.settings_state.toast =
                        Some("All Alera Skills Installed / Updated".to_string());
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn copy_agent_skill_command(
        &mut self,
        skill: &'static str,
        runner: &str,
        cx: &mut Context<Self>,
    ) {
        let command = agent_skill_install_command(skill, runner);
        cx.write_to_clipboard(gpui::ClipboardItem::new_string(command));
        self.settings_state.toast = Some("Install Command Copied".to_string());
        cx.notify();
    }

    pub(super) fn persist_settings(&self) {
        self.settings_store.save(&self.settings_state);
    }

    pub(super) fn persist_shared_flutter_settings(&self, updates: Value, cx: &mut Context<Self>) {
        cx.spawn(async move |this, cx| {
            let result = super::settings_store::save_shared_flutter_settings(updates).await;
            if let Err(error) = result {
                let _ = this.update(cx, |this, cx| {
                    this.settings_state.error = Some(error);
                    cx.notify();
                });
            }
        })
        .detach();
    }

    fn update_terminal_f64(
        &mut self,
        value: &str,
        min: f64,
        max: f64,
        label: &'static str,
        update: impl FnOnce(&mut SettingsState, f64),
        cx: &mut Context<Self>,
    ) {
        if let Some(value) = parse_f64(value, min, max) {
            self.update_terminal_settings(|settings| update(settings, value), cx);
        } else {
            self.invalid_settings_value(label, cx);
        }
    }

    fn invalid_settings_value(&mut self, label: &'static str, cx: &mut Context<Self>) {
        self.settings_state.error = Some(format!("{label} Has An Invalid Value."));
        cx.notify();
    }

    fn configure_terminal_host(&mut self, cx: &mut Context<Self>) {
        let scrollback_bytes = self.settings_state.terminal_host_scrollback_bytes.max(1);
        let restore_snapshot_bytes = (self.settings_state.terminal_scrollback_lines.max(1) * 256)
            .max(256 * 1024)
            .min(scrollback_bytes);
        let payload = json!({
            "emptyShutdownDelaySeconds":
                self.settings_state.host_empty_shutdown_delay_seconds.max(1),
            "detachedSessionShutdownDelaySeconds":
                self.settings_state.host_detached_shutdown_delay_seconds.max(1),
            "scrollbackBytes": scrollback_bytes,
            "restoreSnapshotBytes": restore_snapshot_bytes,
            "loginShell": self.settings_state.terminal_login_shell,
            "crashReporting": self.settings_state.crash_reporting_enabled,
        });
        self.run_settings_request("configure", payload, "Settings Updated", cx);
    }

    fn run_settings_request(
        &mut self,
        request_type: &'static str,
        payload: Value,
        success_message: &'static str,
        cx: &mut Context<Self>,
    ) {
        self.settings_state.loading = true;
        self.settings_state.error = None;
        self.settings_state.toast = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request(request_type, payload).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.settings_state.loading = false;
                match result {
                    Ok(_) => this.settings_state.toast = Some(success_message.to_string()),
                    Err(error) => this.settings_state.error = Some(error),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn run_cli_registration_request(
        &mut self,
        request_type: &'static str,
        success_message: Option<&'static str>,
        cx: &mut Context<Self>,
    ) {
        self.settings_state.loading = true;
        self.settings_state.error = None;
        if success_message.is_some() {
            self.settings_state.toast = None;
        }
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request(request_type, json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.settings_state.loading = false;
                match result {
                    Ok(value) => {
                        match serde_json::from_value(value) {
                            Ok(status) => {
                                this.settings_state.cli_registration_status = Some(status);
                                if let Some(message) = success_message {
                                    this.settings_state.toast = Some(message.to_string());
                                }
                            }
                            Err(error) => {
                                this.settings_state.error =
                                    Some(format!("Could Not Read CLI Registration Status: {error}"));
                            }
                        }
                    }
                    Err(error) => this.settings_state.error = Some(error),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn update_runtime_setting(&mut self, key: &'static str, value: Value, cx: &mut Context<Self>) {
        self.persist_settings();
        self.settings_state.loading = true;
        self.settings_state.error = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("runtimeSettings.update", json!({(key): value}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.settings_state.loading = false;
                if let Err(error) = result {
                    this.settings_state.error = Some(error);
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }
}

fn agent_skill_install_command(skill: &str, runner: &str) -> String {
    let skill = match skill {
        "cli" => "alera-cli",
        "orchestration" => "alera-orchestration",
        "computer-use" => "computer-use",
        "emulator" => "alera-emulator",
        _ => skill,
    };
    let command = |runner: &str| {
        format!(
            "{runner} skills add https://github.com/leynier/alera --skill {skill} --global"
        )
    };
    match runner {
        "npx" => command("npx"),
        "bunx" => command("bunx"),
        _ if cfg!(target_os = "windows") => format!(
            "if (Get-Command npx -ErrorAction SilentlyContinue) {{ {} }} else {{ {} }}",
            command("npx"),
            command("bunx")
        ),
        _ => format!("{} || {}", command("npx"), command("bunx")),
    }
}
