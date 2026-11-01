//! The session's model goes where the session keeps it, after T3 Code
//! `e4a067b526`: a model config option through `session/set_config_option`,
//! the legacy `models` state through `session/set_model`.

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderKind, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::time::Duration;

fn v1() -> Value {
    json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true},"authMethods":[]}})
}

fn v2() -> Value {
    json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"info":{"name":"agent","version":"1"},"capabilities":{"session":{}},"authMethods":[]}})
}

fn ok(id: u64) -> Value {
    json!({"jsonrpc":"2.0","id":id,"result":{}})
}

fn session(result: Value) -> Value {
    let mut result = result;
    result["sessionId"] = json!("native");
    json!({"jsonrpc":"2.0","id":2,"result":result})
}

fn model_option(id: &str, values: &[&str]) -> Value {
    let options: Vec<Value> = values.iter().map(|value| json!({"value": value})).collect();
    json!({"id":id,"type":"select","category":"model","currentValue":values[0],"options":options})
}

fn legacy(current: &str) -> Value {
    json!({"availableModels":[{"modelId":"alpha"},{"modelId":"beta"}],"currentModelId":current})
}

fn provider(frames: Vec<Value>, flavor: AcpFlavor) -> AcpProvider<MockTransport> {
    AcpProvider::with_transport(
        MockTransport::new(frames),
        AcpProviderConfig {
            provider: ProviderKind::Other("acp".into()),
            provider_instance_id: "models".into(),
            flavor,
            request_timeout: Duration::from_millis(200),
            ..AcpProviderConfig::default()
        },
    )
}

fn start(model: Option<&str>) -> SessionStartInput {
    let mut input = SessionStartInput::new("app");
    input.model = model.map(str::to_owned);
    input
}

fn writes(provider: &AcpProvider<MockTransport>) -> Vec<Value> {
    provider.client().transport().writes().to_vec()
}

fn methods(provider: &AcpProvider<MockTransport>) -> Vec<String> {
    writes(provider)
        .iter()
        .map(|write| write["method"].as_str().unwrap_or("response").to_owned())
        .collect()
}

#[tokio::test]
async fn a_legacy_model_state_enables_switching_through_set_model() {
    let mut provider = provider(
        vec![v1(), session(json!({"models": legacy("alpha")})), ok(3)],
        AcpFlavor::Generic,
    );
    assert!(!provider.capabilities().model_switch);
    provider.start_session(start(Some("beta"))).await.unwrap();
    assert!(provider.capabilities().model_switch);
    let write = &writes(&provider)[2];
    assert_eq!(write["method"], "session/set_model");
    assert_eq!(write["params"]["modelId"], "beta");
    assert_eq!(
        provider.session_model_choices(),
        vec![
            ("alpha".to_owned(), "alpha".to_owned()),
            ("beta".to_owned(), "beta".to_owned())
        ]
    );
}

#[tokio::test]
async fn a_legacy_model_that_is_already_current_is_not_written() {
    let mut provider = provider(
        vec![v1(), session(json!({"models": legacy("alpha")}))],
        AcpFlavor::Generic,
    );
    provider.start_session(start(Some("alpha"))).await.unwrap();
    assert_eq!(methods(&provider), vec!["initialize", "session/new"]);
}

#[tokio::test]
async fn the_option_path_writes_the_options_own_id_on_v1_and_v2() {
    for init in [v1(), v2()] {
        let mut provider = provider(
            vec![
                init,
                session(json!({"configOptions":[model_option("llm", &["alpha", "beta"])]})),
                ok(3),
            ],
            AcpFlavor::Generic,
        );
        provider.start_session(start(Some("beta"))).await.unwrap();
        let write = &writes(&provider)[2];
        assert_eq!(write["method"], "session/set_config_option");
        assert_eq!(write["params"]["configId"], "llm");
        assert_eq!(write["params"]["value"], "beta");
    }
}

#[tokio::test]
async fn the_model_option_wins_over_an_earlier_model_category_option() {
    let mut provider = provider(
        vec![
            v2(),
            session(json!({"configOptions":[
                model_option("provider", &["vercel", "openai"]),
                model_option("model", &["grok-code", "grok-4"])
            ]})),
            ok(3),
        ],
        AcpFlavor::Generic,
    );
    provider.start_session(start(Some("grok-4"))).await.unwrap();
    assert_eq!(writes(&provider)[2]["params"]["configId"], "model");
}

