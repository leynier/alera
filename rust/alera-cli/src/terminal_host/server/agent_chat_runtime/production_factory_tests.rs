use super::super::provider_traits::{parse_runtime_mode, provider_traits, PROVIDERS};
use super::launch_config::{build_config, ProductionConfig};
use super::*;
use alera_provider_protocol::{McpServerSpec, McpTransport, Provider, RuntimeMode};
use serde_json::json;

fn launch(provider: &str) -> ProviderLaunch {
    ProviderLaunch {
        chat_id: "chat".into(),
        generation: 1,
        provider: provider.into(),
        provider_instance_id: format!("{provider}-test"),
        cwd: Some(std::env::temp_dir().join("chat-workspace")),
        model: Some("selected-model".into()),
        runtime_mode: RuntimeMode::ApprovalRequired,
        instance: Some(ProviderInstanceConfig {
            provider_instance_id: format!("{provider}-test"),
            provider: provider.into(),
            executable: Some("custom-provider".into()),
            default_model: Some("configured-default".into()),
            env: BTreeMap::from([
                ("SHARED".into(), "instance".into()),
                ("INSTANCE_ONLY".into(), "instance-value".into()),
            ]),
            ..Default::default()
        }),
        mcp_servers: Vec::new(),
        env: BTreeMap::from([
            ("SHARED".into(), "hook".into()),
            ("ALERA_CHAT_ID".into(), "chat".into()),
        ]),
    }
}

fn environment(launch: &ProviderLaunch) -> BTreeMap<String, String> {
    merge_environment(
        BTreeMap::from([
            ("SHARED".into(), "shell".into()),
            ("SHELL_ONLY".into(), "shell-value".into()),
        ]),
        launch.instance.as_ref(),
        &launch.env,
    )
}

fn assert_process(
    executable: &Path,
    cwd: &Option<PathBuf>,
    env: &BTreeMap<OsString, OsString>,
    launch: &ProviderLaunch,
) {
    assert_eq!(executable, Path::new("custom-provider"));
    assert_eq!(cwd, &launch.cwd);
    assert_eq!(
        env.get(&OsString::from("SHARED")),
        Some(&OsString::from("hook"))
    );
    for (key, value) in [
        ("SHELL_ONLY", "shell-value"),
        ("INSTANCE_ONLY", "instance-value"),
        ("ALERA_CHAT_ID", "chat"),
    ] {
        assert_eq!(env.get(&OsString::from(key)), Some(&OsString::from(value)));
    }
}

