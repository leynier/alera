//! Pull request comments for the mobile Pull Request panel: conversation
//! comments, review summaries, and diff review threads, in the shape the
//! desktop forge layer produces (`github_review_comments.dart`) so both
//! surfaces group the same conversation.
//!
//! Every field beyond `id`, `author`, `body`, `createdAt`, and `url` is
//! additive: an older phone ignores them, and a phone talking to an older host
//! treats every comment as a conversation comment. None of this bumps
//! `aleraMobileProtocolVersion`.

use serde_json::{json, Value};

use super::mobile_pull_request_requests::run_gh;

const REVIEW_THREADS_QUERY: &str = r#"
query($owner: String!, $repo: String!, $pr: Int!, $threadsAfter: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $threadsAfter) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          line
          originalLine
          comments(first: 100) {
            nodes {
              databaseId
              author { login }
              body
              createdAt
              url
              path
            }
          }
        }
      }
    }
  }
}
"#;

/// Caps the thread pages one snapshot fetches (100 threads each). Replies
/// past the first 100 of a single thread are not paged either: a phone reads
/// the conversation, and the full history stays one tap away on the forge.
const MAX_THREAD_PAGES: usize = 10;

pub(super) async fn load_comments(
    repo_path: &str,
    host: &str,
    owner: &str,
    repo: &str,
    number: i64,
) -> Vec<Value> {
    let conversation_endpoint =
        format!("repos/{owner}/{repo}/issues/{number}/comments?per_page=100");
    let reviews_endpoint = format!("repos/{owner}/{repo}/pulls/{number}/reviews?per_page=100");
    let (conversation, reviews, threads) = tokio::join!(
        fetch_rest_pages(repo_path, host, &conversation_endpoint),
        fetch_rest_pages(repo_path, host, &reviews_endpoint),
        fetch_review_threads(repo_path, host, owner, repo, number),
    );
    let mut comments = map_issue_comments(&conversation);
    comments.extend(map_review_summaries(&reviews));
    comments.extend(threads);
    sort_by_created_at(&mut comments);
    comments
}

/// A failed or unparsable source yields nothing, so one unavailable endpoint
/// does not hide the others.
async fn fetch_rest_pages(repo_path: &str, host: &str, endpoint: &str) -> Vec<Value> {
    let Ok((0, stdout, _)) = run_gh(
        repo_path,
        &["api", "--hostname", host, "--paginate", "--slurp", endpoint],
    )
    .await
    else {
        return Vec::new();
    };
    flatten_slurped_pages(&stdout)
}

async fn fetch_review_threads(
    repo_path: &str,
    host: &str,
    owner: &str,
    repo: &str,
    number: i64,
) -> Vec<Value> {
    let query = format!("query={REVIEW_THREADS_QUERY}");
    let owner = format!("owner={owner}");
    let repo = format!("repo={repo}");
    let pr = format!("pr={number}");
    let mut comments = Vec::new();
    let mut after: Option<String> = None;
    for _ in 0..MAX_THREAD_PAGES {
        let after_arg = after
            .as_ref()
            .map(|cursor| format!("threadsAfter={cursor}"));
        let mut args = vec![
            "api",
            "--hostname",
            host,
            "graphql",
            "-f",
            &query,
            "-f",
            &owner,
            "-f",
            &repo,
            "-F",
            &pr,
        ];
        if let Some(after_arg) = &after_arg {
            args.extend(["-f", after_arg]);
        }
        let Ok((0, stdout, _)) = run_gh(repo_path, &args).await else {
            break;
        };
        let Ok(value) = serde_json::from_str::<Value>(&stdout) else {
            break;
        };
        let connection = &value["data"]["repository"]["pullRequest"]["reviewThreads"];
        comments.extend(map_review_threads(connection));
        match next_cursor(connection) {
            Some(next) if after.as_deref() != Some(next.as_str()) => after = Some(next),
            _ => break,
        }
    }
    comments
}

