use super::*;

#[tokio::test]
async fn runtime_relocation_ids_replay_both_directions_without_losing_later_changes() {
    let mut fixture = Fixture::new().await;
    let destination = fixture._root.path().join("workspaces/request-retry");
    let hand_off_id = uuid::Uuid::new_v4().to_string();
    let hand_off = json!({
        "id": "main", "relocationId": hand_off_id, "branch": "request-retry",
        "path": destination.to_string_lossy(), "moveChanges": false,
        "sharedImpactConfirmed": true, "deferSetup": true,
    });
    let first = fixture
        .request_relocation("handOff", hand_off.clone())
        .await;
    assert_eq!(first["ok"], true, "{first}");
    std::fs::write(destination.join("after-first.txt"), "keep this").unwrap();
    let replay = fixture
        .request_relocation("handOff", hand_off.clone())
        .await;
    assert_eq!(replay["ok"], true, "{replay}");
    assert_eq!(
        replay["payload"]["workspace"]["instanceId"],
        first["payload"]["workspace"]["instanceId"]
    );
    assert_eq!(
        std::fs::read_to_string(destination.join("after-first.txt")).unwrap(),
        "keep this"
    );
    let hand_on = json!({"id": "main", "relocationId": uuid::Uuid::new_v4().to_string(), "sharedImpactConfirmed": true});
    let returning = fixture.request_relocation("handOn", hand_on.clone()).await;
    assert_eq!(returning["ok"], true, "{returning}");
    let marker = Path::new(&fixture.main_path).join("after-return.txt");
    std::fs::write(&marker, "later shared work").unwrap();
    let replay = fixture.request_relocation("handOn", hand_on).await;
    assert_eq!(replay["ok"], true, "{replay}");
    assert_eq!(
        std::fs::read_to_string(marker).unwrap(),
        "later shared work"
    );
    assert!(!destination.exists());
    let superseded = fixture.request_relocation("handOff", hand_off).await;
    assert_eq!(superseded["ok"], false, "{superseded}");
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM workspaceRelocations WHERE workspaceId = 'main'")
            .fetch_one(fixture.actor.runtime_store.pool())
            .await
            .unwrap();
    assert_eq!(count, 2);
}
