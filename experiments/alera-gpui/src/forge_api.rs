use std::thread;

use async_channel::{Receiver, Sender};

const COMMAND_CAPACITY: usize = 16;

#[derive(Clone)]
pub struct ForgeService {
    commands: Sender<Command>,
}

enum Command {
    Snapshot {
        workspace_path: String,
        identity: ForgeIdentity,
        review_number: Option<u64>,
        review_dismissed: bool,
        reply: Sender<Result<ForgeSnapshot, String>>,
    },
    Action {
        workspace_path: String,
        identity: ForgeIdentity,
        action: ForgeAction,
        reply: Sender<Result<String, String>>,
    },
    StackAction {
        workspace_path: String,
        identity: ForgeIdentity,
        action: ForgeStackAction,
        reply: Sender<Result<String, String>>,
    },
    Close,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ForgeAuthStatus {
    #[default]
    Unknown,
    Authenticated,
    CliMissing,
    NotAuthenticated,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ForgeUnavailableReason {
    NoRemote,
    ProviderNotDetected,
    UnsupportedProvider,
}

#[derive(Clone, Debug, Default)]
pub struct ForgeSnapshot {
    pub provider: String,
    pub host: String,
    pub repo_slug: String,
    pub branch: String,
    pub auth_status: ForgeAuthStatus,
    pub unavailable_reason: Option<ForgeUnavailableReason>,
    pub base_branches: Vec<String>,
    pub suggested_base_branch: String,
    pub review: Option<ForgeReview>,
    pub suggested_review: Option<ForgeReview>,
    pub checks: Vec<ForgeCheck>,
    pub comments: Vec<ForgeComment>,
    pub stack: Option<ForgeStack>,
    pub stack_error: Option<String>,
}

#[derive(Clone, Debug)]
pub struct ForgeIdentity {
    pub host: String,
    pub repo_slug: String,
    pub branch: String,
    pub base_branches: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct ForgeReview {
    pub number: u64,
    pub title: String,
    pub body: String,
    pub state: String,
    pub url: String,
    pub draft: bool,
    pub mergeable: String,
    pub head_branch: String,
    pub base_branch: String,
    pub author: String,
}

#[derive(Clone, Debug)]
pub struct ForgeStack {
    pub number: u64,
    pub base_branch: String,
    pub open: bool,
    pub entries: Vec<ForgeStackEntry>,
}

#[derive(Clone, Debug)]
pub struct ForgeStackEntry {
    pub review: ForgeReview,
    pub position: usize,
}

#[derive(Clone, Debug)]
pub struct ForgeCheck {
    pub name: String,
    pub _state: String,
    pub bucket: String,
    pub link: Option<String>,
    pub description: Option<String>,
    pub workflow: Option<String>,
    pub event: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
}

#[derive(Clone, Debug)]
pub struct ForgeComment {
    pub _id: String,
    pub author: String,
    pub body: String,
    pub url: Option<String>,
    pub created_at: Option<String>,
    pub path: Option<String>,
    pub line: Option<u64>,
    pub resolved: bool,
    pub source: ForgeCommentSource,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ForgeCommentSource {
    #[default]
    Conversation,
    ReviewSummary,
    ReviewThread,
}

#[derive(Clone, Debug)]
pub enum ForgeAction {
    Create {
        title: String,
        body: String,
        base: String,
        draft: bool,
    },
    Update {
        number: u64,
        title: String,
        body: String,
        base: String,
    },
    Merge {
        number: u64,
        method: MergeMethod,
    },
    Close {
        number: u64,
    },
    SetDraft {
        number: u64,
        draft: bool,
    },
    Comment {
        number: u64,
        body: String,
    },
    UpdateComment {
        number: u64,
        comment_id: String,
        source: ForgeCommentSource,
        body: String,
    },
}

#[derive(Clone, Debug)]
pub enum ForgeStackAction {
    Link {
        review_numbers: Vec<u64>,
        stack_number: Option<u64>,
        base: Option<String>,
    },
    LinkBranches {
        branches: Vec<String>,
        stack_number: Option<u64>,
        base: Option<String>,
    },
    Merge {
        review_number: u64,
        method: MergeMethod,
    },
}

#[derive(Clone, Copy, Debug)]
pub enum MergeMethod {
    Merge,
    Squash,
    Rebase,
}

impl ForgeService {
    pub fn start() -> Self {
        let (commands, receiver) = async_channel::bounded(COMMAND_CAPACITY);
        thread::Builder::new()
            .name("alera-desktop-forge".to_string())
            .spawn(move || run(receiver))
            .expect("failed to start the GPUI forge service");
        Self { commands }
    }

    pub async fn snapshot(
        &self,
        workspace_path: String,
        identity: ForgeIdentity,
        review_number: Option<u64>,
        review_dismissed: bool,
    ) -> Result<ForgeSnapshot, String> {
        request(&self.commands, |reply| Command::Snapshot {
            workspace_path,
            identity,
            review_number,
            review_dismissed,
            reply,
        })
        .await
    }

    pub async fn action(
        &self,
        workspace_path: String,
        identity: ForgeIdentity,
        action: ForgeAction,
    ) -> Result<String, String> {
        request(&self.commands, |reply| Command::Action {
            workspace_path,
            identity,
            action,
            reply,
        })
        .await
    }

    pub async fn stack_action(
        &self,
        workspace_path: String,
        identity: ForgeIdentity,
        action: ForgeStackAction,
    ) -> Result<String, String> {
        request(&self.commands, |reply| Command::StackAction {
            workspace_path,
            identity,
            action,
            reply,
        })
        .await
    }
}

impl Drop for ForgeService {
    fn drop(&mut self) {
        if self.commands.sender_count() == 1 {
            let _ = self.commands.try_send(Command::Close);
        }
    }
}

async fn request<T: Send + 'static>(
    commands: &Sender<Command>,
    build: impl FnOnce(Sender<Result<T, String>>) -> Command,
) -> Result<T, String> {
    let (reply, response) = async_channel::bounded(1);
    commands
        .send(build(reply))
        .await
        .map_err(|_| "Forge service is closed.".to_string())?;
    response
        .recv()
        .await
        .map_err(|_| "Forge service closed before replying.".to_string())?
}

fn run(commands: Receiver<Command>) {
    while let Ok(command) = commands.recv_blocking() {
        match command {
            Command::Snapshot {
                workspace_path,
                identity,
                review_number,
                review_dismissed,
                reply,
            } => {
                let _ = reply.send_blocking(crate::forge_service::load_snapshot(
                    workspace_path,
                    identity,
                    review_number,
                    review_dismissed,
                ));
            }
            Command::Action {
                workspace_path,
                identity,
                action,
                reply,
            } => {
                let _ = reply.send_blocking(crate::forge_service::run_action(
                    workspace_path,
                    identity,
                    action,
                ));
            }
            Command::StackAction {
                workspace_path,
                identity,
                action,
                reply,
            } => {
                let _ = reply.send_blocking(crate::forge_service::run_stack_action(
                    workspace_path,
                    identity,
                    action,
                ));
            }
            Command::Close => return,
        }
    }
}
