use super::*;

#[test]
#[cfg(unix)]
fn terminal_prune_removes_stopped_session_without_a_workspace_tab() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_350,
        "orphan-worker",
        "ws-1",
        "missing-tab",
        &["-c", "exit 0"],
    );
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let terminals = expect_ok(request(
            &mut writer,
            &mut reader,
            8_351,
            "orchestration.terminals",
            json!({}),
        ));
        if terminals["items"]
            .as_array()
            .unwrap()
            .iter()
            .any(|terminal| {
                terminal["handle"] == json!("orphan-worker") && terminal["running"] == json!(false)
            })
        {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "orphan terminal did not stop: {terminals}"
        );
        std::thread::sleep(Duration::from_millis(25));
    }

    let dry_run = expect_ok(request(
        &mut writer,
        &mut reader,
        8_352,
        "orchestration.terminalPrune",
        json!({"apply": false}),
    ));
    assert_eq!(dry_run["candidates"], json!(["orphan-worker"]));
    assert_eq!(dry_run["removed"], json!([]));
    let still_present = expect_ok(request(
        &mut writer,
        &mut reader,
        8_353,
        "orchestration.terminalShow",
        json!({"handle": "orphan-worker"}),
    ));
    assert_eq!(still_present["running"], json!(false));

    let applied = expect_ok(request(
        &mut writer,
        &mut reader,
        8_354,
        "orchestration.terminalPrune",
        json!({"apply": true}),
    ));
    assert_eq!(applied["removed"], json!(["orphan-worker"]));
    let terminals = expect_ok(request(
        &mut writer,
        &mut reader,
        8_355,
        "orchestration.terminals",
        json!({}),
    ));
    assert!(terminals["items"].as_array().unwrap().is_empty());

    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let options = sqlx::sqlite::SqliteConnectOptions::new()
            .filename(host._dir.path().join("terminal_history.sqlite"));
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .connect_with(options)
            .await
            .unwrap();
        let checkpoints: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM checkpoints WHERE sessionId = ?")
                .bind("orphan-worker")
                .fetch_one(&pool)
                .await
                .unwrap();
        let chunks: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM outputChunks WHERE sessionId = ?")
                .bind("orphan-worker")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!((checkpoints, chunks), (0, 0));
    });
}

#[test]
#[cfg(unix)]
fn terminal_prune_removes_unloaded_retained_spawn_and_history() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_356,
        "tab.upsert",
        json!({
            "id": "retained-worker",
            "workspaceId": "ws-1",
            "kind": "terminal",
            "title": "Retained Worker",
            "createdAt": "2026-07-24T00:00:00Z",
            "updatedAt": "2026-07-24T00:00:00Z",
            "payload": {
                "terminalSessionId": "retained-worker",
                "initialCommand": "claude",
                "spawnOnCreate": false,
                "orchestrationSpawn": {
                    "task": "task-retained",
                    "owned": true,
                    "keepOnFailure": true,
                    "startupFailureRecorded": true,
                    "retainedAfterFailure": true
                }
            }
        }),
    ));
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let options = sqlx::sqlite::SqliteConnectOptions::new()
            .filename(host._dir.path().join("terminal_history.sqlite"));
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .connect_with(options)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO checkpoints \
             (sessionId, workspaceId, tabId, workingDirectory, running, exitCode, endedAt, outputStreamBytes, updatedAt) \
             VALUES (?, ?, ?, ?, 0, 1, ?, 4, ?)",
        )
        .bind("retained-worker")
        .bind("ws-1")
        .bind("retained-worker")
        .bind("/tmp")
        .bind("2026-07-24T00:00:00Z")
        .bind("2026-07-24T00:00:00Z")
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO outputChunks (sessionId, sequence, createdAt, data) VALUES (?, 0, ?, ?)",
        )
        .bind("retained-worker")
        .bind("2026-07-24T00:00:00Z")
        .bind(b"tail".as_slice())
        .execute(&pool)
        .await
        .unwrap();
    });

    let dry_run = expect_ok(request(
        &mut writer,
        &mut reader,
        8_357,
        "orchestration.terminalPrune",
        json!({"workspace": "ws-1", "apply": false}),
    ));
    assert_eq!(dry_run["candidates"], json!(["retained-worker"]));
    let applied = expect_ok(request(
        &mut writer,
        &mut reader,
        8_358,
        "orchestration.terminalPrune",
        json!({"workspace": "ws-1", "apply": true}),
    ));
    assert_eq!(applied["removed"], json!(["retained-worker"]));
    let tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_359,
        "tab.find",
        json!({"id": "retained-worker"}),
    ));
    assert!(tab.is_null(), "{tab}");
    runtime.block_on(async {
        let options = sqlx::sqlite::SqliteConnectOptions::new()
            .filename(host._dir.path().join("terminal_history.sqlite"));
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .connect_with(options)
            .await
            .unwrap();
        let checkpoints: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM checkpoints WHERE sessionId = ?")
                .bind("retained-worker")
                .fetch_one(&pool)
                .await
                .unwrap();
        let chunks: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM outputChunks WHERE sessionId = ?")
                .bind("retained-worker")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!((checkpoints, chunks), (0, 0));
    });
}
