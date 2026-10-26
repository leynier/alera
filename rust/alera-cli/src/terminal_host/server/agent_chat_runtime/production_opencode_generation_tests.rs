use super::*;
use alera_agent_http::MockHttpTransport;
use alera_provider_protocol::RuntimeMode;
use serde::Deserialize;
use serde_json::json;
use std::collections::BTreeMap;

use super::super::launch_config::{build_config, ProductionConfig};
use super::super::ProviderInstanceConfig;

#[derive(Deserialize)]
struct Fixtures {
    cli: Vec<CliFixture>,
    servers: Vec<ServerFixture>,
}

#[derive(Deserialize)]
struct CliFixture {
    output: String,
    generation: String,
}

#[derive(Deserialize)]
struct ServerFixture {
    generation: String,
    responses: Vec<ResponseFixture>,
    unauthorized: ResponseFixture,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResponseFixture {
    status: u16,
    content_type: Option<String>,
    body: String,
}

impl ResponseFixture {
    fn response(&self) -> HttpResponse {
        let mut response = HttpResponse::new(self.status, self.body.as_bytes());
        if let Some(content_type) = &self.content_type {
            response
                .headers
                .insert("content-type".into(), content_type.clone());
        }
        response
    }
}

fn fixtures() -> Fixtures {
    // Server responses were recorded by T3 Code on 2026-09-29 from 1.18.32 and 2.0.18.
    // The 1.18.16 CLI output is the installed Mac version from this regression.
    serde_json::from_str(include_str!("production_opencode_generation_fixtures.json")).unwrap()
}

fn generation(value: &str) -> OpenCodeGeneration {
    match value {
        "legacy1" => OpenCodeGeneration::Legacy1,
        "v2" => OpenCodeGeneration::V2,
        _ => panic!("unknown fixture generation"),
    }
}

fn launch() -> ProviderLaunch {
    ProviderLaunch {
        chat_id: "generation-probe".into(),
        generation: 1,
        provider: "opencode".into(),
        provider_instance_id: "opencode-test".into(),
        cwd: None,
        model: None,
        runtime_mode: RuntimeMode::ApprovalRequired,
        instance: Some(ProviderInstanceConfig {
            provider_instance_id: "opencode-test".into(),
            provider: "opencode".into(),
            ..Default::default()
        }),
        mcp_servers: Vec::new(),
        env: BTreeMap::new(),
    }
}

fn config(launch: &ProviderLaunch) -> Box<OpenCodeProviderConfig> {
    let ProductionConfig::OpenCode(config) = build_config(launch, &BTreeMap::new()).unwrap() else {
        panic!("expected OpenCode config")
    };
    config
}

#[test]
fn canonical_cli_versions_select_the_matching_protocol() {
    for fixture in fixtures().cli {
        assert_eq!(
            classify_cli_version(&fixture.output),
            Some(generation(&fixture.generation))
        );
    }
    for output in [
        "",
        "opencode dev build\n",
        "OpenCode 2.x\n",
        "OpenCode 2.0\n",
    ] {
        assert_eq!(classify_cli_version(output), None);
    }
}

#[tokio::test]
async fn explicit_generation_wins_without_running_a_binary_or_contacting_a_server() {
    for selected in ["legacy1", "v2"] {
        for external in [false, true] {
            let mut launch = launch();
            let instance = launch.instance.as_mut().unwrap();
            instance
                .options
                .insert("generation".into(), json!(selected));
            if external {
                instance
                    .options
                    .insert("serverUrl".into(), json!("http://127.0.0.1:1"));
            } else {
                instance.executable = Some("/missing/opencode-test".into());
            }
            let mut config = config(&launch);
            resolve(&launch, &mut config).await.unwrap();
            assert_eq!(config.generation, generation(selected));
        }
    }
}

#[tokio::test]
async fn recorded_servers_require_json_and_the_matching_identity_fields() {
    for fixture in fixtures().servers {
        let transport = MockHttpTransport::new();
        for response in &fixture.responses {
            transport.push_response(response.response());
        }
        assert_eq!(
            probe_server(
                &transport,
                "http://proxy:8080/opencode/?route=oc",
                Some("pässwörd")
            )
            .await
            .unwrap(),
            generation(&fixture.generation)
        );
        let requests = transport.captured_requests();
        assert_eq!(
            requests.len(),
            if fixture.generation == "legacy1" {
                2
            } else {
                1
            }
        );
        for (request, path) in requests.iter().zip(["api/info", "global/health"]) {
            assert_eq!(request.method, "GET");
            assert_eq!(
                request.path,
                format!("http://proxy:8080/opencode/{path}?route=oc")
            );
            assert_eq!(
                request.headers["authorization"],
                "Basic b3BlbmNvZGU6cMOkc3N3w7ZyZA=="
            );
        }
    }
}

#[tokio::test]
async fn unauthorized_is_an_authentication_error_and_never_a_generation_hint() {
    for fixture in fixtures().servers {
        let transport = MockHttpTransport::new();
        transport.push_response(fixture.unauthorized.response());
        let error = probe_server(&transport, "http://127.0.0.1:4096", Some("wrong"))
            .await
            .unwrap_err();
        assert!(error.to_string().contains("401 Unauthorized"));
        assert_eq!(transport.captured_requests().len(), 1);
    }
}

#[tokio::test]
async fn html_unrelated_json_invalid_versions_and_unhealthy_servers_remain_unknown() {
    for (info, health) in [
        (
            r#"{"version":"2.0.18"}"#,
            r#"{"healthy":false,"version":"1.18.32"}"#,
        ),
        (
            r#"{"version":"2.0.18","pid":"2393556"}"#,
            r#"{"healthy":true,"version":"dev"}"#,
        ),
        (r#"{"version":"dev","pid":2393556}"#, "<!doctype html>"),
        ("invalid json", r#"{"healthy":"true","version":"1.18.32"}"#),
    ] {
        let transport = MockHttpTransport::new();
        for body in [info, health] {
            let mut response = HttpResponse::new(200, body.as_bytes());
            response
                .headers
                .insert("content-type".into(), "application/json".into());
            transport.push_response(response);
        }
        assert!(probe_server(&transport, "http://127.0.0.1:4096", None)
            .await
            .is_err());
        assert_eq!(transport.captured_requests().len(), 2);
    }
}

#[tokio::test]
async fn server_probe_errors_keep_urls_and_credentials_private() {
    let secret = "private-probe-token";
    for url in [
        format!("localhost:4096/{secret}"),
        format!("ftp://user:{secret}@10.0.0.1/"),
        format!("http://user:{secret}@10.0.0.1/?token={secret}"),
    ] {
        let transport = MockHttpTransport::new();
        transport.push_response_error(HttpError::Request {
            operation: "request",
        });
        let error = probe_server(&transport, &url, Some(secret))
            .await
            .unwrap_err()
            .to_string();
        assert!(!error.contains(secret));
        assert!(!error.contains("10.0.0.1"));
    }
    let transport = MockHttpTransport::new();
    transport.push_response_error(HttpError::Timeout {
        operation: "request",
        timeout: SERVER_PROBE_TIMEOUT,
    });
    assert!(matches!(
        probe_server(&transport, "http://localhost:4096", None).await,
        Err(ProviderError::Timeout { .. })
    ));
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(200, vec![b'x'; MAX_PROBE_BYTES + 1]));
    assert!(probe_server(&transport, "http://localhost:4096", None)
        .await
        .is_err());
}

#[tokio::test]
async fn an_external_server_is_probed_instead_of_the_unavailable_local_binary() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        let mut request = Vec::new();
        while !request.windows(4).any(|bytes| bytes == b"\r\n\r\n") {
            let mut chunk = [0; 1024];
            let read = stream.read(&mut chunk).await.unwrap();
            assert!(read > 0);
            request.extend_from_slice(&chunk[..read]);
            assert!(request.len() <= MAX_PROBE_BYTES);
        }
        let request = String::from_utf8_lossy(&request);
        assert!(request.starts_with("GET /api/info HTTP/1.1\r\n"));
        assert!(request
            .to_ascii_lowercase()
            .contains("authorization: basic b3blbmnvzgu6chc="));
        let body = r#"{"version":"2.0.18","pid":2393556}"#;
        stream.write_all(format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        ).as_bytes()).await.unwrap();
    });
    let mut launch = launch();
    let instance = launch.instance.as_mut().unwrap();
    instance.options.insert("serverUrl".into(), json!(url));
    instance
        .options
        .insert("serverPassword".into(), json!("pw"));
    let mut config = config(&launch);
    config.executable = "/missing/opencode-test".into();
    resolve(&launch, &mut config).await.unwrap();
    assert_eq!(config.generation, OpenCodeGeneration::V2);
    server.await.unwrap();
}

