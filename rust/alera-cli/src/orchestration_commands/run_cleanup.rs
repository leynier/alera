//! `run cleanup ...`: the `runs.*Cleanup` payloads. Selecting removes
//! nothing; only an applied preview does.

use serde_json::{json, Map, Value};

use crate::cli_orchestration::RunCleanupAction;

use super::insert_opt;

pub(super) fn cleanup_request(
    action: RunCleanupAction,
) -> Result<(&'static str, Map<String, Value>), String> {
    let mut payload = Map::new();
    let verb = match action {
        RunCleanupAction::Preview(args) => {
            if let Some(stray) = args
                .delete_branches
                .iter()
                .find(|workspace| !args.resources.contains(workspace))
            {
                return Err(format!(
                    "--delete-branch {stray} is not one of the selected --resource values."
                ));
            }
            let resources: Vec<Value> = args
                .resources
                .iter()
                .map(|workspace| {
                    json!({
                        "workspaceId": workspace,
                        "removeBranch": args.delete_branches.contains(workspace),
                    })
                })
                .collect();
            let id = args.id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
            payload.insert("id".into(), json!(id));
            payload.insert("runId".into(), json!(args.run));
            payload.insert("resources".into(), json!(resources));
            "runs.previewCleanup"
        }
        RunCleanupAction::Apply(args) => {
            payload.insert("id".into(), json!(args.id));
            payload.insert("digest".into(), json!(args.digest));
            payload.insert("confirm".into(), json!(true));
            "runs.applyCleanup"
        }
        RunCleanupAction::Retry(args) => {
            payload.insert("id".into(), json!(args.id));
            payload.insert("digest".into(), json!(args.digest));
            "runs.retryCleanup"
        }
        RunCleanupAction::Abandon(args) => {
            payload.insert("id".into(), json!(args.id));
            payload.insert("digest".into(), json!(args.digest));
            "runs.abandonCleanup"
        }
        RunCleanupAction::Status(args) => {
            payload.insert("id".into(), json!(args.id));
            "runs.cleanup"
        }
        RunCleanupAction::List(args) => {
            payload.insert("runId".into(), json!(args.run));
            insert_opt(&mut payload, "beforeRow", args.before_row);
            "runs.cleanups"
        }
    };
    Ok((verb, payload))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleanup_preview_selects_branches_only_among_its_resources() {
        use crate::cli_orchestration::RunCleanupPreviewArgs;
        let preview = |delete: Vec<&str>| {
            cleanup_request(RunCleanupAction::Preview(RunCleanupPreviewArgs {
                run: "run-1".into(),
                resources: vec!["ws-a".into(), "ws-b".into()],
                delete_branches: delete.into_iter().map(String::from).collect(),
                id: Some("00000000-0000-0000-0000-000000000001".into()),
            }))
        };
        let (verb, payload) = preview(vec!["ws-b"]).unwrap();
        assert_eq!(verb, "runs.previewCleanup");
        assert_eq!(payload["resources"][0]["removeBranch"], false);
        assert_eq!(payload["resources"][1]["removeBranch"], true);
        assert!(preview(vec!["ws-c"]).is_err());
    }

    #[test]
    fn applying_a_cleanup_confirms_the_preview() {
        use crate::cli_orchestration::RunCleanupConfirmArgs;
        let (verb, payload) = cleanup_request(RunCleanupAction::Apply(RunCleanupConfirmArgs {
            id: "c".into(),
            digest: "d".into(),
        }))
        .unwrap();
        assert_eq!(verb, "runs.applyCleanup");
        assert_eq!(payload["confirm"], true);
    }
}
