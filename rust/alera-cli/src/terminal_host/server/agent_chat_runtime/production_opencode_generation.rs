//! Selects the installed OpenCode protocol before constructing its server.

use std::sync::LazyLock;
use std::time::Duration;

use alera_agent_http::{
    HttpClientConfig, HttpError, HttpRequest, HttpResponse, HttpTransport, ReqwestTransport,
};
use alera_agent_transport::{ManagedProcess, ProcessConfig};
use alera_provider_opencode::{OpenCodeGeneration, OpenCodeProviderConfig};
use alera_provider_protocol::ProviderError;
use base64::Engine;
use regex::Regex;
use serde_json::Value;
use url::Url;

use super::ProviderLaunch;

#[cfg(test)]
#[path = "production_opencode_generation_tests.rs"]
mod tests;

const CLI_PROBE_TIMEOUT: Duration = Duration::from_secs(4);
const SERVER_PROBE_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_PROBE_BYTES: usize = 8 * 1024;
const PROBE_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(1);

pub(super) async fn resolve(
    launch: &ProviderLaunch,
    config: &mut OpenCodeProviderConfig,
) -> Result<(), ProviderError> {
    if launch
        .instance
        .as_ref()
        .is_some_and(|instance| instance.options.contains_key("generation"))
    {
        return Ok(());
    }
    config.generation = if let Some(url) = &config.server_url {
        let transport = ReqwestTransport::new(HttpClientConfig {
            base_url: url.trim().to_owned(),
            request_timeout: SERVER_PROBE_TIMEOUT,
            max_response_bytes: MAX_PROBE_BYTES,
            ..Default::default()
        })
        .map_err(|_| invalid_server_url())?;
        probe_server(&transport, url, config.server_password.as_deref()).await?
    } else {
        probe_binary(config, CLI_PROBE_TIMEOUT).await?
    };
    Ok(())
}

fn binary_probe_config(config: &OpenCodeProviderConfig) -> ProcessConfig {
    ProcessConfig {
        executable: config.executable.clone(),
        args: vec!["--version".into()],
        cwd: config.cwd.clone(),
        env: config.env.clone(),
        max_frame_bytes: MAX_PROBE_BYTES,
        shutdown_timeout: PROBE_SHUTDOWN_TIMEOUT,
    }
}

async fn probe_binary(
    config: &OpenCodeProviderConfig,
    timeout: Duration,
) -> Result<OpenCodeGeneration, ProviderError> {
    let deadline = tokio::time::Instant::now() + timeout;
    let mut process =
        tokio::time::timeout_at(deadline, ManagedProcess::spawn(binary_probe_config(config)))
            .await
            .map_err(|_| cli_timeout())?
            .map_err(|_| {
                ProviderError::Protocol("Couldn't run the OpenCode CLI version probe.".into())
            })?;
    let output = tokio::time::timeout_at(deadline, async {
        let mut output = String::new();
        while let Some(line) = process.next_stdout_line().await {
            if output.len().saturating_add(line.len()).saturating_add(1) > MAX_PROBE_BYTES {
                return Err(ProviderError::Protocol(
                    "OpenCode CLI version output exceeded the probe limit.".into(),
                ));
            }
            output.push_str(&line);
            output.push('\n');
        }
        classify_cli_version(&output).ok_or_else(|| {
            ProviderError::Protocol(
                "Unable to determine OpenCode generation from its CLI version output.".into(),
            )
        })
    })
    .await
    .map_err(|_| cli_timeout())
    .and_then(|result| result);
    let _ = process.close().await;
    output
}

fn classify_cli_version(output: &str) -> Option<OpenCodeGeneration> {
    static VERSION: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"\bv?([0-9]+\.[0-9]+\.[0-9]+)\b").unwrap());
    classify_version(VERSION.captures(output)?.get(1)?.as_str())
}

