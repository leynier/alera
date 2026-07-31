use alera_native::api::{git, process};
use serde_json::Value;

pub use crate::forge_api::{
    ForgeAction, ForgeCheck, ForgeComment, ForgeReview, ForgeService, ForgeSnapshot, MergeMethod,
};

const REVIEW_FIELDS: &str =
    "number,title,body,state,url,isDraft,mergeable,headRefName,baseRefName,author";
const CHECK_FIELDS: &str = "name,state,bucket,link,description,workflow,startedAt,completedAt";

#[derive(Clone, Debug)]
struct GitHubIdentity {
    host: String,
    repo_slug: String,
    branch: String,
}

pub(crate) fn load_snapshot(workspace_path: String) -> Result<ForgeSnapshot, String> {
    let identity = github_identity(&workspace_path)?;
    let authenticated = gh_authenticated(&workspace_path, &identity.host);
    if !authenticated {
        return Ok(ForgeSnapshot {
            provider: "GitHub".to_string(),
            host: identity.host,
            repo_slug: identity.repo_slug,
            branch: identity.branch,
            authenticated: false,
            review: None,
            checks: Vec::new(),
            comments: Vec::new(),
        });
    }
    let reviews = run_gh_json(
        &workspace_path,
        vec![
            "pr".into(),
            "list".into(),
            "--repo".into(),
            identity.repo_slug.clone(),
            "--head".into(),
            identity.branch.clone(),
            "--state".into(),
            "open".into(),
            "--limit".into(),
            "1".into(),
            "--json".into(),
            REVIEW_FIELDS.into(),
        ],
        false,
    )?;
    let review = reviews
        .as_array()
        .and_then(|items| items.first())
        .map(parse_review)
        .transpose()?;
    let (checks, comments) = if let Some(review) = &review {
        (
            load_checks(&workspace_path, &identity.repo_slug, review.number)?,
            load_comments(&workspace_path, &identity.repo_slug, review.number)?,
        )
    } else {
        (Vec::new(), Vec::new())
    };
    Ok(ForgeSnapshot {
        provider: "GitHub".to_string(),
        host: identity.host,
        repo_slug: identity.repo_slug,
        branch: identity.branch,
        authenticated,
        review,
        checks,
        comments,
    })
}

fn load_checks(
    workspace_path: &str,
    repo_slug: &str,
    number: u64,
) -> Result<Vec<ForgeCheck>, String> {
    let output = run_gh(
        workspace_path,
        vec![
            "pr".into(),
            "checks".into(),
            number.to_string(),
            "--repo".into(),
            repo_slug.into(),
            "--json".into(),
            CHECK_FIELDS.into(),
        ],
        true,
    )?;
    if output.trim().is_empty() {
        return Ok(Vec::new());
    }
    let value: Value = serde_json::from_str(&output)
        .map_err(|error| format!("Unexpected gh checks output: {error}"))?;
    Ok(value
        .as_array()
        .into_iter()
        .flatten()
        .map(|item| ForgeCheck {
            name: string(item, "name"),
            state: string(item, "state"),
            bucket: string(item, "bucket"),
            link: optional_string(item, "link"),
            description: optional_string(item, "description"),
            workflow: optional_string(item, "workflow"),
        })
        .collect())
}

fn load_comments(
    workspace_path: &str,
    repo_slug: &str,
    number: u64,
) -> Result<Vec<ForgeComment>, String> {
    let value = run_gh_json(
        workspace_path,
        vec![
            "pr".into(),
            "view".into(),
            number.to_string(),
            "--repo".into(),
            repo_slug.into(),
            "--json".into(),
            "comments,reviews".into(),
        ],
        false,
    )?;
    let mut comments = Vec::new();
    for key in ["comments", "reviews"] {
        for item in value
            .get(key)
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let body = string(item, "body");
            if body.trim().is_empty() {
                continue;
            }
            comments.push(ForgeComment {
                author: item
                    .get("author")
                    .and_then(|author| author.get("login"))
                    .and_then(Value::as_str)
                    .unwrap_or("Unknown")
                    .to_string(),
                body,
                url: optional_string(item, "url"),
            });
        }
    }
    Ok(comments)
}

pub(crate) fn run_action(workspace_path: String, action: ForgeAction) -> Result<String, String> {
    let identity = github_identity(&workspace_path)?;
    let mut arguments = vec!["pr".to_string()];
    let success = match action {
        ForgeAction::Create {
            title,
            body,
            base,
            draft,
        } => {
            arguments.extend([
                "create".into(),
                "--repo".into(),
                identity.repo_slug,
                "--base".into(),
                base,
                "--head".into(),
                identity.branch,
                "--title".into(),
                title,
                "--body".into(),
                body,
            ]);
            if draft {
                arguments.push("--draft".into());
            }
            "Pull Request Created"
        }
        ForgeAction::Update {
            number,
            title,
            body,
            base,
        } => {
            arguments.extend([
                "edit".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
                "--title".into(),
                title,
                "--body".into(),
                body,
                "--base".into(),
                base,
            ]);
            "Pull Request Updated"
        }
        ForgeAction::Merge { number, method } => {
            arguments.extend([
                "merge".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
                match method {
                    MergeMethod::Merge => "--merge",
                    MergeMethod::Squash => "--squash",
                    MergeMethod::Rebase => "--rebase",
                }
                .into(),
            ]);
            "Pull Request Merged"
        }
        ForgeAction::Close { number } => {
            arguments.extend([
                "close".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
            ]);
            "Pull Request Closed"
        }
        ForgeAction::SetDraft { number, draft } => {
            arguments.extend([
                "ready".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
            ]);
            if draft {
                arguments.push("--undo".into());
            }
            if draft {
                "Pull Request Converted To Draft"
            } else {
                "Pull Request Marked Ready"
            }
        }
        ForgeAction::Comment { number, body } => {
            arguments.extend([
                "comment".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
                "--body".into(),
                body,
            ]);
            "Comment Added"
        }
    };
    run_gh(&workspace_path, arguments, false)?;
    Ok(success.to_string())
}

