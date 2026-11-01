//! Installation, version and verified sign-in signals never run a model.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Duration;

use futures_util::StreamExt;
use serde_json::{json, Value};

use super::probe::{ProbeCommand, ProviderProbe};
use crate::terminal_host::diagnostics::redaction::{redact, register_secret};

pub(crate) async fn cli_status(
    provider: &str,
    executable: &Path,
    environment: &BTreeMap<String, String>,
    probe: &dyn ProviderProbe,
) -> (Option<String>, String, Option<String>) {
    let version = match probe
        .run(ProbeCommand {
            executable: executable.into(),
            args: vec!["--version".into()],
            environment: environment.clone(),
            cwd: None,
        })
        .await
    {
        Ok(output) if output.success => version(&output.stdout),
        _ => None,
    };
    let mut label = None;
    let auth = if provider == "claudeAgent" {
        // Claude settings set the CLI's env over the inherited one.
        let base_url = tokio::task::spawn_blocking({
            let environment = environment.clone();
            move || alera_provider_claude::claude_settings_base_url(&environment)
        })
        .await
        .ok()
        .flatten()
        .or_else(|| environment.get("ANTHROPIC_BASE_URL").cloned());
        match probe
            .run(ProbeCommand {
                executable: executable.into(),
                args: vec!["auth".into(), "status".into(), "--json".into()],
                environment: environment.clone(),
                cwd: None,
            })
            .await
        {
            // Claude uses a nonzero exit for a JSON loggedIn:false signal.
            Ok(output) => {
                let (auth, auth_label) = claude_auth_status(&output.stdout, base_url.as_deref());
                label = auth_label.map(str::to_owned);
                auth.into()
            }
            _ => "unknown".into(),
        }
    } else if provider == "codex" {
        codex_auth(environment).await.into()
    } else {
        "unknown".into()
    };
    (version, auth, label)
}

fn version(output: &str) -> Option<String> {
    let regex = regex::Regex::new(r"\bv?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\b")
        .expect("version regex");
    regex
        .find(&redact(output))
        .map(|matched| matched.as_str().to_owned())
}

const CUSTOM_ENDPOINT_LABEL: &str = "Custom API endpoint";

/// Claude's sign-in from `claude auth status --json`, and its label. A
/// first-party CLI pointed at a non-Anthropic endpoint reads as signed in
/// through a custom endpoint, since Anthropic account fields cannot verify
/// a proxy's credentials, as T3 Code does.
pub(crate) fn claude_auth_status(
    output: &str,
    base_url: Option<&str>,
) -> (&'static str, Option<&'static str>) {
    let Ok(status) = serde_json::from_str::<Value>(output) else {
        return ("unknown", None);
    };
    let Some(logged_in) = status["loggedIn"].as_bool() else {
        return ("unknown", None);
    };
    let first_party = match &status["apiProvider"] {
        Value::Null => true,
        Value::String(provider) => provider == "firstParty",
        _ => false,
    };
    if first_party && base_url.is_some_and(custom_api_endpoint) {
        return ("signedIn", Some(CUSTOM_ENDPOINT_LABEL));
    }
    (if logged_in { "signedIn" } else { "signedOut" }, None)
}

fn custom_api_endpoint(url: &str) -> bool {
    url::Url::parse(url.trim()).is_ok_and(|url| {
        matches!(url.scheme(), "http" | "https")
            && url
                .host_str()
                .is_some_and(|host| !host.is_empty() && host != "api.anthropic.com")
    })
}

async fn codex_auth(environment: &BTreeMap<String, String>) -> &'static str {
    tokio::time::timeout(Duration::from_secs(8), async {
        let home = environment
            .get("CODEX_HOME")
            .map(PathBuf::from)
            .or_else(|| {
                environment
                    .get(if cfg!(windows) { "USERPROFILE" } else { "HOME" })
                    .map(|home| PathBuf::from(home).join(".codex"))
            })?;
        let path = home.join("auth.json");
        if tokio::fs::metadata(&path).await.ok()?.len() > 256 * 1024 {
            return None;
        }
        let bytes = tokio::fs::read(path).await.ok()?;
        if bytes.len() > 256 * 1024 {
            return None;
        }
        let auth: Value = serde_json::from_slice(&bytes).ok()?;
        let token = auth.pointer("/tokens/access_token")?.as_str()?;
        register_secret(token);
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(6))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .ok()?;
        let mut request = client
            .get("https://chatgpt.com/backend-api/wham/usage")
            .bearer_auth(token)
            .header("User-Agent", "codex-cli")
            .header("OpenAI-Beta", "codex-1")
            .header("originator", "Codex Desktop");
        if let Some(account) = auth.pointer("/tokens/account_id").and_then(Value::as_str) {
            request = request.header("ChatGPT-Account-Id", account);
        }
        let response = request.send().await.ok()?;
        if !response.status().is_success() {
            return None;
        }
        let mut stream = response.bytes_stream();
        let mut bytes = Vec::new();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.ok()?;
            if bytes.len().saturating_add(chunk.len()) > 256 * 1024 {
                return None;
            }
            bytes.extend_from_slice(&chunk);
        }
        let usage: Value = serde_json::from_slice(&bytes).ok()?;
        if usage
            .get("rate_limit")
            .or_else(|| usage.get("rateLimit"))
            .is_some_and(Value::is_object)
        {
            Some("signedIn")
        } else {
            None
        }
    })
    .await
    .ok()
    .flatten()
    .unwrap_or("unknown")
}

