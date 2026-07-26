use super::*;

fn sample(session_id: &str) -> TerminalHostCheckpoint {
    TerminalHostCheckpoint {
        session_id: session_id.to_string(),
        workspace_id: "ws".to_string(),
        tab_id: "tab".to_string(),
        working_directory: "/tmp/project".to_string(),
        running: true,
        exit_code: None,
        ended_at: None,
        output_stream_bytes: 42,
        updated_at: Utc.timestamp_opt(1_700_000_000, 123_000_000).unwrap(),
        buffer: Vec::new(),
    }
}

#[tokio::test]
async fn upsert_append_then_read_round_trips_incremental_chunks() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();

    assert!(store.read("missing", 1024).await.unwrap().is_none());

    let checkpoint = sample("s1");
    store.upsert(checkpoint.clone()).await.unwrap();
    store.append_output("s1", 0, b"hello ").await.unwrap();
    store.append_output("s1", 1, b"world").await.unwrap();

    let read = store.read("s1", 1024).await.unwrap().unwrap();
    assert_eq!(read.session_id, checkpoint.session_id);
    assert_eq!(read.workspace_id, checkpoint.workspace_id);
    assert_eq!(read.output_stream_bytes, checkpoint.output_stream_bytes);
    assert_eq!(read.buffer, b"hello world");
}

#[tokio::test]
async fn read_orders_chunks_by_sequence_not_insert_order() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store.upsert(sample("s1")).await.unwrap();

    store.append_output("s1", 1, b"world").await.unwrap();
    store.append_output("s1", 0, b"hello ").await.unwrap();

    let read = store.read("s1", 1024).await.unwrap().unwrap();
    assert_eq!(read.buffer, b"hello world");
}

#[tokio::test]
async fn next_output_sequence_advances_persisted_history() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store.upsert(sample("s1")).await.unwrap();

    assert_eq!(store.next_output_sequence("s1").await.unwrap(), 0);
    store.append_output("s1", 0, b"first").await.unwrap();
    store.append_output("s1", 1, b"second").await.unwrap();

    assert_eq!(store.next_output_sequence("s1").await.unwrap(), 2);
}

#[tokio::test]
async fn append_output_trims_oldest_bytes() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store.upsert(sample("s1")).await.unwrap();

    store.append_output("s1", 0, b"abc").await.unwrap();
    store.append_output("s1", 1, b"de").await.unwrap();
    store.append_output("s1", 2, b"fg").await.unwrap();

    let read = store.read("s1", 5).await.unwrap().unwrap();
    assert_eq!(read.buffer, b"cdefg");
}

#[tokio::test]
async fn append_output_keeps_tail_of_single_oversized_chunk() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store.upsert(sample("s1")).await.unwrap();

    store.append_output("s1", 0, b"abcdefg").await.unwrap();

    let read = store.read("s1", 3).await.unwrap().unwrap();
    assert_eq!(read.buffer, b"efg");
}

#[tokio::test]
async fn shrinking_the_limit_cuts_across_chunks() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store.upsert(sample("s1")).await.unwrap();
    store.append_output("s1", 0, b"abc").await.unwrap();
    store.append_output("s1", 1, b"de").await.unwrap();
    store.append_output("s1", 2, b"fg").await.unwrap();

    // A limit above the total leaves everything alone.
    store.trim_session("s1", 9).await.unwrap();
    assert_eq!(
        store.read("s1", 100).await.unwrap().unwrap().buffer,
        b"abcdefg"
    );

    // A limit landing inside a chunk keeps that chunk's tail.
    store.trim_session("s1", 5).await.unwrap();
    assert_eq!(
        store.read("s1", 100).await.unwrap().unwrap().buffer,
        b"cdefg"
    );

    // A limit landing exactly on a boundary drops the chunk whole.
    store.trim_session("s1", 4).await.unwrap();
    assert_eq!(
        store.read("s1", 100).await.unwrap().unwrap().buffer,
        b"defg"
    );
}

#[tokio::test]
async fn shrinking_session_limit_trims_existing_chunks() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store.upsert(sample("s1")).await.unwrap();
    store.append_output("s1", 0, b"abcdefgh").await.unwrap();

    store.trim_session("s1", 3).await.unwrap();

    let read = store.read("s1", 3).await.unwrap().unwrap();
    assert_eq!(read.buffer, b"fgh");
}

#[tokio::test]
async fn delete_removes_metadata_and_chunks() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store.upsert(sample("s1")).await.unwrap();
    store.append_output("s1", 0, b"hello").await.unwrap();

    store.delete("s1").await.unwrap();

    assert!(store.read("s1", 1024).await.unwrap().is_none());
}

#[tokio::test]
async fn legacy_buffer_checkpoint_schema_is_destroyed() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(HISTORY_DATABASE_FILE_NAME);
    let options = SqliteConnectOptions::new()
        .filename(&path)
        .create_if_missing(true);
    let pool = SqlitePoolOptions::new()
        .connect_with(options)
        .await
        .unwrap();
    sqlx::query("CREATE TABLE checkpoints (sessionId TEXT PRIMARY KEY, buffer BLOB NOT NULL)")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO checkpoints (sessionId, buffer) VALUES ('old', x'4142')")
        .execute(&pool)
        .await
        .unwrap();
    drop(pool);

    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();

    assert!(store.read("old", 1024).await.unwrap().is_none());
    let columns = sqlx::query("PRAGMA table_info(checkpoints)")
        .fetch_all(&store.pool)
        .await
        .unwrap();
    assert!(!columns
        .iter()
        .any(|row| row.try_get::<String, _>("name").unwrap() == "buffer"));
}
