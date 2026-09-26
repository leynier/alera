//! Configured remotes with their fetch URLs, used to detect the git hosting
//! provider from the remote identity.

use serde::{Deserialize, Serialize};

use super::{open_repo, GitError};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitRemote {
    pub name: String,
    /// The fetch URL, or `None` when the remote has no URL configured.
    pub url: Option<String>,
}

pub fn list_remotes(path: &str) -> Result<Vec<GitRemote>, GitError> {
    let repo = open_repo(path)?;
    let names = repo.remotes().map_err(GitError::from_git2)?;
    let mut remotes = Vec::new();
    for name in names.iter() {
        let Some(name) = name.map_err(GitError::from_git2)? else {
            continue;
        };
        let url = match repo.find_remote(name) {
            Ok(remote) => remote.url().ok().map(ToString::to_string),
            Err(_) => None,
        };
        remotes.push(GitRemote {
            name: name.to_string(),
            url,
        });
    }
    Ok(remotes)
}
