//! Vercel's fx through the ACP agent recipe (`fx acp`): Supervised runs its
//! `ask` mode, after T3 Code's `fxSessionModeForPolicy`.

use alera_agent_transport::MockTransport;
use alera_provider_acp_registry::{
    AcpRegistryAgentFlavor, AcpRegistryProvider, AcpRegistryProviderConfig, AcpRegistrySource,
};
use alera_provider_protocol::{Provider, SessionStartInput};
use serde_json::{json, Value};
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

fn local(executable: &str, args: &[&str], agent_id: &str) -> AcpRegistryProviderConfig {
    AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: agent_id.into(),
        executable: Some(PathBuf::from(executable)),
        args: args.iter().map(OsString::from).collect(),
        request_timeout: Duration::from_millis(200),
        ..Default::default()
    }
}

#[test]
fn fx_is_recognized_by_its_agent_id_or_a_local_fx_acp_launch() {
    for config in [
        local("agent", &[], "fx"),
        local("fx", &["acp"], "custom"),
        local("/opt/fx/bin/fx.exe", &["acp"], "custom"),
        local("FX.cmd", &["--verbose", "acp"], "custom"),
    ] {
        assert_eq!(
            config.agent_flavor(),
            AcpRegistryAgentFlavor::Fx,
            "{config:?}"
        );
    }
    for config in [
        local("fx", &[], "custom"),
        local("fx", &["data.json"], "custom"),
        local("fxx", &["acp"], "custom"),
        AcpRegistryProviderConfig {
            source: AcpRegistrySource::Registry,
            ..local("fx", &["acp"], "custom")
        },
    ] {
        assert_eq!(
            config.agent_flavor(),
            AcpRegistryAgentFlavor::Generic,
            "{config:?}"
        );
    }
}

fn session(id: u64) -> Value {
    json!({"jsonrpc":"2.0","id":id,"result":{"sessionId":"fx-session","configOptions":[
        {"id":"provider","category":"model","type":"select","currentValue":"xai","options":[{"value":"xai"},{"value":"openai"}]},
        {"id":"model","category":"model","type":"select","currentValue":"grok-4","options":[{"value":"grok-4"},{"value":"grok-code"}]},
        {"id":"mode","category":"mode","type":"select","currentValue":"auto","options":[{"value":"ask"},{"value":"auto"}]}
    ]}})
}

async fn start(resume: bool, model: Option<&str>) -> Vec<Value> {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true},"authMethods":[]}}),
        session(2),
        json!({"jsonrpc":"2.0","id":3,"result":{}}),
        json!({"jsonrpc":"2.0","id":4,"result":{}}),
    ]);
    let mut provider =
        AcpRegistryProvider::with_transport(transport, local("fx", &["acp"], "fx")).unwrap();
    let mut input = SessionStartInput::new("app");
    input.model = model.map(str::to_owned);
    if resume {
        input.resume_thread_id = Some("fx-session".into());
    }
    provider.start_session(input).await.unwrap();
    provider.inner().client().transport().writes().to_vec()
}

#[tokio::test]
async fn supervised_fx_sessions_run_the_ask_mode_after_new_and_load() {
    for (resume, method) in [(false, "session/new"), (true, "session/load")] {
        let writes = start(resume, None).await;
        assert_eq!(writes[1]["method"], method);
        assert_eq!(writes[2]["method"], "session/set_config_option");
        assert_eq!(
            (
                &writes[2]["params"]["configId"],
                &writes[2]["params"]["value"]
            ),
            (&json!("mode"), &json!("ask"))
        );
    }
}

#[tokio::test]
async fn the_fx_model_goes_to_its_model_option_not_its_provider() {
    let writes = start(false, Some("grok-code")).await;
    assert_eq!(writes[2]["params"]["configId"], "model");
    assert_eq!(writes[2]["params"]["value"], "grok-code");
    assert_eq!(writes[3]["params"]["configId"], "mode");
}
