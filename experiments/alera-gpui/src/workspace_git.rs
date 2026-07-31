use alera_native::api::git;

#[derive(Clone, Debug, Default)]
pub struct GitSnapshot {
    pub branch: String,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
    pub has_conflicts: bool,
    pub changes: Vec<GitChange>,
    pub patch: Vec<String>,
    pub history: Vec<GitHistoryItem>,
    pub stashes: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct GitChange {
    pub path: String,
    pub area: String,
    pub status: String,
    pub added: Option<u32>,
    pub removed: Option<u32>,
}

#[derive(Clone, Debug)]
pub struct GitHistoryItem {
    pub id: String,
    pub subject: String,
    pub author: Option<String>,
}

#[derive(Clone, Debug)]
pub enum GitAction {
    StageAll,
    StagePath(String),
    UnstageAll,
    UnstagePath(String),
    DiscardAll,
    DiscardPath(String),
    Commit(String),
    Amend(String),
    Fetch,
    Pull,
    Push,
    Stash,
    StashPop(u32),
}

pub(crate) fn git_snapshot(workspace_path: String) -> Result<GitSnapshot, String> {
    let state = git::git_repository_state(workspace_path.clone()).map_err(|error| error.context)?;
    let status = git::git_status(workspace_path.clone()).map_err(|error| error.context)?;
    let diff = git::git_diff_all(workspace_path.clone(), None).map_err(|error| error.context)?;
    let history =
        git::git_history(workspace_path.clone(), Some(50), None).map_err(|error| error.context)?;
    let stashes = git::git_list_stashes(workspace_path).map_err(|error| error.context)?;
    Ok(GitSnapshot {
        branch: state.branch,
        upstream: state.upstream,
        ahead: state.ahead,
        behind: state.behind,
        has_conflicts: state.has_conflicts,
        changes: status
            .entries
            .into_iter()
            .map(|entry| GitChange {
                path: entry.path,
                area: format!("{:?}", entry.area),
                status: format!("{:?}", entry.status),
                added: entry.added,
                removed: entry.removed,
            })
            .collect(),
        patch: diff
            .files
            .into_iter()
            .flat_map(|file| {
                let path = file.path;
                file.lines
                    .into_iter()
                    .map(move |line| format!("{path}: {}", line.text))
            })
            .take(2_000)
            .collect(),
        history: history
            .items
            .into_iter()
            .map(|item| GitHistoryItem {
                id: item.display_id.unwrap_or(item.id),
                subject: item.subject,
                author: item.author,
            })
            .collect(),
        stashes: stashes
            .into_iter()
            .map(|item| format!("{} {}", item.reference, item.message))
            .collect(),
    })
}

pub(crate) fn git_action(workspace_path: String, action: GitAction) -> Result<String, String> {
    let result = match action {
        GitAction::StageAll => git::git_stage(workspace_path, None).map(|_| "Staged".to_string()),
        GitAction::StagePath(path) => {
            git::git_stage(workspace_path, Some(path)).map(|_| "Staged File".to_string())
        }
        GitAction::UnstageAll => {
            git::git_unstage(workspace_path, None).map(|_| "Unstaged".to_string())
        }
        GitAction::UnstagePath(path) => {
            git::git_unstage(workspace_path, Some(path)).map(|_| "Unstaged File".to_string())
        }
        GitAction::DiscardAll => {
            git::git_discard(workspace_path, None).map(|_| "Discarded".to_string())
        }
        GitAction::DiscardPath(path) => {
            git::git_discard(workspace_path, Some(path)).map(|_| "Discarded File".to_string())
        }
        GitAction::Commit(message) => git::git_commit(workspace_path, message),
        GitAction::Amend(message) => git::git_commit_amend(workspace_path, message),
        GitAction::Fetch => git::git_fetch(workspace_path).map(|_| "Fetched".to_string()),
        GitAction::Pull => git::git_pull(workspace_path).map(|_| "Pulled".to_string()),
        GitAction::Push => git::git_push(workspace_path).map(|_| "Pushed".to_string()),
        GitAction::Stash => git::git_stash(workspace_path).map(|_| "Stashed".to_string()),
        GitAction::StashPop(index) => {
            git::git_stash_pop(workspace_path, index).map(|_| "Applied Stash".to_string())
        }
    };
    result.map_err(|error| error.context)
}
