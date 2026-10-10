//! Which forge a remote URL belongs to and the coordinates its CLI needs.
//! Ported from the desktop's `git_remote_parser.dart` and
//! `hosting_provider_resolver.dart`: a project may force the provider, and the
//! coordinates still come from the remote URL.

use super::super::mobile_pull_request_identity::{parse_github_identity, GitHubIdentity};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ForgeKind {
    GitHub,
    GitLab,
    AzureDevOps,
}

impl ForgeKind {
    pub(crate) const ALL: [ForgeKind; 3] = [Self::GitHub, Self::GitLab, Self::AzureDevOps];

    /// The name `LinkedReview.provider`, snapshots, and the desktop use.
    pub(crate) fn wire(self) -> &'static str {
        match self {
            Self::GitHub => "github",
            Self::GitLab => "gitlab",
            Self::AzureDevOps => "azureDevops",
        }
    }

    pub(crate) fn from_wire(value: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|kind| kind.wire() == value)
    }

    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::GitHub => "GitHub",
            Self::GitLab => "GitLab",
            Self::AzureDevOps => "Azure DevOps",
        }
    }

    pub(crate) fn cli(self) -> &'static str {
        match self {
            Self::GitHub => "gh",
            Self::GitLab => "glab",
            Self::AzureDevOps => "az",
        }
    }

    /// The word each forge uses for a review.
    pub(crate) fn review_noun(self) -> &'static str {
        match self {
            Self::GitLab => "merge request",
            _ => "pull request",
        }
    }
}

/// Repository coordinates. GitLab's owner can hold nested groups; Azure DevOps
/// keeps the organization in `owner` and needs `project` too.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ForgeIdentity {
    pub(crate) kind: ForgeKind,
    pub(crate) host: String,
    pub(crate) owner: String,
    pub(crate) repo: String,
    pub(crate) project: Option<String>,
}

impl ForgeIdentity {
    /// The `gh` coordinates, keeping the runtime's existing GitHub parsing
    /// (which accepts `*.github.com` hosts) when the remote allows it.
    pub(crate) fn github(&self, remote_url: &str) -> GitHubIdentity {
        parse_github_identity(remote_url).unwrap_or_else(|| GitHubIdentity {
            host: self.host.clone(),
            owner: self.owner.clone(),
            repo: self.repo.clone(),
            slug: if self.host == "github.com" {
                format!("{}/{}", self.owner, self.repo)
            } else {
                format!("{}/{}/{}", self.host, self.owner, self.repo)
            },
        })
    }

    /// `https://dev.azure.com/{org}`, or the legacy `{org}.visualstudio.com`.
    pub(crate) fn azure_org_url(&self) -> String {
        if self.host.contains("visualstudio.com") {
            format!("https://{}.visualstudio.com", self.owner)
        } else {
            format!("https://dev.azure.com/{}", self.owner)
        }
    }
}

/// The forge of [url], forced to [forced] when the project overrides it.
pub(crate) fn resolve_identity(url: &str, forced: Option<ForgeKind>) -> Option<ForgeIdentity> {
    let parsed = parse_remote_url(url)?;
    match forced {
        Some(kind) => as_kind(&parsed, kind),
        None => detect(&parsed),
    }
}

fn detect(parsed: &ParsedRemote) -> Option<ForgeIdentity> {
    let host = parsed.hostname.as_str();
    if host == "github.com" || host.ends_with(".github.com") {
        return as_kind(parsed, ForgeKind::GitHub);
    }
    if host == "dev.azure.com"
        || host == "ssh.dev.azure.com"
        || host == "vs-ssh.visualstudio.com"
        || host.ends_with(".visualstudio.com")
    {
        return as_kind(parsed, ForgeKind::AzureDevOps);
    }
    // Self-hosted GitLab usually keeps the product name in its host; the
    // project setting covers the rest.
    if host == "gitlab.com" || host.contains("gitlab") {
        return as_kind(parsed, ForgeKind::GitLab);
    }
    None
}

fn as_kind(parsed: &ParsedRemote, kind: ForgeKind) -> Option<ForgeIdentity> {
    let segments = &parsed.segments;
    let identity = |owner: String, repo: String, project: Option<String>| ForgeIdentity {
        kind,
        host: parsed.host.clone(),
        owner,
        repo,
        project,
    };
    match kind {
        ForgeKind::GitHub if segments.len() >= 2 => {
            Some(identity(segments[0].clone(), segments[1].clone(), None))
        }
        ForgeKind::GitLab if segments.len() >= 2 => Some(identity(
            segments[..segments.len() - 1].join("/"),
            segments[segments.len() - 1].clone(),
            None,
        )),
        ForgeKind::AzureDevOps => {
            azure(parsed).map(|(org, project, repo)| identity(org, repo, Some(project)))
        }
        _ => None,
    }
}