#[test]
fn all_nine_builders_preserve_identity_model_cwd_and_environment() {
    for provider in PROVIDERS {
        let launch = launch(provider);
        match build_config(&launch, &environment(&launch)).expect(provider) {
            ProductionConfig::Codex(config) => {
                assert_process(&config.executable, &config.cwd, &config.env, &launch);
                assert_eq!(config.instance_id, launch.provider_instance_id);
                assert_eq!(config.model, launch.model);
                assert_eq!(config.args, vec![OsString::from("app-server")]);
                assert!(config.approval_policy.is_none() && config.sandbox_mode.is_none());
            }
            ProductionConfig::Claude(config) => {
                assert_eq!(
                    config.options.cli_path.as_deref(),
                    Some(Path::new("custom-provider"))
                );
                assert_eq!(config.options.cwd, launch.cwd);
                assert_eq!(config.options.model, launch.model);
                assert_eq!(config.options.env, environment(&launch));
                assert_eq!(config.provider_instance_id, launch.provider_instance_id);
                assert!(config.options.permission_mode.is_none());
            }
            ProductionConfig::Cursor(config, Some(bridge)) => {
                assert_process(
                    &bridge.process.executable,
                    &bridge.process.cwd,
                    &bridge.process.env,
                    &launch,
                );
                assert_eq!(config.provider_instance_id, launch.provider_instance_id);
                assert_eq!(config.model, launch.model);
                assert_eq!(config.cwd, launch.cwd);
                assert_eq!(
                    bridge.process.args,
                    vec![
                        OsString::from("--workspace"),
                        launch.cwd.as_ref().unwrap().as_os_str().to_owned()
                    ]
                );
            }
            ProductionConfig::Grok(config) => {
                assert_process(&config.executable, &config.cwd, &config.env, &launch);
                assert_eq!(config.instance_id, launch.provider_instance_id);
                assert_eq!(config.model, launch.model);
                assert_eq!(config.runtime_mode, launch.runtime_mode);
                assert_eq!(
                    config.spawn_args(),
                    ["--permission-mode", "default", "agent", "stdio"].map(OsString::from)
                );
            }
            ProductionConfig::Antigravity(config) => {
                assert_process(&config.executable, &config.cwd, &config.env, &launch);
                assert_eq!(config.instance_id, launch.provider_instance_id);
                assert_eq!(config.model, launch.model);
                assert_eq!(config.runtime_mode, launch.runtime_mode);
                assert!(config.args.is_empty());
            }
            ProductionConfig::Registry(config) => {
                assert_process(
                    config.executable.as_deref().unwrap(),
                    &config.cwd,
                    &config.env,
                    &launch,
                );
                assert_eq!(config.instance_id, launch.provider_instance_id);
                assert_eq!(config.agent_id, launch.provider_instance_id);
                assert_eq!(config.model, launch.model);
                assert_eq!(config.runtime_mode, launch.runtime_mode);
            }
            ProductionConfig::Pi(config) => {
                assert_process(&config.executable, &config.cwd, &config.env, &launch);
                assert_eq!(config.instance_id, launch.provider_instance_id);
                assert_eq!(config.model, launch.model);
                assert_eq!(config.runtime_mode, launch.runtime_mode);
                assert_eq!(config.args, ["--mode", "rpc"].map(OsString::from));
                assert!(config.approval_policy.is_none() && config.sandbox_mode.is_none());
            }
            ProductionConfig::Muse(config) => {
                assert_process(
                    &config.options.executable,
                    &config.options.cwd,
                    &config.options.env,
                    &launch,
                );
                assert_eq!(config.provider_instance_id, launch.provider_instance_id);
                assert_eq!(config.options.args, vec![OsString::from("serve")]);
            }
            ProductionConfig::OpenCode(config) => {
                assert_process(&config.executable, &config.cwd, &config.env, &launch);
                assert_eq!(config.provider_instance_id, launch.provider_instance_id);
                assert_eq!(config.model, launch.model);
                assert_eq!(config.directory, launch.cwd);
                assert_eq!(config.args, vec![OsString::from("serve")]);
                assert!(config.server_url.is_none());
            }
            ProductionConfig::Cursor(_, None) => {
                panic!("configured executable must own a Cursor bridge")
            }
        }
    }
}

#[test]
fn process_args_add_to_native_defaults_and_empty_args_preserve_them() {
    for provider in [
        "codex",
        "pi",
        "muse",
        "opencode",
        "antigravity",
        "acpRegistry",
        "cursor",
    ] {
        let mut launch = launch(provider);
        launch.instance.as_mut().unwrap().args = Some(vec!["--custom".into(), "value".into()]);
        let args = match build_config(&launch, &environment(&launch)).expect(provider) {
            ProductionConfig::Codex(config) => config.args,
            ProductionConfig::Pi(config) => config.args,
            ProductionConfig::Muse(config) => config.options.args,
            ProductionConfig::OpenCode(config) => config.args,
            ProductionConfig::Antigravity(config) => config.args,
            ProductionConfig::Registry(config) => config.args,
            ProductionConfig::Cursor(_, Some(config)) => config.process.args,
            _ => unreachable!(),
        };
        assert!(args.ends_with(&[OsString::from("--custom"), OsString::from("value")]));
        if provider == "codex" {
            assert_eq!(args[0], "app-server");
        }
        if provider == "pi" {
            assert_eq!(
                &args[..2],
                &[OsString::from("--mode"), OsString::from("rpc")]
            );
        }
        if matches!(provider, "muse" | "opencode") {
            assert_eq!(args[0], "serve");
        }
        launch.instance.as_mut().unwrap().args = Some(Vec::new());
        assert!(build_config(&launch, &environment(&launch)).is_ok());
    }
    for provider in ["grok", "claudeAgent"] {
        let mut launch = launch(provider);
        launch.instance.as_mut().unwrap().args = Some(vec!["--custom".into()]);
        assert!(matches!(
            build_config(&launch, &environment(&launch)),
            Err(ProviderError::Unsupported(_))
        ));
    }
}