fn flatten_slurped_pages(stdout: &str) -> Vec<Value> {
    let Ok(Value::Array(pages)) = serde_json::from_str::<Value>(stdout) else {
        return Vec::new();
    };
    pages
        .into_iter()
        .flat_map(|page| match page {
            Value::Array(entries) => entries,
            Value::Object(_) => vec![page],
            _ => Vec::new(),
        })
        .collect()
}

fn map_issue_comments(entries: &[Value]) -> Vec<Value> {
    entries
        .iter()
        .map(|entry| rest_comment(entry, "created_at", "conversation"))
        .collect()
}

/// Reviews without a body (a bare approval) carry nothing to read.
fn map_review_summaries(entries: &[Value]) -> Vec<Value> {
    entries
        .iter()
        .filter(|entry| {
            entry
                .get("body")
                .and_then(Value::as_str)
                .is_some_and(|body| !body.trim().is_empty())
        })
        .map(|entry| rest_comment(entry, "submitted_at", "reviewSummary"))
        .collect()
}

fn rest_comment(entry: &Value, created_at_field: &str, source: &str) -> Value {
    json!({
        "id": entry.get("id").and_then(Value::as_i64).unwrap_or(0),
        "author": entry.get("user").and_then(|user| user.get("login")).and_then(Value::as_str),
        "body": entry.get("body").and_then(Value::as_str).unwrap_or(""),
        "createdAt": entry.get(created_at_field).and_then(Value::as_str),
        "url": entry.get("html_url").and_then(Value::as_str),
        "kind": "conversation",
        "source": source,
    })
}

fn map_review_threads(connection: &Value) -> Vec<Value> {
    let Some(threads) = connection.get("nodes").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut comments = Vec::new();
    for thread in threads {
        let thread_id = thread.get("id").and_then(Value::as_str);
        let resolved = thread
            .get("isResolved")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let line = thread
            .get("line")
            .and_then(Value::as_i64)
            .or_else(|| thread.get("originalLine").and_then(Value::as_i64));
        let Some(nodes) = thread["comments"]["nodes"].as_array() else {
            continue;
        };
        for node in nodes {
            comments.push(json!({
                "id": node.get("databaseId").and_then(Value::as_i64).unwrap_or(0),
                "author": node.get("author").and_then(|author| author.get("login")).and_then(Value::as_str),
                "body": node.get("body").and_then(Value::as_str).unwrap_or(""),
                "createdAt": node.get("createdAt").and_then(Value::as_str),
                "url": node.get("url").and_then(Value::as_str),
                "kind": "review",
                "source": "reviewThread",
                "path": node.get("path").and_then(Value::as_str),
                "line": line,
                "resolved": resolved,
                "threadId": thread_id,
            }));
        }
    }
    comments
}