#[tokio::test]
async fn resume_reads_the_resumed_sessions_model_state() {
    let mut provider = provider(
        vec![v1(), session(json!({"models": legacy("alpha")})), ok(3)],
        AcpFlavor::Generic,
    );
    let mut input = start(Some("beta"));
    input.resume_thread_id = Some("native".into());
    provider.start_session(input).await.unwrap();
    assert_eq!(
        methods(&provider),
        vec!["initialize", "session/load", "session/set_model"]
    );
}

#[tokio::test]
async fn a_session_without_model_support_refuses_a_new_model_but_resume_keeps_it() {
    let mut fresh = provider(vec![v2(), session(json!({}))], AcpFlavor::Generic);
    let error = fresh.start_session(start(Some("beta"))).await.unwrap_err();
    assert!(matches!(error, ProviderError::Unsupported(_)), "{error:?}");

    let mut resumed = provider(vec![v2(), session(json!({}))], AcpFlavor::Generic);
    let mut input = start(Some("beta"));
    input.resume_thread_id = Some("native".into());
    let session = resumed.start_session(input).await.unwrap();
    assert_eq!(session.model.as_deref(), Some("beta"));
    assert_eq!(methods(&resumed), vec!["initialize", "session/resume"]);
}

#[tokio::test]
async fn turns_write_a_changed_model_before_the_effort_and_skip_an_unchanged_one() {
    let options = json!([
        model_option("model", &["alpha", "beta"]),
        {"id":"effort","category":"thought_level","type":"select","currentValue":"low","options":[{"value":"low"},{"value":"high"}]}
    ]);
    let mut provider = provider(
        vec![
            v2(),
            session(json!({"configOptions": options})),
            ok(3),
            json!({"jsonrpc":"2.0","id":4,"result":{"stopReason":"end_turn"}}),
            ok(5),
            ok(6),
        ],
        AcpFlavor::Generic,
    );
    provider.start_session(start(Some("alpha"))).await.unwrap();
    let mut first = TurnInput::text("app", "one");
    first.model = Some("alpha".into());
    provider.send_turn(first).await.unwrap();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::TurnStarted {
            assert_eq!(event.payload["model"], "alpha");
        }
        if event.kind == EventKind::TurnCompleted {
            break;
        }
    }
    let mut second = TurnInput::text("app", "two");
    second.model = Some("beta".into());
    second
        .options
        .insert("reasoningEffort".into(), json!("high"));
    provider.send_turn(second).await.unwrap();
    let all = writes(&provider);
    assert_eq!(
        methods(&provider),
        vec![
            "initialize",
            "session/new",
            "session/set_config_option",
            "session/prompt",
            "session/set_config_option",
            "session/set_config_option",
            "session/prompt"
        ]
    );
    assert_eq!(all[4]["params"]["configId"], "model");
    assert_eq!(all[4]["params"]["value"], "beta");
    assert_eq!(all[5]["params"]["configId"], "effort");
    assert_eq!(provider.session().unwrap().model.as_deref(), Some("beta"));
}

#[tokio::test]
async fn invalid_params_reads_as_a_rejected_model_and_other_codes_keep_their_error() {
    for (code, rejected) in [(-32602, true), (-32603, false)] {
        let mut provider = provider(
            vec![
                v2(),
                session(json!({"configOptions":[model_option("model", &["alpha", "beta"])]})),
                json!({"jsonrpc":"2.0","id":3,"error":{"code":code,"message":"nope"}}),
            ],
            AcpFlavor::Generic,
        );
        let error = provider
            .start_session(start(Some("beta")))
            .await
            .unwrap_err();
        if rejected {
            assert_eq!(
                error.to_string(),
                "provider rejected the turn: The agent did not accept the model \"beta\". Choose another model for this provider, then retry."
            );
        } else {
            assert!(
                matches!(error, ProviderError::Rpc { code: -32603, .. }),
                "{error:?}"
            );
        }
    }
}

#[tokio::test]
async fn grok_v1_model_selection_keeps_session_set_model() {
    let mut provider = provider(
        vec![
            v1(),
            session(json!({
                "models": legacy("alpha"),
                "configOptions":[model_option("model", &["alpha", "beta"])]
            })),
            ok(3),
        ],
        AcpFlavor::Grok,
    );
    provider.start_session(start(Some("beta"))).await.unwrap();
    assert_eq!(writes(&provider)[2]["method"], "session/set_model");
}