#[test]
fn every_advertised_runtime_mode_is_preserved_and_unadvertised_modes_are_rejected() {
    for provider in PROVIDERS {
        let traits = provider_traits(provider).unwrap();
        for mode in [
            RuntimeMode::ApprovalRequired,
            RuntimeMode::AutoAcceptEdits,
            RuntimeMode::Auto,
            RuntimeMode::FullAccess,
        ] {
            let mut launch = launch(provider);
            launch.runtime_mode = mode;
            let result = build_config(&launch, &environment(&launch));
            let name = serde_json::to_value(mode).unwrap();
            assert_eq!(
                result.is_ok(),
                traits.runtime_modes.contains(&name.as_str().unwrap()),
                "{provider}: {mode:?}"
            );
            match result {
                Ok(ProductionConfig::Grok(config)) => {
                    assert_eq!(config.runtime_mode, mode);
                    assert_eq!(
                        config.spawn_args(),
                        alera_provider_grok::grok_spawn_args(mode)
                            .into_iter()
                            .map(OsString::from)
                            .collect::<Vec<_>>()
                    );
                }
                Ok(ProductionConfig::Antigravity(config)) => assert_eq!(config.runtime_mode, mode),
                Ok(ProductionConfig::Registry(config)) => assert_eq!(config.runtime_mode, mode),
                Ok(ProductionConfig::Pi(config)) => assert_eq!(config.runtime_mode, mode),
                _ => {}
            }
        }
        assert!(traits
            .runtime_modes
            .iter()
            .all(|name| parse_runtime_mode(name).is_some()));
    }
}

#[test]
fn private_options_and_policy_overrides_are_never_silently_ignored() {
    for provider in PROVIDERS {
        for key in [
            "unknownOption",
            "approvalPolicy",
            "sandboxMode",
            "runtimeMode",
        ] {
            let mut launch = launch(provider);
            launch
                .instance
                .as_mut()
                .unwrap()
                .options
                .insert(key.into(), json!("full-access"));
            assert!(
                matches!(
                    build_config(&launch, &environment(&launch)),
                    Err(ProviderError::Unsupported(_))
                ),
                "{provider}: {key}"
            );
        }
    }
}

#[test]
fn pi_mcp_servers_are_in_the_config_before_the_spawn_boundary() {
    let mut launch = launch("pi");
    launch.mcp_servers = vec![McpServerSpec {
        name: "alera".into(),
        transport: McpTransport::Stdio {
            command: std::env::current_exe().unwrap(),
            args: vec!["mcp".into()],
            env: BTreeMap::from([("CHAT_TOKEN".into(), "test-token".into())]),
            cwd: None,
        },
    }];
    let ProductionConfig::Pi(config) = build_config(&launch, &environment(&launch)).unwrap() else {
        panic!()
    };
    assert_eq!(config.mcp_servers, launch.mcp_servers);
    launch.mcp_servers[0].transport = McpTransport::Http {
        url: "http://127.0.0.1:1234/mcp".into(),
        headers: BTreeMap::new(),
    };
    assert!(matches!(
        build_config(&launch, &environment(&launch)),
        Err(ProviderError::Unsupported(_))
    ));
}