fn next_cursor(connection: &Value) -> Option<String> {
    let page_info = connection.get("pageInfo")?;
    if page_info.get("hasNextPage").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    page_info
        .get("endCursor")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

/// GitHub timestamps are uniform RFC 3339 UTC strings, so they order
/// lexicographically. The sort is stable, and an entry without a timestamp
/// sorts first.
fn sort_by_created_at(comments: &mut [Value]) {
    comments.sort_by(|a, b| {
        let created = |value: &Value| value["createdAt"].as_str().unwrap_or("").to_owned();
        created(a).cmp(&created(b))
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flattens_slurped_rest_pages() {
        let entries = flatten_slurped_pages(r#"[[{"id":1},{"id":2}],[{"id":3}],{"id":4},7]"#);
        let ids: Vec<i64> = entries.iter().filter_map(|e| e["id"].as_i64()).collect();
        assert_eq!(ids, vec![1, 2, 3, 4]);
        assert!(flatten_slurped_pages("not json").is_empty());
        assert!(flatten_slurped_pages(r#"{"id":1}"#).is_empty());
    }

    #[test]
    fn maps_issue_comments_as_conversation() {
        let entries = vec![json!({
            "id": 11,
            "user": {"login": "alice"},
            "body": "General note",
            "created_at": "2026-07-16T12:00:00Z",
            "html_url": "https://github.com/leynier/alera/pull/1#issuecomment-11",
        })];
        let comments = map_issue_comments(&entries);
        assert_eq!(comments.len(), 1);
        let comment = &comments[0];
        assert_eq!(comment["id"], 11);
        assert_eq!(comment["author"], "alice");
        assert_eq!(comment["body"], "General note");
        assert_eq!(comment["createdAt"], "2026-07-16T12:00:00Z");
        assert_eq!(comment["kind"], "conversation");
        assert_eq!(comment["source"], "conversation");
        assert!(comment.get("threadId").is_none());
    }

    #[test]
    fn keeps_only_review_summaries_with_a_body() {
        let entries = vec![
            json!({"id": 1, "user": {"login": "carol"}, "body": "LGTM with nits", "submitted_at": "2026-07-16T13:00:00Z"}),
            json!({"id": 2, "user": {"login": "dave"}, "body": "   ", "submitted_at": "2026-07-16T14:00:00Z"}),
            json!({"id": 3, "user": {"login": "erin"}, "submitted_at": "2026-07-16T15:00:00Z"}),
        ];
        let comments = map_review_summaries(&entries);
        assert_eq!(comments.len(), 1);
        assert_eq!(comments[0]["author"], "carol");
        assert_eq!(comments[0]["createdAt"], "2026-07-16T13:00:00Z");
        assert_eq!(comments[0]["source"], "reviewSummary");
        assert_eq!(comments[0]["kind"], "conversation");
    }

    #[test]
    fn maps_review_threads_with_location_and_resolution() {
        let connection = json!({
            "nodes": [
                {
                    "id": "T1",
                    "isResolved": true,
                    "line": null,
                    "originalLine": 17,
                    "comments": {"nodes": [
                        {"databaseId": 2, "author": {"login": "bob"}, "body": "Change this", "createdAt": "2026-07-16T11:00:00Z", "url": "https://github.com/x", "path": "lib/a.dart"},
                        {"databaseId": 3, "author": null, "body": "Done", "createdAt": "2026-07-16T11:30:00Z", "path": "lib/a.dart"}
                    ]}
                },
                {"id": "T2", "isResolved": false, "line": 4, "comments": {"nodes": [
                    {"databaseId": 4, "author": {"login": "alice"}, "body": "Open", "createdAt": "2026-07-16T10:00:00Z", "path": "b.rs"}
                ]}},
                {"id": "T3", "isResolved": false}
            ]
        });
        let comments = map_review_threads(&connection);
        assert_eq!(comments.len(), 3);
        assert_eq!(comments[0]["kind"], "review");
        assert_eq!(comments[0]["source"], "reviewThread");
        assert_eq!(comments[0]["path"], "lib/a.dart");
        assert_eq!(comments[0]["line"], 17);
        assert_eq!(comments[0]["resolved"], true);
        assert_eq!(comments[0]["threadId"], "T1");
        assert!(comments[1]["author"].is_null());
        assert_eq!(comments[1]["threadId"], "T1");
        assert_eq!(comments[2]["line"], 4);
        assert_eq!(comments[2]["resolved"], false);
        assert!(map_review_threads(&json!({})).is_empty());
    }

    #[test]
    fn reads_the_next_thread_cursor() {
        assert_eq!(
            next_cursor(&json!({"pageInfo": {"hasNextPage": true, "endCursor": "C1"}})),
            Some("C1".to_owned())
        );
        assert_eq!(
            next_cursor(&json!({"pageInfo": {"hasNextPage": false, "endCursor": "C1"}})),
            None
        );
        assert_eq!(next_cursor(&json!({})), None);
    }

    #[test]
    fn orders_every_source_by_creation_time() {
        let mut comments = vec![
            json!({"id": 1, "createdAt": "2026-07-16T12:00:00Z"}),
            json!({"id": 2, "createdAt": "2026-07-16T11:00:00Z"}),
            json!({"id": 3}),
            json!({"id": 4, "createdAt": "2026-07-16T12:00:00Z"}),
        ];
        sort_by_created_at(&mut comments);
        let ids: Vec<i64> = comments.iter().filter_map(|c| c["id"].as_i64()).collect();
        assert_eq!(ids, vec![3, 2, 1, 4]);
    }
}