pub(crate) fn setup(
    provider: &str,
    executable: Option<&Path>,
    installed: Option<bool>,
    auth_status: &str,
) -> Value {
    let Some(executable) = executable else {
        return json!([]);
    };
    let quote = |value: &str| {
        if cfg!(windows) {
            format!("\"{}\"", value.replace('"', "\"\""))
        } else {
            format!("'{}'", value.replace('\'', "'\\''"))
        }
    };
    json!(super::setup::verified_recipes(provider,executable).into_iter().filter(|recipe| match recipe.action {
        "signIn" => auth_status != "signedIn",
        "install" => installed != Some(true),
        _ => true,
    }).map(|recipe| {
        let binary = quote(&recipe.executable.to_string_lossy());
        let arguments = recipe.arguments.iter().map(|argument| quote(argument)).collect::<Vec<_>>().join(" ");
        json!({"action":recipe.action,"label":recipe.label,"command":format!("{binary} {arguments}")})
    }).collect::<Vec<_>>())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_verified_auth_json_proves_sign_in() {
        let claude_auth = |output| claude_auth_status(output, None).0;
        assert_eq!(claude_auth(r#"{"loggedIn":true}"#), "signedIn");
        assert_eq!(claude_auth(r#"{"loggedIn":false}"#), "signedOut");
        assert_eq!(claude_auth(r#"{"apiKey":"synthetic-secret"}"#), "unknown");
        assert_eq!(claude_auth("network error"), "unknown");
        assert_eq!(version("codex-cli 1.2.3"), Some("1.2.3".into()));
    }

    #[test]
    fn a_claude_proxy_endpoint_reads_as_a_custom_sign_in() {
        let signed_out = r#"{"loggedIn":false,"apiProvider":"firstParty"}"#;
        let custom = ("signedIn", Some(CUSTOM_ENDPOINT_LABEL));
        for url in ["https://proxy.example/api", "http://localhost:8080"] {
            assert_eq!(claude_auth_status(signed_out, Some(url)), custom, "{url}");
        }
        for url in [
            "https://api.anthropic.com",
            "https://api.anthropic.com:443",
            "https://api.anthropic.com:8443",
            "openrouter.ai/api",
            "localhost:8080",
            "ftp://proxy.example",
            "",
            " ",
        ] {
            assert_eq!(
                claude_auth_status(signed_out, Some(url)),
                ("signedOut", None),
                "{url}"
            );
        }
        let proxy = Some("https://proxy.example");
        assert_eq!(
            claude_auth_status(r#"{"loggedIn":true,"authMethod":"oauth_token"}"#, proxy),
            custom
        );
        assert_eq!(
            claude_auth_status(r#"{"loggedIn":true,"apiProvider":"bedrock"}"#, proxy),
            ("signedIn", None)
        );
        assert_eq!(
            claude_auth_status("network error", proxy),
            ("unknown", None)
        );
    }

    #[test]
    fn advertised_setup_respects_verified_installation_and_auth() {
        for (provider, executable) in [("codex", "codex"), ("claudeAgent", "claude")] {
            for (installed, auth, expected) in [
                (None, "unknown", vec!["signIn", "install"]),
                (None, "signedOut", vec!["signIn", "install"]),
                (None, "signedIn", vec!["install"]),
                (Some(false), "unknown", vec!["signIn", "install"]),
                (Some(false), "signedOut", vec!["signIn", "install"]),
                (Some(false), "signedIn", vec!["install"]),
                (Some(true), "unknown", vec!["signIn"]),
                (Some(true), "signedOut", vec!["signIn"]),
                (Some(true), "signedIn", vec![]),
            ] {
                let recipes = setup(provider, Some(Path::new(executable)), installed, auth);
                let actions: Vec<_> = recipes
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|recipe| recipe["action"].as_str().unwrap())
                    .collect();
                assert_eq!(actions, expected, "{provider}: {installed:?}, {auth}");
            }
        }
    }

    #[test]
    fn advertised_setup_preserves_updates_and_verified_recipe_boundaries() {
        for installed in [None, Some(false), Some(true)] {
            assert_eq!(
                setup("pi", Some(Path::new("pi")), installed, "signedIn")
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|recipe| recipe["action"].as_str().unwrap())
                    .collect::<Vec<_>>(),
                if installed == Some(true) {
                    vec!["update"]
                } else {
                    vec!["install", "update"]
                }
            );
        }
        let standalone = Path::new("/packages/standalone/codex");
        let recipes = setup("codex", Some(standalone), Some(true), "signedIn");
        assert_eq!(recipes.as_array().unwrap().len(), 1);
        assert_eq!(recipes[0]["action"], "update");
        assert_eq!(setup("acpRegistry", None, None, "unknown"), json!([]));
        assert_eq!(
            setup(
                "acpRegistry",
                Some(Path::new("custom-acp")),
                None,
                "unknown"
            ),
            json!([])
        );
        assert!(
            super::super::setup::verified_recipes("codex", Path::new("codex"))
                .iter()
                .any(|recipe| recipe.action == "signIn")
        );
    }
}