#[test]
fn connection_options_are_typed_and_preserve_generation_auth_and_profiles() {
    let mut launch = launch("opencode");
    launch
        .instance
        .as_mut()
        .unwrap()
        .options
        .insert("generation".into(), json!("legacy1"));
    launch
        .instance
        .as_mut()
        .unwrap()
        .options
        .insert("serverPassword".into(), json!("local-password"));
    let ProductionConfig::OpenCode(config) = build_config(&launch, &environment(&launch)).unwrap()
    else {
        panic!()
    };
    assert_eq!(
        config.generation,
        alera_provider_opencode::OpenCodeGeneration::Legacy1
    );
    assert_eq!(config.server_password.as_deref(), Some("local-password"));
    launch
        .instance
        .as_mut()
        .unwrap()
        .options
        .insert("generation".into(), json!("future"));
    assert!(matches!(
        build_config(&launch, &environment(&launch)),
        Err(ProviderError::Validation(_))
    ));

    let mut launch = self::launch("grok");
    launch
        .instance
        .as_mut()
        .unwrap()
        .options
        .insert("authMethod".into(), json!("api_key"));
    let ProductionConfig::Grok(config) = build_config(&launch, &environment(&launch)).unwrap()
    else {
        panic!()
    };
    assert_eq!(
        config.auth_method,
        alera_provider_grok::GrokAuthMethod::ApiKey
    );

    let mut launch = self::launch("antigravity");
    launch
        .instance
        .as_mut()
        .unwrap()
        .options
        .insert("profileDir".into(), json!("provider-profile"));
    launch
        .instance
        .as_mut()
        .unwrap()
        .options
        .insert("authMethodId".into(), json!("custom-auth"));
    let ProductionConfig::Antigravity(config) =
        build_config(&launch, &environment(&launch)).unwrap()
    else {
        panic!()
    };
    assert_eq!(config.profile_dir, Some(PathBuf::from("provider-profile")));
    assert_eq!(config.auth_method_id, "custom-auth");
}

#[test]
fn explicit_external_endpoints_reject_process_overrides_instead_of_discarding_them() {
    for provider in ["cursor", "opencode"] {
        let mut launch = launch(provider);
        let instance = launch.instance.as_mut().unwrap();
        instance.executable = None;
        instance.env.clear();
        launch.env.clear();
        if provider == "cursor" {
            instance
                .options
                .insert("bridgeUrl".into(), json!("http://127.0.0.1:1234"));
            instance
                .options
                .insert("bridgeBearerToken".into(), json!("test-token"));
        } else {
            instance
                .options
                .insert("serverUrl".into(), json!("http://127.0.0.1:1234"));
        }
        assert!(build_config(&launch, &environment(&launch)).is_ok());
        launch.env.insert("ALERA_CHAT_ID".into(), "chat".into());
        assert!(matches!(
            build_config(&launch, &environment(&launch)),
            Err(ProviderError::Unsupported(_))
        ));
    }
}

#[test]
fn local_opencode_retains_mcp_ownership_with_its_ephemeral_client_url() {
    let url = "http://127.0.0.1:1234";
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: url.into(),
        ..Default::default()
    })
    .unwrap();
    let provider =
        super::owned_provider::local_opencode_provider(transport, Default::default(), url);
    assert_eq!(provider.client().config().base_url, url);
    assert!(provider.config().server_url.is_none());
    assert!(provider.capabilities().mcp_injection.stdio);
    assert!(provider.capabilities().mcp_injection.http);
}

#[test]
fn availability_respects_explicit_paths_and_override_path() {
    let executable = std::env::current_exe().unwrap();
    let path = std::env::join_paths([executable.parent().unwrap()])
        .unwrap()
        .into_string()
        .unwrap();
    let env = BTreeMap::from([("PATH".into(), path)]);
    assert!(executable_available(Some(&executable), "missing-default", &BTreeMap::new()).is_ok());
    assert!(executable_available(
        Some(Path::new(executable.file_name().unwrap())),
        "missing-default",
        &env
    )
    .is_ok());
    assert!(executable_available(Some(executable.parent().unwrap()), "", &env).is_err());
    assert!(executable_available(None, "missing-alera-test-provider", &env).is_err());
}
