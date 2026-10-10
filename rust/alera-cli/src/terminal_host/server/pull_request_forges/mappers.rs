//! Pure JSON mappers for `glab` and `az` output, ported 1:1 from the desktop's
//! `gitlab_review_mappers.dart`, `gitlab_review_comments.dart`,
//! `azure_devops_review_mappers.dart`, and `azure_devops_review_comments.dart`.
//! The shared fixtures under `test/fixtures/forges/` keep both ports honest.

use serde_json::{json, Value};

use super::identity::ForgeIdentity;
use super::model::{check_json, Review};

fn text(value: &Value, key: &str) -> Option<String> {
    value[key]
        .as_str()
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) fn gitlab_review(value: &Value) -> Review {
    let state = value["state"]
        .as_str()
        .unwrap_or("opened")
        .to_ascii_lowercase();
    let draft = value["draft"]
        .as_bool()
        .or_else(|| value["work_in_progress"].as_bool())
        .unwrap_or(false);
    let detailed = value["detailed_merge_status"]
        .as_str()
        .unwrap_or("")
        .to_ascii_lowercase();
    Review {
        number: value["iid"].as_i64().unwrap_or(0),
        title: value["title"].as_str().unwrap_or("").to_string(),
        state: match state.as_str() {
            "merged" => "MERGED",
            "closed" => "CLOSED",
            _ => "OPEN",
        },
        url: value["web_url"].as_str().unwrap_or("").to_string(),
        is_draft: draft,
        author: text(&value["author"], "username").or_else(|| text(&value["author"], "name")),
        head_branch: text(value, "source_branch"),
        base_branch: text(value, "target_branch"),
        created_at: text(value, "created_at"),
        mergeable: if value["has_conflicts"] == true {
            "CONFLICTING"
        } else {
            match detailed.as_str() {
                "mergeable" | "can_be_merged" => "MERGEABLE",
                "conflict" | "cannot_be_merged" => "CONFLICTING",
                _ => "UNKNOWN",
            }
        },
        head_sha: text(value, "sha"),
    }
}

/// The MR's head pipeline as one check, like `mapGitLabPipeline`.
pub(crate) fn gitlab_pipeline(pipeline: &Value) -> Value {
    let status = pipeline["status"]
        .as_str()
        .unwrap_or("")
        .to_ascii_lowercase();
    let bucket = match status.as_str() {
        "success" => "pass",
        "failed" | "manual" => "fail",
        "canceled" | "cancelled" => "cancel",
        "skipped" => "skipping",
        _ => "pending",
    };
    let name = match pipeline["id"].as_i64() {
        Some(id) => format!("Pipeline #{id}"),
        None => "Pipeline".to_string(),
    };
    check_json(&name, &status, bucket, text(pipeline, "web_url").as_deref())
}

/// Notes of every discussion, without system notes, oldest first.
pub(crate) fn gitlab_comments(discussions: &[Value]) -> Vec<Value> {
    let mut comments = Vec::new();
    for discussion in discussions {
        let discussion_id = discussion["id"]
            .as_str()
            .map(ToOwned::to_owned)
            .or_else(|| discussion["id"].as_i64().map(|id| id.to_string()));
        for note in discussion["notes"].as_array().into_iter().flatten() {
            if note["system"] == true {
                continue;
            }
            let position = &note["position"];
            let positioned = position.is_object();
            let resolvable = positioned || note["resolvable"] == true;
            let line = position["new_line"]
                .as_i64()
                .or_else(|| position["old_line"].as_i64());
            comments.push(json!({
                "id": note["id"].as_i64().unwrap_or(0),
                "author": text(&note["author"], "username").or_else(|| text(&note["author"], "name")),
                "body": note["body"].as_str().unwrap_or(""),
                "createdAt": text(note, "created_at"),
                "url": text(note, "url"),
                "kind": if positioned { "review" } else { "conversation" },
                "source": if positioned { "reviewThread" } else { "conversation" },
                "path": if positioned {
                    text(position, "new_path").or_else(|| text(position, "old_path"))
                } else {
                    None
                },
                "line": if positioned { line } else { None },
                "resolved": resolvable && note["resolved"] == true,
                "outdated": false,
                "threadId": if resolvable { discussion_id.clone() } else { None },
                "discussionId": discussion_id,
            }));
        }
    }
    sort_by_created_at(&mut comments);
    comments
}

pub(crate) fn azure_web_url(identity: &ForgeIdentity, number: i64) -> String {
    let project = identity.project.as_deref().unwrap_or("");
    let number = number.to_string();
    let segments = [
        project,
        "_git",
        identity.repo.as_str(),
        "pullrequest",
        &number,
    ];
    let Ok(mut url) = url::Url::parse(&identity.azure_org_url()) else {
        return format!("{}/{}", identity.azure_org_url(), segments.join("/"));
    };
    if let Ok(mut path) = url.path_segments_mut() {
        path.pop_if_empty().extend(segments);
    }
    url.to_string()
}

