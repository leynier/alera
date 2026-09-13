use serde::{Deserialize, Serialize};
use url::Url;

use super::IssueFetchError;

/// Forges whose issues Alera can read. Wire values match the Dart
/// `GitHostingProvider` enum names.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueProvider {
    #[serde(rename = "github")]
    GitHub,
    #[serde(rename = "gitlab")]
    GitLab,
    #[serde(rename = "azureDevops")]
    AzureDevOps,
}

impl IssueProvider {
    pub fn wire_name(self) -> &'static str {
        match self {
            IssueProvider::GitHub => "github",
            IssueProvider::GitLab => "gitlab",
            IssueProvider::AzureDevOps => "azureDevops",
        }
    }
}

/// An issue URL and, when a provider recognized its shape, the coordinates
/// needed to fetch it. The URL stays the source of truth: an unrecognized one
/// keeps `provider`, `repository` and `number` empty and is still linkable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IssueReference {
    pub url: String,
    pub host: String,
    pub provider: Option<IssueProvider>,
    /// `owner/repo` on GitHub, `group/subgroup/project` on GitLab and
    /// `organization/project` on Azure DevOps.
    pub repository: Option<String>,
    pub number: Option<i64>,
}

impl IssueReference {
    /// The `--org` value `az boards` expects for an Azure DevOps reference.
    pub fn azure_organization_url(&self) -> Option<String> {
        if self.provider != Some(IssueProvider::AzureDevOps) {
            return None;
        }
        if self.host.ends_with(".visualstudio.com") {
            return Some(format!("https://{}", self.host));
        }
        let organization = self.repository.as_deref()?.split('/').next()?;
        Some(format!("https://{}/{organization}", self.host))
    }
}

/// Parses an issue URL. Only http(s) URLs are accepted; the recognized shapes
/// are GitHub `/owner/repo/issues/N`, GitLab `/group/project/-/issues/N` (or
/// `/-/work_items/N`, on any host) and Azure DevOps `/_workitems/edit/N`.
pub fn parse_issue_reference(raw: &str) -> Result<IssueReference, IssueFetchError> {
    let trimmed = raw.trim();
    let parsed = Url::parse(trimmed)
        .map_err(|_| IssueFetchError::InvalidUrl(format!("Not a valid issue URL: {trimmed}")))?;
    if parsed.scheme() != "https" && parsed.scheme() != "http" {
        return Err(IssueFetchError::InvalidUrl(format!(
            "Issue URLs must use http or https: {trimmed}"
        )));
    }
    let Some(host) = parsed.host_str().map(str::to_ascii_lowercase) else {
        return Err(IssueFetchError::InvalidUrl(format!(
            "Issue URL has no host: {trimmed}"
        )));
    };
    let host = match parsed.port() {
        Some(port) => format!("{host}:{port}"),
        None => host,
    };
    let segments: Vec<String> = parsed
        .path_segments()
        .map(|segments| {
            segments
                .filter(|segment| !segment.is_empty())
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default();
    let recognized = recognize(&host, &segments);
    Ok(IssueReference {
        url: trimmed.to_string(),
        host,
        provider: recognized.as_ref().map(|found| found.0),
        repository: recognized.as_ref().map(|found| found.1.clone()),
        number: recognized.map(|found| found.2),
    })
}

fn recognize(host: &str, segments: &[String]) -> Option<(IssueProvider, String, i64)> {
    gitlab_shape(segments)
        .map(|(repository, number)| (IssueProvider::GitLab, repository, number))
        .or_else(|| {
            azure_shape(host, segments)
                .map(|(repository, number)| (IssueProvider::AzureDevOps, repository, number))
        })
        .or_else(|| github_shape(host, segments))
}

fn gitlab_shape(segments: &[String]) -> Option<(String, i64)> {
    let marker = segments.iter().position(|segment| segment == "-")?;
    let kind = segments.get(marker + 1)?;
    if kind != "issues" && kind != "work_items" {
        return None;
    }
    let number = issue_number(segments.get(marker + 2)?)?;
    if marker < 2 {
        return None;
    }
    Some((segments[..marker].join("/"), number))
}

fn azure_shape(host: &str, segments: &[String]) -> Option<(String, i64)> {
    let marker = segments
        .iter()
        .position(|segment| segment == "_workitems")?;
    if segments.get(marker + 1).map(String::as_str) != Some("edit") {
        return None;
    }
    let number = issue_number(segments.get(marker + 2)?)?;
    let prefix = &segments[..marker];
    if host == "dev.azure.com" {
        if prefix.len() != 2 {
            return None;
        }
        return Some((format!("{}/{}", prefix[0], prefix[1]), number));
    }
    let organization = host.strip_suffix(".visualstudio.com")?;
    let project = match prefix {
        [project] => project,
        [_collection, project] => project,
        _ => return None,
    };
    Some((format!("{organization}/{project}"), number))
}

fn github_shape(host: &str, segments: &[String]) -> Option<(IssueProvider, String, i64)> {
    let [owner, repo, kind, number, ..] = segments else {
        return None;
    };
    if kind != "issues" {
        return None;
    }
    let number = issue_number(number)?;
    let repository = format!("{owner}/{repo}");
    match host {
        "github.com" | "www.github.com" => Some((IssueProvider::GitHub, repository, number)),
        // gitlab.com still redirects the legacy path without the `-` marker.
        "gitlab.com" => Some((IssueProvider::GitLab, repository, number)),
        _ => None,
    }
}

fn issue_number(segment: &str) -> Option<i64> {
    let number = segment.parse::<i64>().ok()?;
    (number > 0).then_some(number)
}

#[cfg(test)]
#[path = "issue_reference_tests.rs"]
mod tests;
