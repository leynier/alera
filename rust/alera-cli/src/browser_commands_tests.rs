use super::*;
use crate::cli::BrowserSettingsSetArgs;

#[test]
fn search_engine_payload_uses_the_closed_wire_enum() {
    let action = BrowserAction::Settings(crate::cli::BrowserSettingsCommand {
        action: BrowserSettingsAction::Set(BrowserSettingsSetArgs {
            search_engine: crate::cli::BrowserSearchEngineArg::DuckDuckGo,
        }),
    });
    let (request_type, payload) = request_for_action(&action).unwrap();
    assert_eq!(request_type, "browser.settings.set");
    assert_eq!(payload["searchEngine"], "duckDuckGo");
}

#[test]
fn browser_failures_exit_non_zero() {
    let value = json!({
        "ok": false,
        "error": {
            "code": "page_unavailable",
            "message": "no owner",
            "nextSteps": [],
            "retryable": true,
        }
    });
    assert_eq!(report(&value, true, &BrowserAction::Capabilities), 1);
}

#[test]
fn capture_requests_never_forward_a_caller_path() {
    let action = BrowserAction::Screenshot(BrowserCaptureArgs {
        page: BrowserTimedPageArgs {
            page_id: "page-1".to_string(),
            timeout_ms: 30_000,
        },
        output: Some("/tmp/caller-controlled.png".to_string()),
    });
    let (_, payload) = request_for_action(&action).unwrap();
    assert_eq!(payload.get("outputPath"), None);
    assert_eq!(payload.get("destinationPath"), None);
    assert_eq!(payload["fullPage"], false);
}

#[test]
fn capture_artifacts_are_copied_after_the_host_returns() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("reserved.png");
    let output = dir.path().join("requested.png");
    std::fs::write(&source, b"png").unwrap();
    let action = BrowserAction::Screenshot(BrowserCaptureArgs {
        page: BrowserTimedPageArgs {
            page_id: "page-1".to_string(),
            timeout_ms: 30_000,
        },
        output: Some(output.to_string_lossy().into_owned()),
    });
    let mut response = json!({
        "ok": true,
        "artifact": {"path": source, "format": "png"}
    });
    materialize_capture_output(&mut response, &action).unwrap();
    assert_eq!(std::fs::read(output).unwrap(), b"png");
    assert!(response.get("savedTo").is_some());
}