pub(crate) fn short_azure_ref(reference: Option<&str>) -> Option<String> {
    reference.map(|reference| {
        reference
            .strip_prefix("refs/heads/")
            .unwrap_or(reference)
            .to_string()
    })
}

pub(crate) fn azure_review(identity: &ForgeIdentity, value: &Value) -> Review {
    let number = value["pullRequestId"].as_i64().unwrap_or(0);
    let status = value["status"]
        .as_str()
        .unwrap_or("active")
        .to_ascii_lowercase();
    Review {
        number,
        title: value["title"].as_str().unwrap_or("").to_string(),
        state: match status.as_str() {
            "completed" => "MERGED",
            "abandoned" => "CLOSED",
            _ => "OPEN",
        },
        url: azure_web_url(identity, number),
        is_draft: value["isDraft"].as_bool().unwrap_or(false),
        author: text(&value["createdBy"], "displayName"),
        head_branch: short_azure_ref(value["sourceRefName"].as_str()),
        base_branch: short_azure_ref(value["targetRefName"].as_str()),
        created_at: text(value, "creationDate"),
        mergeable: match value["mergeStatus"]
            .as_str()
            .map(str::to_ascii_lowercase)
            .as_deref()
        {
            Some("succeeded") => "MERGEABLE",
            Some("conflicts") => "CONFLICTING",
            _ => "UNKNOWN",
        },
        head_sha: text(&value["lastMergeSourceCommit"], "commitId"),
    }
}

pub(crate) fn azure_policy_name(evaluation: &Value) -> String {
    text(&evaluation["configuration"]["type"], "displayName").unwrap_or_else(|| "Policy".into())
}

/// One policy evaluation as a check, like `mapAzureCheck`.
pub(crate) fn azure_check(identity: &ForgeIdentity, evaluation: &Value) -> Value {
    let status = evaluation["status"]
        .as_str()
        .unwrap_or("")
        .to_ascii_lowercase();
    let bucket = match status.as_str() {
        "approved" => "pass",
        "rejected" => "fail",
        "queued" | "running" => "pending",
        // `notApplicable` and anything Alera does not know read as neutral.
        _ => "skipping",
    };
    let url = evaluation["context"]["buildId"].as_i64().map(|build| {
        format!(
            "{}/{}/_build/results?buildId={build}",
            identity.azure_org_url(),
            identity.project.as_deref().unwrap_or("")
        )
    });
    check_json(
        &azure_policy_name(evaluation),
        &status,
        bucket,
        url.as_deref(),
    )
}

/// Comments of every live thread, without system comments, oldest first.
pub(crate) fn azure_comments(threads: &Value) -> Vec<Value> {
    let threads = threads["value"]
        .as_array()
        .or_else(|| threads.as_array())
        .cloned()
        .unwrap_or_default();
    let mut comments = Vec::new();
    for thread in threads.iter().filter(|thread| thread["isDeleted"] != true) {
        let thread_id = match &thread["id"] {
            Value::Number(id) => id.to_string(),
            Value::String(id) => id.clone(),
            _ => continue,
        };
        let context = &thread["threadContext"];
        let path = text(context, "filePath");
        let line = context["rightFileStart"]["line"].as_i64();
        let status = match &thread["status"] {
            Value::String(status) => status.to_ascii_lowercase(),
            other => other.to_string().to_ascii_lowercase(),
        };
        let resolved = matches!(status.as_str(), "fixed" | "closed" | "bydesign" | "wontfix");
        for comment in thread["comments"].as_array().into_iter().flatten() {
            let system = comment["commentType"] == 3
                || comment["commentType"]
                    .as_str()
                    .is_some_and(|kind| kind.eq_ignore_ascii_case("system"));
            if comment["isDeleted"] == true || system {
                continue;
            }
            let author = &comment["author"];
            comments.push(json!({
                "id": comment["id"].as_i64().unwrap_or(0),
                "author": text(author, "displayName").or_else(|| text(author, "uniqueName")),
                "body": comment["content"].as_str().unwrap_or(""),
                "createdAt": text(comment, "publishedDate"),
                "url": Value::Null,
                "kind": if path.is_some() { "review" } else { "conversation" },
                "source": if path.is_some() { "reviewThread" } else { "conversation" },
                "path": path,
                "line": line,
                "resolved": resolved,
                "outdated": false,
                "threadId": thread_id,
            }));
        }
    }
    sort_by_created_at(&mut comments);
    comments
}

fn sort_by_created_at(comments: &mut [Value]) {
    comments.sort_by(|a, b| {
        let created = |value: &Value| value["createdAt"].as_str().unwrap_or("").to_owned();
        created(a).cmp(&created(b))
    });
}

/// The `az devops invoke` body that opens a conversation thread.
pub(crate) fn azure_thread_body(body: &str) -> Value {
    json!({
        "comments": [{ "parentCommentId": 0, "content": body, "commentType": 1 }],
        "status": 1,
    })
}

/// The body of a reply in an existing thread.
pub(crate) fn azure_reply_body(body: &str, parent_comment_id: i64) -> Value {
    json!({ "content": body, "parentCommentId": parent_comment_id, "commentType": 1 })
}
