use super::*;
use serde_json::json;
use std::sync::Mutex;

struct Owner {
    response: Value,
    scripts: Mutex<Vec<String>>,
}
impl RemoteHostExecutor for Owner {
    async fn probe_windows(&self, _: &alera_core::runtime::SshTarget) -> Option<bool> {
        Some(false)
    }
    async fn run(
        &self,
        _: &alera_core::runtime::SshTarget,
        _: bool,
        script: &str,
    ) -> Result<String> {
        self.scripts.lock().unwrap().push(script.into());
        Ok(self.response.to_string())
    }
}

#[tokio::test]
async fn setup_response_requires_exact_identity_attempt_and_a_persisted_report() {
    let (_root, store, pending, preparation, completion) =
        crate::remote_workspace_relocation::tests::fixture().await;
    store
        .record_remote_workspace_relocation_preparation(
            &pending.id,
            &serde_json::from_value(preparation["relocation"].clone()).unwrap(),
        )
        .await
        .unwrap();
    let attempt = uuid::Uuid::new_v4().to_string();
    let setup = RelocationSetupReceipt {
        relocation_id: pending.id.clone(),
        config: Default::default(),
        attempt_id: Some(attempt.clone()),
        report: Some(WorktreeSetupReport::empty()),
    };
    let response = json!({"version":1,"workspace":completion["workspace"],"relocationId":pending.id,"action":"recover","setup":setup,"result":{"steps":[]}});
    let request = || SetupRequest {
        workspace_id: pending.source.id.clone(),
        relocation_id: pending.id.clone(),
        attempt_id: Some(attempt.clone()),
        action: OwnerSetupAction::Recover,
    };
    for (pointer, value) in [
        ("/workspace/instanceId", json!("foreign")),
        ("/workspace/path", json!("/another/checkout")),
        ("/setup/attemptId", json!(uuid::Uuid::new_v4())),
        ("/setup/report", Value::Null),
        ("/action", json!("cancel")),
    ] {
        let mut invalid = response.clone();
        *invalid.pointer_mut(pointer).unwrap() = value;
        let remote = Owner {
            response: invalid,
            scripts: Mutex::new(vec![]),
        };
        assert!(execute(&store, request(), &remote).await.is_err());
    }
    let remote = Owner {
        response,
        scripts: Mutex::new(vec![]),
    };
    assert_eq!(
        execute(&store, request(), &remote).await.unwrap(),
        json!({"steps":[]})
    );
    let script = remote.scripts.lock().unwrap()[0].clone();
    assert!(script.contains("--action recover"));
    assert!(script.contains(&format!("--attempt-id '{attempt}'")));
    assert!(!script.contains("enroll"));
    assert_eq!(
        store
            .find_workspace(&pending.source.id)
            .await
            .unwrap()
            .unwrap()
            .path,
        pending.source.path
    );
    assert!(store
        .find_remote_workspace_relocation_receipt(&pending.id)
        .await
        .unwrap()
        .is_none());
}
