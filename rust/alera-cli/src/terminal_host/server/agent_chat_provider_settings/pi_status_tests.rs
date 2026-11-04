use super::*;
use crate::terminal_host::server::agent_chat_provider_settings::probe::ProbeOutput;
use std::sync::Mutex;

const LISTING: &str = "provider model context\nanthropic claude-a 1M\nopenai gpt-x 400K\n";

struct FakeProbe {
    listing: &'static str,
    auth: &'static str,
    calls: Mutex<Vec<Vec<String>>>,
}

impl FakeProbe {
    fn new(listing: &'static str, auth: &'static str) -> Self {
        Self {
            listing,
            auth,
            calls: Mutex::new(Vec::new()),
        }
    }
}

#[async_trait::async_trait]
impl ProviderProbe for FakeProbe {
    async fn run(&self, command: ProbeCommand) -> Result<ProbeOutput, String> {
        self.calls.lock().unwrap().push(command.args.clone());
        let stdout = if command.args[0] == "auth" {
            self.auth
        } else {
            self.listing
        };
        Ok(ProbeOutput {
            // Pi exits nonzero when the provider is not ready.
            success: command.args[0] != "auth",
            stdout: stdout.into(),
        })
    }
}

fn agent_dir(settings: &str) -> (tempfile::TempDir, BTreeMap<String, String>) {
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(directory.path().join("settings.json"), settings).unwrap();
    let environment = BTreeMap::from([(
        "PI_CODING_AGENT_DIR".to_owned(),
        directory.path().to_string_lossy().into_owned(),
    )]);
    (directory, environment)
}

async fn note(
    probe: &FakeProbe,
    args: &[&str],
    settings: &str,
    version: Option<&str>,
) -> Option<String> {
    let (_directory, environment) = agent_dir(settings);
    let args: Vec<OsString> = args.iter().map(OsString::from).collect();
    pi_model_note(Path::new("pi"), &args, &environment, version, probe).await
}

const XAI_DEFAULT: &str = r#"{"defaultProvider":"xai","defaultModel":"grok-5"}"#;
const MISSING: &str =
    r#"{"status":"not_ready","provider":"xai","reason":"credentials_not_configured"}"#;

#[tokio::test]
async fn a_default_with_listed_models_needs_no_note() {
    let probe = FakeProbe::new(LISTING, MISSING);
    let settings = r#"{"defaultProvider":"openai","defaultModel":"gpt-x"}"#;
    assert_eq!(note(&probe, &[], settings, Some("1.4.0")).await, None);
    assert_eq!(note(&probe, &[], "{}", Some("1.4.0")).await, None);
    assert_eq!(probe.calls.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn an_empty_listing_means_no_usable_models() {
    let probe = FakeProbe::new("provider model context\n", MISSING);
    assert_eq!(
        note(&probe, &[], XAI_DEFAULT, Some("1.4.0"))
            .await
            .as_deref(),
        Some(NO_MODELS)
    );
}

#[tokio::test]
async fn auth_check_explains_missing_credentials() {
    let probe = FakeProbe::new(LISTING, MISSING);
    let message = note(&probe, &[], XAI_DEFAULT, Some("v0.84.1"))
        .await
        .unwrap();
    assert!(
        message.starts_with("Pi default (xai/grok-5) has no credentials configured for xai."),
        "{message}"
    );
    assert_eq!(
        probe.calls.lock().unwrap()[1],
        [
            "auth",
            "check",
            "--provider",
            "xai",
            "--json",
            "--no-refresh"
        ]
    );
}

#[tokio::test]
async fn falls_back_without_auth_check_support_or_with_a_launch_key() {
    for (version, args) in [
        (Some("0.84.0"), &[][..]),
        (None, &[][..]),
        (Some("1.4.0"), &["--api-key", "secret"][..]),
    ] {
        let probe = FakeProbe::new(LISTING, MISSING);
        let message = note(&probe, args, XAI_DEFAULT, version).await.unwrap();
        assert!(
            message.contains("uses xai, which has no available models in Pi"),
            "{message}"
        );
        assert_eq!(probe.calls.lock().unwrap().len(), 1, "{version:?} {args:?}");
    }
    let probe = FakeProbe::new(LISTING, r#"{"reason":"provider_not_found"}"#);
    let message = note(&probe, &[], XAI_DEFAULT, Some("1.4.0")).await.unwrap();
    assert!(
        message.contains("which has no available models"),
        "{message}"
    );
}

#[tokio::test]
async fn launch_arguments_override_the_settings_default() {
    let probe = FakeProbe::new(LISTING, MISSING);
    let args = ["--mode", "rpc", "--model", "openai/gpt-x"];
    assert_eq!(note(&probe, &args, XAI_DEFAULT, Some("1.4.0")).await, None);
    assert_eq!(
        launch_default(&["--provider".into(), "xai".into()]),
        Some(PiDefault {
            provider: "xai".into(),
            model: None
        })
    );
    assert_eq!(launch_default(&["--model".into(), "bare".into()]), None);
    assert_eq!(
        parse_settings(&serde_json::json!({"defaultModel": "x"})),
        None
    );
}