fn github_identity(workspace_path: &str) -> Result<GitHubIdentity, String> {
    let branch = git::current_branch(workspace_path.to_string()).map_err(|error| error.context)?;
    let remotes = git::list_remotes(workspace_path.to_string()).map_err(|error| error.context)?;
    let remote = remotes
        .iter()
        .find(|remote| remote.name == "origin" && remote.url.is_some())
        .or_else(|| remotes.iter().find(|remote| remote.url.is_some()))
        .and_then(|remote| remote.url.clone())
        .ok_or_else(|| "Repository has no readable Git remote.".to_string())?;
    let (host, path) = split_remote(&remote)?;
    if host != "github.com" {
        return Err(format!(
            "The interactive POC currently implements GitHub remotes, not {host}."
        ));
    }
    let segments = path
        .trim_matches('/')
        .trim_end_matches(".git")
        .split('/')
        .collect::<Vec<_>>();
    if segments.len() < 2 {
        return Err("GitHub remote omitted owner or repository.".to_string());
    }
    Ok(GitHubIdentity {
        host,
        repo_slug: format!("{}/{}", segments[0], segments[1]),
        branch,
    })
}

fn split_remote(remote: &str) -> Result<(String, String), String> {
    if let Some((_, remainder)) = remote.split_once("://") {
        let remainder = remainder
            .rsplit_once('@')
            .map(|(_, value)| value)
            .unwrap_or(remainder);
        let (host, path) = remainder
            .split_once('/')
            .ok_or_else(|| "Git remote URL omitted its path.".to_string())?;
        return Ok((host.to_ascii_lowercase(), path.to_string()));
    }
    let without_user = remote
        .rsplit_once('@')
        .map(|(_, value)| value)
        .unwrap_or(remote);
    let (host, path) = without_user
        .split_once(':')
        .ok_or_else(|| "Git remote URL is not recognized.".to_string())?;
    Ok((host.to_ascii_lowercase(), path.to_string()))
}

fn run_gh_json(
    workspace_path: &str,
    arguments: Vec<String>,
    allow_nonzero: bool,
) -> Result<Value, String> {
    let output = run_gh(workspace_path, arguments, allow_nonzero)?;
    serde_json::from_str(output.trim()).map_err(|error| format!("Unexpected gh JSON: {error}"))
}

fn run_gh(
    workspace_path: &str,
    arguments: Vec<String>,
    allow_nonzero: bool,
) -> Result<String, String> {
    let result = process::process_run(
        "gh".to_string(),
        arguments,
        Some(workspace_path.to_string()),
        None,
    )
    .map_err(|error| format!("Failed to run gh: {error}"))?;
    if result.exit_code != 0 && !allow_nonzero {
        return Err(if result.stderr.trim().is_empty() {
            format!("gh exited with code {}.", result.exit_code)
        } else {
            result.stderr.trim().to_string()
        });
    }
    Ok(result.stdout)
}

fn gh_authenticated(workspace_path: &str, host: &str) -> bool {
    process::process_run(
        "gh".to_string(),
        vec![
            "auth".into(),
            "status".into(),
            "--hostname".into(),
            host.to_string(),
        ],
        Some(workspace_path.to_string()),
        None,
    )
    .map(|result| result.exit_code == 0)
    .unwrap_or(false)
}

fn parse_review(value: &Value) -> Result<ForgeReview, String> {
    Ok(ForgeReview {
        number: value
            .get("number")
            .and_then(Value::as_u64)
            .ok_or_else(|| "gh review omitted number.".to_string())?,
        title: string(value, "title"),
        body: string(value, "body"),
        state: string(value, "state"),
        url: string(value, "url"),
        draft: value
            .get("isDraft")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        mergeable: string(value, "mergeable"),
        head_branch: string(value, "headRefName"),
        base_branch: string(value, "baseRefName"),
        author: value
            .get("author")
            .and_then(|author| author.get("login"))
            .and_then(Value::as_str)
            .unwrap_or("Unknown")
            .to_string(),
    })
}

fn string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn optional_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::split_remote;

    #[test]
    fn parses_https_and_scp_github_remotes() {
        assert_eq!(
            split_remote("https://github.com/zed-industries/zed.git").unwrap(),
            (
                "github.com".to_string(),
                "zed-industries/zed.git".to_string()
            )
        );
        assert_eq!(
            split_remote("git@github.com:leynier/alera.git").unwrap(),
            ("github.com".to_string(), "leynier/alera.git".to_string())
        );
    }
}