fn classify_version(version: &str) -> Option<OpenCodeGeneration> {
    static VERSION: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"^v?([0-9]+)\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
            .unwrap()
    });
    let major = VERSION
        .captures(version.trim())?
        .get(1)?
        .as_str()
        .parse::<u64>()
        .ok()?;
    Some(if major >= 2 {
        OpenCodeGeneration::V2
    } else {
        OpenCodeGeneration::Legacy1
    })
}

async fn probe_server(
    transport: &impl HttpTransport,
    url: &str,
    password: Option<&str>,
) -> Result<OpenCodeGeneration, ProviderError> {
    for (path, request) in server_probe_requests(url, password)? {
        let response = tokio::time::timeout(SERVER_PROBE_TIMEOUT, transport.request(request))
            .await
            .map_err(|_| server_timeout())?;
        let response = match response {
            Ok(response) => response,
            Err(HttpError::Status { status: 401, .. }) => return Err(unauthorized()),
            Err(HttpError::Status { .. }) => continue,
            Err(HttpError::Timeout { .. }) => return Err(server_timeout()),
            Err(_) => {
                return Err(ProviderError::Protocol(
                    "Couldn't check the OpenCode server version.".into(),
                ))
            }
        };
        if response.status == 401 {
            return Err(unauthorized());
        }
        if response.body.len() > MAX_PROBE_BYTES {
            return Err(ProviderError::Protocol(
                "OpenCode server version response exceeded the probe limit.".into(),
            ));
        }
        if let Some(generation) = classify_server_response(path, &response) {
            return Ok(generation);
        }
    }
    Err(ProviderError::Protocol(
        "The server did not identify its OpenCode generation.".into(),
    ))
}

fn server_probe_requests(
    url: &str,
    password: Option<&str>,
) -> Result<[(&'static str, HttpRequest); 2], ProviderError> {
    let base = Url::parse(url.trim()).map_err(|_| invalid_server_url())?;
    if !matches!(base.scheme(), "http" | "https") {
        return Err(invalid_server_url());
    }
    let authorization = password
        .filter(|password| !password.is_empty())
        .map(|password| {
            let token = base64::engine::general_purpose::STANDARD
                .encode(format!("opencode:{password}").as_bytes());
            format!("Basic {token}")
        });
    Ok(["/api/info", "/global/health"].map(|path| {
        let mut url = base.clone();
        url.set_path(&format!("{}{path}", base.path().trim_end_matches('/')));
        let mut request = HttpRequest::new("GET", url.as_str());
        request
            .headers
            .insert("accept".into(), "application/json".into());
        if let Some(authorization) = &authorization {
            request
                .headers
                .insert("authorization".into(), authorization.clone());
        }
        (path, request)
    }))
}

fn classify_server_response(path: &str, response: &HttpResponse) -> Option<OpenCodeGeneration> {
    let media_type = response
        .headers
        .get("content-type")?
        .split(';')
        .next()?
        .trim();
    if response.status != 200 || !media_type.eq_ignore_ascii_case("application/json") {
        return None;
    }
    let body: Value = serde_json::from_slice(&response.body).ok()?;
    match path {
        "/api/info" if body.get("pid")?.as_i64().is_some() => {}
        "/global/health" if body.get("healthy")?.as_bool() == Some(true) => {}
        _ => return None,
    }
    classify_version(body.get("version")?.as_str()?)
}

fn cli_timeout() -> ProviderError {
    ProviderError::Timeout {
        operation: "OpenCode CLI version probe".into(),
    }
}

fn server_timeout() -> ProviderError {
    ProviderError::Timeout {
        operation: "OpenCode server version probe".into(),
    }
}

fn invalid_server_url() -> ProviderError {
    ProviderError::Validation("OpenCode server URL must be a valid HTTP or HTTPS URL.".into())
}

fn unauthorized() -> ProviderError {
    ProviderError::Protocol("401 Unauthorized: the OpenCode server rejected its password.".into())
}
