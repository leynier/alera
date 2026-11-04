//! `OpenCodeServer::spawn` against a stand-in `opencode serve` script.
#![cfg(unix)]

use opencode_agent_sdk::{OpenCodeServer, OpenCodeServerConfig, OpenCodeServerError};
use std::ffi::OsString;
use std::time::Duration;

/// Fails with `failure` on stderr until the `starts`-th start, then serves.
const SCRIPT: &str = r#"
n=$(cat "$COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT"
if [ "$n" -lt "$STARTS" ]; then echo "$FAILURE" >&2; exit 1; fi
echo "opencode server listening on http://127.0.0.1:4999"
sleep 30
"#;

async fn spawn(failure: &str, starts: u32) -> (Result<OpenCodeServer, OpenCodeServerError>, u32) {
    let directory = tempfile::tempdir().unwrap();
    let count = directory.path().join("count");
    let config = OpenCodeServerConfig {
        executable: "sh".into(),
        args: vec!["-c".into(), SCRIPT.into()],
        env: [
            ("COUNT", count.to_string_lossy().into_owned()),
            ("STARTS", starts.to_string()),
            ("FAILURE", failure.to_owned()),
            ("PATH", std::env::var("PATH").unwrap_or_default()),
        ]
        .into_iter()
        .map(|(key, value)| (OsString::from(key), OsString::from(value)))
        .collect(),
        startup_timeout: Duration::from_secs(10),
        shutdown_timeout: Duration::from_secs(1),
        ..OpenCodeServerConfig::default()
    };
    let result = OpenCodeServer::spawn(config).await;
    let starts = std::fs::read_to_string(count)
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    (result, starts)
}

#[tokio::test]
async fn a_locked_database_is_retried_until_the_server_starts() {
    let (server, starts) = spawn("Error: SQLITE_BUSY: database is locked", 3).await;
    let mut server = server.unwrap();
    assert_eq!(server.url(), "http://127.0.0.1:4999");
    assert_eq!(starts, 3);
    server.close().await.unwrap();
}

#[tokio::test]
async fn a_lock_that_outlasts_three_retries_is_reported() {
    let (server, starts) = spawn("database is locked", 99).await;
    assert!(matches!(server, Err(OpenCodeServerError::DatabaseLocked)));
    assert_eq!(starts, 4);
}

#[tokio::test]
async fn other_startup_failures_are_not_retried() {
    let (server, starts) = spawn("Error: invalid configuration", 99).await;
    assert!(matches!(server, Err(OpenCodeServerError::Exited)));
    assert_eq!(starts, 1);
}
