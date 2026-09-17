//! Runtime policy shared by every client that activates a GitHub watch.
use std::collections::{BTreeMap, BTreeSet};

use alera_core::runtime::{PullRequestWatch, PullRequestWatchDispatchMark};
use serde_json::Value;

#[derive(Debug, PartialEq)]
pub(super) enum Evaluation {
    Wait,
    Stop,
    Dispatch {
        mark: PullRequestWatchDispatchMark,
        prompt: String,
    },
    Merge {
        head: String,
        method: String,
    },
}

pub(super) fn evaluate(watch: &PullRequestWatch, snapshot: &Value) -> Evaluation {
    // Missing authentication or partial network results are not evidence that a PR disappeared.
    if snapshot["authStatus"] != "authenticated" || snapshot["provider"] != "github" {
        return Evaluation::Wait;
    }
    let review = &snapshot["review"];
    if review.is_null() || review["number"].as_i64() != Some(watch.review_number) {
        return Evaluation::Stop;
    }
    if matches!(review["state"].as_str(), Some("CLOSED" | "MERGED")) {
        return Evaluation::Stop;
    }
    let checks = review["checks"].as_array();
    let failed = checks.is_some_and(|checks| {
        checks.iter().any(|check| {
            matches!(
                check["bucket"]
                    .as_str()
                    .filter(|s| !s.is_empty())
                    .or(check["state"].as_str())
                    .unwrap_or("")
                    .to_lowercase()
                    .as_str(),
                "fail"
                    | "failure"
                    | "error"
                    | "cancel"
                    | "cancelled"
                    | "timed_out"
                    | "timedout"
                    | "action_required"
            )
        })
    });
    let green = checks.is_some_and(|checks| {
        !checks.is_empty()
            && checks.iter().all(|check| {
                matches!(
                    check["bucket"]
                        .as_str()
                        .filter(|s| !s.is_empty())
                        .or(check["state"].as_str())
                        .unwrap_or("")
                        .to_lowercase()
                        .as_str(),
                    "pass" | "success" | "skipping" | "skipped" | "neutral"
                )
            })
    });
    let author = review["author"]
        .as_str()
        .unwrap_or("")
        .trim()
        .to_lowercase();
    let mut threads: BTreeMap<&str, Vec<&Value>> = BTreeMap::new();
    if watch.comments {
        for comment in review["comments"].as_array().into_iter().flatten() {
            if let Some(id) = comment["threadId"].as_str().filter(|id| !id.is_empty()) {
                threads.entry(id).or_default().push(comment);
            }
        }
    }
    let thread_ids: BTreeSet<String> = threads
        .into_iter()
        .filter(|(_, comments)| {
            !comments.iter().all(|c| c["resolved"] == true)
                && !comments.iter().all(|c| c["outdated"] == true)
                && (author.is_empty()
                    || !comments.iter().all(|c| {
                        c["author"].as_str().unwrap_or("").trim().to_lowercase() == author
                    }))
        })
        .map(|(id, _)| id.to_string())
        .collect();
    let head = review["headSha"]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    let checks_failed = watch.checks && failed;
    let conflict = watch.conflicts && review["mergeable"] == "CONFLICTING";
    let previous = watch
        .last_dispatch
        .as_ref()
        .filter(|mark| mark.head_sha == head);
    let new_concerns = checks_failed && previous.is_none_or(|m| !m.checks_failed)
        || conflict && previous.is_none_or(|m| !m.conflict)
        || thread_ids
            .iter()
            .any(|id| previous.is_none_or(|m| !m.thread_ids.contains(id)));
    if new_concerns {
        let mut accumulated = thread_ids.clone();
        if let Some(previous) = previous {
            accumulated.extend(previous.thread_ids.iter().cloned());
        }
        let mark = PullRequestWatchDispatchMark {
            head_sha: head,
            checks_failed: checks_failed || previous.is_some_and(|m| m.checks_failed),
            conflict: conflict || previous.is_some_and(|m| m.conflict),
            thread_ids: accumulated.into_iter().collect(),
        };
        let mut concerns = Vec::new();
        if checks_failed {
            concerns.push("Fix the failed checks.".to_string());
        }
        if conflict {
            concerns.push(format!(
                "Resolve merge conflicts with the base branch {}.",
                review["baseRefName"]
                    .as_str()
                    .unwrap_or("of the pull request")
            ));
        }
        if !thread_ids.is_empty() {
            concerns.push(format!(
                "Address the unresolved review threads: {}. Resolve each thread once its fix is pushed.",
                thread_ids.into_iter().collect::<Vec<_>>().join(", ")
            ));
        }
        return Evaluation::Dispatch { mark, prompt: format!("Review pull request #{} and address these problems:\n{}\nRun relevant validation and push the fixes. Do not merge the pull request; the runtime watch handles merging when eligible.", watch.review_number, concerns.join("\n")) };
    }
    if watch.mode == "fixAndMerge"
        && green
        && review["state"] == "OPEN"
        && review["isDraft"] == false
        && review["mergeable"] == "MERGEABLE"
        && (!watch.comments || review["commentsTruncated"] == false)
        && thread_ids.is_empty()
    {
        if let Some(head) = head.filter(|head| Some(head) != watch.last_merged_head_sha.as_ref()) {
            for method in ["squash", "mergeCommit", "rebase"] {
                if snapshot["mergeMethods"]
                    .as_array()
                    .is_some_and(|methods| methods.iter().any(|m| m == method))
                {
                    return Evaluation::Merge {
                        head,
                        method: method.into(),
                    };
                }
            }
        }
    }
    Evaluation::Wait
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn watch() -> PullRequestWatch {
        serde_json::from_value(json!({"workspaceId":"w", "reviewNumber":42, "mode":"fixAndMerge", "checks":true, "comments":true, "conflicts":true, "tabId":"t"})).unwrap()
    }
    fn snapshot() -> Value {
        json!({"authStatus":"authenticated", "provider":"github", "mergeMethods":["squash"], "review":{
            "number":42,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","headSha":"abc","author":"owner",
            "checks":[{"bucket":"pass"}],"comments":[],"commentsTruncated":false
        }})
    }
    #[test]
    fn green_review_merges_only_with_complete_known_state() {
        assert_eq!(
            evaluate(&watch(), &snapshot()),
            Evaluation::Merge {
                head: "abc".into(),
                method: "squash".into()
            }
        );
        for (field, value) in [
            ("checks", json!([])),
            ("checks", json!([{"bucket":"pending"}])),
            ("checks", json!([{"bucket":"unknown"}])),
            ("isDraft", json!(true)),
            ("commentsTruncated", json!(true)),
            ("mergeable", json!("UNKNOWN")),
            ("headSha", Value::Null),
        ] {
            let mut snapshot = snapshot();
            snapshot["review"][field] = value;
            assert_eq!(evaluate(&watch(), &snapshot), Evaluation::Wait, "{field}");
        }
    }
    #[test]
    fn auth_failure_preserves_watch_but_closed_or_changed_review_stops() {
        let mut snapshot = snapshot();
        snapshot["authStatus"] = json!("notAuthenticated");
        snapshot["review"] = Value::Null;
        assert_eq!(evaluate(&watch(), &snapshot), Evaluation::Wait);
        snapshot["authStatus"] = json!("authenticated");
        assert_eq!(evaluate(&watch(), &snapshot), Evaluation::Stop);
        for state in ["CLOSED", "MERGED"] {
            let mut snapshot = self::snapshot();
            snapshot["review"]["state"] = json!(state);
            assert_eq!(evaluate(&watch(), &snapshot), Evaluation::Stop);
        }
    }
    #[test]
    fn dispatch_watermark_survives_reloads_and_accumulates_new_concerns() {
        let mut watch = watch();
        let mut snapshot = snapshot();
        snapshot["review"]["checks"] = json!([{"bucket":"fail"}]);
        let Evaluation::Dispatch { mark, .. } = evaluate(&watch, &snapshot) else {
            panic!("expected dispatch");
        };
        watch.last_dispatch = Some(mark);
        let mut restored: PullRequestWatch =
            serde_json::from_value(serde_json::to_value(watch).unwrap()).unwrap();
        assert_eq!(evaluate(&restored, &snapshot), Evaluation::Wait);
        snapshot["review"]["mergeable"] = json!("CONFLICTING");
        let Evaluation::Dispatch { mark, .. } = evaluate(&restored, &snapshot) else {
            panic!("expected new conflict");
        };
        assert!(mark.checks_failed && mark.conflict);
        restored.last_dispatch = Some(mark);
        snapshot["review"]["headSha"] = json!("new-head");
        assert!(matches!(
            evaluate(&restored, &snapshot),
            Evaluation::Dispatch { .. }
        ));
    }
    #[test]
    fn only_unresolved_current_external_threads_block_merge() {
        for ignored in [
            json!({"resolved":true,"author":"reviewer"}),
            json!({"outdated":true,"author":"reviewer"}),
            json!({"author":"OWNER"}),
        ] {
            let mut snapshot = snapshot();
            let mut comment = ignored;
            comment["threadId"] = json!("T");
            snapshot["review"]["comments"] = json!([comment]);
            assert!(matches!(
                evaluate(&watch(), &snapshot),
                Evaluation::Merge { .. }
            ));
        }
        let mut snapshot = snapshot();
        snapshot["review"]["comments"] = json!([{"threadId":"T", "author":"reviewer"}]);
        let mut watch = watch();
        let Evaluation::Dispatch { mark, .. } = evaluate(&watch, &snapshot) else {
            panic!("expected thread dispatch");
        };
        watch.last_dispatch = Some(mark);
        assert_eq!(evaluate(&watch, &snapshot), Evaluation::Wait);
    }
    #[test]
    fn scope_and_fix_mode_are_preserved() {
        let mut watch = watch();
        watch.mode = "fix".into();
        assert_eq!(evaluate(&watch, &snapshot()), Evaluation::Wait);
        watch.checks = false;
        watch.conflicts = false;
        let mut snapshot = snapshot();
        snapshot["review"]["checks"] = json!([{"bucket":"fail"}]);
        snapshot["review"]["mergeable"] = json!("CONFLICTING");
        assert_eq!(evaluate(&watch, &snapshot), Evaluation::Wait);
    }
}
