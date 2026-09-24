//! Which forge a workspace remote points at, and the GitHub coordinates `gh`
//! needs to address it. Shared by the mobile pull request snapshot and its
//! write verbs so both resolve the same repository.

use serde_json::{json, Value};

pub(super) struct GitHubIdentity {
    pub(super) host: String,
    pub(super) owner: String,
    pub(super) repo: String,
    pub(super) slug: String,
}

pub(super) fn parse_github_identity(url: &str) -> Option<GitHubIdentity> {
    let parsed = parse_remote_url(url)?;
    if parsed.hostname != "github.com" && !parsed.hostname.ends_with(".github.com") {
        return None;
    }
    if parsed.segments.len() < 2 {
        return None;
    }
    let owner = parsed.segments[0].clone();
    let repo = parsed.segments[1].clone();
    let slug = if parsed.hostname == "github.com" {
        format!("{owner}/{repo}")
    } else {
        format!("{}/{owner}/{repo}", parsed.host)
    };
    Some(GitHubIdentity {
        host: parsed.host,
        owner,
        repo,
        slug,
    })
}

pub(super) fn detect_provider(url: Option<&str>) -> Option<&'static str> {
    let url = url?;
    let parsed = parse_remote_url(url)?;
    if parsed.hostname == "gitlab.com" || parsed.hostname.contains("gitlab") {
        return Some("gitlab");
    }
    if parsed.hostname == "dev.azure.com"
        || parsed.hostname.ends_with(".visualstudio.com")
        || parsed.hostname.contains("azure")
    {
        return Some("azureDevops");
    }
    None
}

pub(super) fn remote_identity_json(url: Option<&str>, provider: Option<&str>) -> Value {
    let parsed = url.and_then(parse_remote_url);
    json!({
        "provider": provider,
        "host": parsed.as_ref().map(|parsed| parsed.host.clone()),
        "owner": parsed.as_ref().and_then(|parsed| parsed.segments.first()).cloned(),
        "repo": parsed.as_ref().and_then(|parsed| parsed.segments.last()).cloned(),
    })
}

struct ParsedRemote {
    host: String,
    hostname: String,
    segments: Vec<String>,
}

fn parse_remote_url(raw: &str) -> Option<ParsedRemote> {
    let url = raw.trim();
    if url.is_empty() {
        return None;
    }
    let (host, path) = if let Some(scheme_end) = url.find("://") {
        let rest = &url[scheme_end + 3..];
        let rest = rest.split_once('@').map_or(rest, |(_, rest)| rest);
        let (host, path) = rest.split_once('/')?;
        (host.to_string(), path.to_string())
    } else {
        let rest = url.split_once('@').map_or(url, |(_, rest)| rest);
        let (host, path) = rest.split_once(':')?;
        (host.to_string(), path.to_string())
    };
    let hostname = host
        .split(':')
        .next()
        .unwrap_or(&host)
        .trim()
        .to_ascii_lowercase();
    let segments = path
        .trim_start_matches('/')
        .trim_end_matches(".git")
        .split('/')
        .filter(|segment| !segment.is_empty())
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    if hostname.is_empty() || segments.is_empty() {
        return None;
    }
    Some(ParsedRemote {
        host: host.to_string(),
        hostname,
        segments,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_github_https_and_ssh_remotes() {
        let https = parse_github_identity("https://github.com/leynier/alera.git").unwrap();
        assert_eq!(https.slug, "leynier/alera");
        let ssh = parse_github_identity("git@github.com:leynier/alera.git").unwrap();
        assert_eq!(ssh.owner, "leynier");
        assert_eq!(ssh.repo, "alera");
        assert!(parse_github_identity("https://gitlab.com/group/project.git").is_none());
        assert_eq!(
            detect_provider(Some("https://gitlab.com/group/project.git")),
            Some("gitlab")
        );
    }

    #[test]
    fn identity_json_includes_owner_and_repo() {
        let value =
            remote_identity_json(Some("https://github.com/leynier/alera.git"), Some("github"));
        assert_eq!(value["provider"], "github");
        assert_eq!(value["owner"], "leynier");
        assert_eq!(value["repo"], "alera");
    }
}