#[cfg(unix)]
fn binary_fixture(body: &str) -> (tempfile::TempDir, std::path::PathBuf) {
    use std::os::unix::fs::PermissionsExt;
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join("opencode-fixture");
    std::fs::write(&executable, format!("#!/bin/sh\n{body}\n")).unwrap();
    std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
    (directory, executable)
}

#[cfg(unix)]
#[tokio::test]
async fn local_version_probe_uses_the_configured_executable_cwd_and_hydrated_overrides() {
    let (directory, executable) = binary_fixture(
        "[ \"$1\" = \"--version\" ] && [ \"$#\" = \"1\" ] && [ \"$PWD\" = \"$EXPECTED_CWD\" ] || exit 2\nprintf '%s\\n' \"$PROBE_VERSION\"",
    );
    for fixture in fixtures().cli {
        let mut launch = launch();
        launch.cwd = Some(directory.path().into());
        launch.instance.as_mut().unwrap().executable = Some(executable.clone());
        launch.instance.as_mut().unwrap().args = Some(vec!["serve".into(), "--extra".into()]);
        let mut config = config(&launch);
        config
            .env
            .insert("PROBE_VERSION".into(), fixture.output.trim().into());
        config.env.insert(
            "EXPECTED_CWD".into(),
            directory.path().as_os_str().to_owned(),
        );
        resolve(&launch, &mut config).await.unwrap();
        assert_eq!(config.generation, generation(&fixture.generation));
        assert_eq!(
            config.local_server_config().generation,
            config.generation.into()
        );
    }
}

#[cfg(unix)]
#[tokio::test]
async fn local_unknown_oversized_missing_and_stalled_binaries_fail_without_guessing() {
    let (_directory, executable) = binary_fixture("printf '%s\\n' \"$PROBE_VERSION\"");
    for output in [
        "opencode dev build".to_owned(),
        "x".repeat(MAX_PROBE_BYTES + 1),
    ] {
        let mut config = OpenCodeProviderConfig {
            executable: executable.clone(),
            ..Default::default()
        };
        config.env.insert("PROBE_VERSION".into(), output.into());
        assert!(probe_binary(&config, CLI_PROBE_TIMEOUT).await.is_err());
    }
    let config = OpenCodeProviderConfig {
        executable: "/missing/opencode-test".into(),
        ..Default::default()
    };
    assert!(probe_binary(&config, CLI_PROBE_TIMEOUT).await.is_err());
    let (_directory, executable) = binary_fixture("while :; do :; done");
    let config = OpenCodeProviderConfig {
        executable,
        ..Default::default()
    };
    assert!(matches!(
        probe_binary(&config, Duration::from_millis(100)).await,
        Err(ProviderError::Timeout { .. })
    ));
}
