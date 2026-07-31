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
        reply: Sender<Result<ForgeSnapshot, String>>,
    },
    Action {
        workspace_path: String,
        action: ForgeAction,
        reply: Sender<Result<String, String>>,
    },
    Close,
}

#[derive(Clone, Debug, Default)]
pub struct ForgeSnapshot {
    pub provider: String,
    pub host: String,
    pub repo_slug: String,
    pub branch: String,
    pub authenticated: bool,
    pub review: Option<ForgeReview>,
    pub checks: Vec<ForgeCheck>,
    pub comments: Vec<ForgeComment>,
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
pub struct ForgeCheck {
    pub name: String,
    pub state: String,
    pub bucket: String,
    pub link: Option<String>,
    pub description: Option<String>,
    pub workflow: Option<String>,
}

#[derive(Clone, Debug)]
pub struct ForgeComment {
    pub author: String,
    pub body: String,
    pub url: Option<String>,
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
            .name("alera-gpui-forge".to_string())
            .spawn(move || run(receiver))
            .expect("failed to start the GPUI forge service");
        Self { commands }
    }

    pub async fn snapshot(&self, workspace_path: String) -> Result<ForgeSnapshot, String> {
        request(&self.commands, |reply| Command::Snapshot {
            workspace_path,
            reply,
        })
        .await
    }

    pub async fn action(
        &self,
        workspace_path: String,
        action: ForgeAction,
    ) -> Result<String, String> {
        request(&self.commands, |reply| Command::Action {
            workspace_path,
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
                reply,
            } => {
                let _ = reply.send_blocking(crate::forge_service::load_snapshot(workspace_path));
            }
            Command::Action {
                workspace_path,
                action,
                reply,
            } => {
                let _ =
                    reply.send_blocking(crate::forge_service::run_action(workspace_path, action));
            }
            Command::Close => return,
        }
    }
}
