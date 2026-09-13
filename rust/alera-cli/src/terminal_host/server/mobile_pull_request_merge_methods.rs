//! The merge methods a phone may offer for one pull request: repository
//! settings intersected with the rules active on the base branch. Ported from
//! the desktop's `github_merge_methods.dart` and `allowedMergeMethods`, so both
//! surfaces offer the same list and a malformed payload fails closed on both.

use std::collections::BTreeSet;

use serde_json::Value;

use super::mobile_pull_request_identity::GitHubIdentity;
use super::mobile_pull_request_requests::run_gh;

const INVALID_PAYLOAD: &str = "GitHub returned an invalid merge-method payload.";

/// Wire names, in the order the desktop lists them.
const ORDER: [&str; 3] = ["mergeCommit", "squash", "rebase"];

pub(super) async fn allowed_merge_methods(
    repo_path: &str,
    identity: &GitHubIdentity,
    base_branch: Option<&str>,
) -> Result<Vec<&'static str>, String> {
    let repo_output = gh_json(
        repo_path,
        &[
            "repo",
            "view",
            &identity.slug,
            "--json",
            "mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed",
        ],
    )
    .await?;
    let repo_allowed = map_repo_allowed(&repo_output)
        .ok_or_else(|| "GitHub did not return the repository merge methods.".to_string())?;
    let Some(base_branch) = base_branch.filter(|branch| !branch.trim().is_empty()) else {
        return Ok(repo_allowed);
    };
    let endpoint = format!(
        "repos/{}/{}/rules/branches/{}",
        identity.owner,
        identity.repo,
        encode_path_segment(base_branch)
    );
    let rules = gh_json(
        repo_path,
        &[
            "api",
            "--hostname",
            &identity.host,
            "--paginate",
            "--slurp",
            &endpoint,
        ],
    )
    .await?;
    let Some(rule_allowed) = map_ruleset_allowed(&rules)? else {
        return Ok(repo_allowed);
    };
    Ok(repo_allowed
        .into_iter()
        .filter(|method| rule_allowed.contains(method))
        .collect())
}

async fn gh_json(repo_path: &str, args: &[&str]) -> Result<Value, String> {
    let (code, stdout, stderr) = run_gh(repo_path, args)
        .await
        .map_err(|error| error.wire_message())?;
    if code != 0 {
        let detail = stderr.trim();
        return Err(if detail.is_empty() {
            "The GitHub CLI failed.".to_string()
        } else {
            detail.to_string()
        });
    }
    serde_json::from_str(&stdout).map_err(|_| INVALID_PAYLOAD.to_string())
}

/// `None` when the payload does not describe merge permissions, so the caller
/// fails closed instead of advertising every method.
fn map_repo_allowed(value: &Value) -> Option<Vec<&'static str>> {
    let flag = |key: &str| value.get(key).and_then(Value::as_bool);
    let flags = [
        flag("mergeCommitAllowed")?,
        flag("squashMergeAllowed")?,
        flag("rebaseMergeAllowed")?,
    ];
    Some(
        ORDER
            .iter()
            .zip(flags)
            .filter_map(|(method, allowed)| allowed.then_some(*method))
            .collect(),
    )
}

/// `Ok(None)` when no rule constrains the methods. Rules intersect, a
/// `pull_request` rule without a list is unconstrained, and
/// `required_linear_history` forbids merge commits.
fn map_ruleset_allowed(decoded: &Value) -> Result<Option<BTreeSet<&'static str>>, String> {
    let mut entries = Vec::new();
    collect_rules(decoded, &mut entries)?;
    let mut allowed: Option<BTreeSet<&'static str>> = None;
    for rule in entries {
        let Some(methods) = rule_methods(rule)? else {
            continue;
        };
        allowed = Some(match allowed {
            None => methods,
            Some(current) => current.intersection(&methods).copied().collect(),
        });
    }
    Ok(allowed)
}

fn collect_rules<'a>(value: &'a Value, entries: &mut Vec<&'a Value>) -> Result<(), String> {
    match value {
        Value::Object(_) => entries.push(value),
        Value::Array(items) => {
            for item in items {
                collect_rules(item, entries)?;
            }
        }
        _ => return Err(INVALID_PAYLOAD.to_string()),
    }
    Ok(())
}

fn rule_methods(rule: &Value) -> Result<Option<BTreeSet<&'static str>>, String> {
    let rule_type = rule
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_lowercase();
    let parameters = rule.get("parameters").filter(|value| !value.is_null());
    if parameters.is_some_and(|value| !value.is_object()) {
        return Err(INVALID_PAYLOAD.to_string());
    }
    if rule_type == "required_linear_history" {
        return Ok(Some(BTreeSet::from(["squash", "rebase"])));
    }
    if rule_type == "pull_request" || rule_type == "merge_method" {
        return parse_methods(
            parameters.and_then(|value| value.get("allowed_merge_methods")),
            rule_type == "merge_method",
        );
    }
    parse_methods(rule.get("allowed_merge_methods"), false)
}

fn parse_methods(
    raw: Option<&Value>,
    required: bool,
) -> Result<Option<BTreeSet<&'static str>>, String> {
    let Some(raw) = raw.filter(|value| !value.is_null()) else {
        return if required {
            Err(INVALID_PAYLOAD.to_string())
        } else {
            Ok(None)
        };
    };
    let items = raw.as_array().ok_or_else(|| INVALID_PAYLOAD.to_string())?;
    let mut methods = BTreeSet::new();
    for item in items {
        let token = item.as_str().ok_or_else(|| INVALID_PAYLOAD.to_string())?;
        match token.trim().to_lowercase().as_str() {
            "merge" | "merge_commit" | "mergecommit" => methods.insert("mergeCommit"),
            "squash" => methods.insert("squash"),
            "rebase" => methods.insert("rebase"),
            _ => false,
        };
    }
    Ok(Some(methods))
}

/// Same output as Dart's `Uri.encodeComponent` for a branch name.
fn encode_path_segment(value: &str) -> String {
    value
        .bytes()
        .map(|byte| match byte {
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'-'
            | b'_'
            | b'.'
            | b'!'
            | b'~'
            | b'*'
            | b'\''
            | b'('
            | b')' => (byte as char).to_string(),
            _ => format!("%{byte:02X}"),
        })
        .collect()
}

#[cfg(test)]
#[path = "mobile_pull_request_merge_methods_tests.rs"]
mod tests;