/// `(org, project, repo)` from `[..]/org/project/_git/repo` (dev.azure.com),
/// `[..]/project/_git/repo` on `org.visualstudio.com`, or SSH
/// `v3/org/project/repo`.
fn azure(parsed: &ParsedRemote) -> Option<(String, String, String)> {
    let segments = &parsed.segments;
    if let Some(git) = segments.iter().position(|segment| segment == "_git") {
        if git >= 1 && git + 1 < segments.len() {
            let repo = segments[git + 1].clone();
            if let Some(org) = parsed.hostname.strip_suffix(".visualstudio.com") {
                return Some((org.to_string(), segments[git - 1].clone(), repo));
            }
            if git >= 2 {
                return Some((segments[git - 2].clone(), segments[git - 1].clone(), repo));
            }
            return None;
        }
    }
    let base = if segments.first().map(String::as_str) == Some("v3") {
        &segments[1..]
    } else {
        &segments[..]
    };
    (base.len() >= 3).then(|| (base[0].clone(), base[1].clone(), base[2].clone()))
}

struct ParsedRemote {
    /// Lowercased host, with the port only for http(s) remotes.
    host: String,
    hostname: String,
    segments: Vec<String>,
}

fn parse_remote_url(raw: &str) -> Option<ParsedRemote> {
    let url = raw.trim();
    if url.is_empty() {
        return None;
    }
    let (host, hostname, path) = if url.contains("://") {
        let parsed = url::Url::parse(url).ok()?;
        let hostname = parsed.host_str()?.to_ascii_lowercase();
        let keeps_port = matches!(parsed.scheme(), "http" | "https");
        let host = match parsed.port() {
            Some(port) if keeps_port => format!("{hostname}:{port}"),
            _ => hostname.clone(),
        };
        (host, hostname, parsed.path().to_string())
    } else {
        let (authority, path) = url.split_once(':')?;
        let authority = authority.rsplit('@').next().unwrap_or(authority);
        if authority.is_empty() {
            return None;
        }
        let host = authority.to_ascii_lowercase();
        (host.clone(), host, path.to_string())
    };
    let mut segments = path
        .split('/')
        .filter(|segment| !segment.is_empty())
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    let last = segments.last_mut()?;
    if let Some(stripped) = last.strip_suffix(".git") {
        *last = stripped.to_string();
    }
    if last.is_empty() {
        return None;
    }
    Some(ParsedRemote {
        host,
        hostname,
        segments,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(url: &str) -> ForgeIdentity {
        resolve_identity(url, None).unwrap()
    }

    #[test]
    fn detects_each_forge_like_the_desktop() {
        let github = parse("git@github.com:leynier/alera.git");
        assert_eq!(
            (github.kind, github.owner.as_str(), github.repo.as_str()),
            (ForgeKind::GitHub, "leynier", "alera")
        );
        let gitlab = parse("https://gitlab.acme.test:8443/platform/mobile/alera.git");
        assert_eq!(gitlab.kind, ForgeKind::GitLab);
        assert_eq!(gitlab.host, "gitlab.acme.test:8443");
        assert_eq!(gitlab.owner, "platform/mobile");
        assert_eq!(gitlab.repo, "alera");
        let azure = parse("https://myorg@dev.azure.com/myorg/myproject/_git/myrepo");
        assert_eq!(azure.kind, ForgeKind::AzureDevOps);
        assert_eq!(
            (
                azure.owner.as_str(),
                azure.project.as_deref(),
                azure.repo.as_str()
            ),
            ("myorg", Some("myproject"), "myrepo")
        );
        assert_eq!(azure.azure_org_url(), "https://dev.azure.com/myorg");
        let ssh = parse("git@ssh.dev.azure.com:v3/myorg/myproject/myrepo");
        assert_eq!(ssh.project.as_deref(), Some("myproject"));
        let legacy =
            parse("https://myorg.visualstudio.com/DefaultCollection/myproject/_git/myrepo");
        assert_eq!(legacy.owner, "myorg");
        assert_eq!(legacy.azure_org_url(), "https://myorg.visualstudio.com");
        assert!(resolve_identity("https://example.com/a/b.git", None).is_none());
    }

    #[test]
    fn a_project_override_forces_the_provider() {
        let forced =
            resolve_identity("git@code.acme.test:team/app.git", Some(ForgeKind::GitLab)).unwrap();
        assert_eq!(forced.kind, ForgeKind::GitLab);
        assert_eq!(forced.host, "code.acme.test");
        let enterprise =
            resolve_identity("https://ghe.acme.test/team/app", Some(ForgeKind::GitHub)).unwrap();
        let github = enterprise.github("https://ghe.acme.test/team/app");
        assert_eq!(github.slug, "ghe.acme.test/team/app");
        assert!(
            resolve_identity("https://ghe.acme.test/app", Some(ForgeKind::AzureDevOps)).is_none()
        );
    }

    #[test]
    fn wire_names_round_trip() {
        for kind in ForgeKind::ALL {
            assert_eq!(ForgeKind::from_wire(kind.wire()), Some(kind));
        }
        assert_eq!(ForgeKind::from_wire("bitbucket"), None);
    }
}
