//! The REST bodies the Azure DevOps provider sends through `az devops invoke
//! --in-file`, and the guard that keeps the azure-cli `@file` expansion away
//! from every argument it still passes on the command line.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::provider::CreateInput;

/// `refs/heads/<branch>` unless [branch] is already a full ref, as
/// `az repos pr create` and `az repos pr list` qualify it.
pub(super) fn qualified_ref(branch: &str) -> String {
    if branch.starts_with("refs/") {
        branch.to_string()
    } else {
        format!("refs/heads/{branch}")
    }
}

/// The value for `--source-branch`. azure-cli reads an argument that starts
/// with `@` as a file to load, so such a branch is passed as its full ref,
/// which `az repos pr list` treats the same.
pub(super) fn branch_argument(branch: &str) -> String {
    if branch.starts_with('@') {
        qualified_ref(branch)
    } else {
        branch.to_string()
    }
}

/// azure-cli replaces an argument of the form `@path` with that file's
/// contents. Nothing the provider passes should, so any such argument is
/// refused before `az` runs rather than letting it read a local file.
pub(super) fn reject_file_expansion(args: &[String]) -> HostResult<()> {
    match args.iter().find(|arg| arg.starts_with('@')) {
        Some(arg) => Err(HostError::state(format!(
            "Refusing to pass {arg:?} to az: azure-cli would read it as a file."
        ))),
        None => Ok(()),
    }
}

/// The `POST pullRequests` body `az repos pr create` sends for [input].
pub(super) fn create_body(input: &CreateInput) -> Value {
    json!({
        "sourceRefName": qualified_ref(&input.head),
        "targetRefName": qualified_ref(&input.base),
        "title": input.title,
        "description": input.body,
        "isDraft": input.draft,
    })
}

/// The `PATCH pullRequests/{id}` body that completes [existing]. Azure
/// DevOps rejects it when the source branch has moved past [expected_head],
/// so the head check holds on the server instead of between two calls. The
/// pull request's own completion options are kept, as `az repos pr update
/// --status completed` keeps them, with the merge strategy set explicitly.
pub(super) fn completion_body(existing: &Value, expected_head: &str, squash: bool) -> Value {
    let mut options = existing["completionOptions"]
        .as_object()
        .cloned()
        .unwrap_or_default();
    options.insert("squashMerge".into(), Value::Bool(squash));
    options.insert(
        "mergeStrategy".into(),
        Value::String(if squash { "squash" } else { "noFastForward" }.into()),
    );
    json!({
        "status": "completed",
        "lastMergeSourceCommit": { "commitId": expected_head },
        "completionOptions": options,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn at_arguments_are_refused_or_qualified() {
        let args = ["repos", "pr", "list", "--title", "@/etc/passwd"].map(String::from);
        assert!(reject_file_expansion(&args).is_err());
        assert!(reject_file_expansion(&["a@b".to_string()]).is_ok());
        assert_eq!(branch_argument("@secrets"), "refs/heads/@secrets");
        assert_eq!(branch_argument("feature"), "feature");
        assert_eq!(qualified_ref("refs/heads/main"), "refs/heads/main");
    }

    #[test]
    fn completion_keeps_the_pull_request_options_and_binds_the_head() {
        let existing = json!({
            "completionOptions": { "deleteSourceBranch": true, "mergeStrategy": "rebase" }
        });
        let body = completion_body(&existing, "abc", false);
        assert_eq!(body["status"], "completed");
        assert_eq!(body["lastMergeSourceCommit"]["commitId"], "abc");
        assert_eq!(body["completionOptions"]["deleteSourceBranch"], true);
        assert_eq!(body["completionOptions"]["squashMerge"], false);
        assert_eq!(body["completionOptions"]["mergeStrategy"], "noFastForward");
        let body = completion_body(&Value::Null, "abc", true);
        assert_eq!(body["completionOptions"]["mergeStrategy"], "squash");
    }
}
