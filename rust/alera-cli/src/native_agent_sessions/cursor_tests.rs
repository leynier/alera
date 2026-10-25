use super::super::test_support::{outcome_for, session, write, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;

fn md5_hex(value: &str) -> String {
    use md5::{Digest, Md5};
    hex::encode(Md5::digest(value.as_bytes()))
}

#[test]
fn workspace_directories_are_the_md5_of_the_exact_path() {
    // `printf %s /work/app | md5sum`, the digest Cursor names the directory with.
    assert_eq!(md5_hex("/work/app"), "7d3bc8c3c79adb12ac244d58560d89da");
}

#[tokio::test]
async fn registered_chats_are_removed_from_any_workspace_directory() {
    let fixture = Fixture::new();
    let chats = fixture.home().join(".cursor/chats");
    write(&chats.join("aaaa/chat-1/meta.json"), "{}");
    write(&chats.join("aaaa/chat-2/meta.json"), "{}");

    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("cursor", "chat-1")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "cursor", "chat-1").result, Ok(()));
    assert!(!chats.join("aaaa/chat-1").exists());
    assert!(chats.join("aaaa/chat-2").exists());
    assert!(fixture.commands().is_empty());
}

#[tokio::test]
async fn path_scope_removes_only_the_workspace_hash_directory() {
    let mut fixture = Fixture::new();
    let data = fixture.temp.path().join("cursor-data");
    fixture
        .variables
        .insert("CURSOR_DATA_DIR".into(), data.to_string_lossy().into());
    let chats = data.join("chats");
    write(&chats.join(md5_hex("/work/app")).join("c1/meta.json"), "{}");
    write(
        &chats
            .join(md5_hex("/work/app-sibling"))
            .join("c2/meta.json"),
        "{}",
    );

    let outcomes = fixture.run(WorkspacePath, "/work/app", Vec::new()).await;

    assert_eq!(outcome_for(&outcomes, "cursor", PATH_TARGET).result, Ok(()));
    assert!(!chats.join(md5_hex("/work/app")).exists());
    assert!(chats.join(md5_hex("/work/app-sibling")).exists());
}

#[tokio::test]
async fn a_preserved_chat_keeps_its_workspace_directory() {
    let fixture = Fixture::new();
    let workspace = fixture
        .home()
        .join(".cursor/chats")
        .join(md5_hex("/work/app"));
    write(&workspace.join("keep/meta.json"), "{}");
    write(&workspace.join("drop/meta.json"), "{}");

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            Vec::new(),
            vec![session("cursor", "keep")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "cursor", PATH_TARGET).result, Ok(()));
    assert!(workspace.join("keep/meta.json").exists());
    assert!(!workspace.join("drop").exists());
}
