use std::path::PathBuf;
use std::thread;

use alera_native::api::merman_viewer;
use alera_native::api::workspace_files::{self, WorkspaceFileKind};
use alera_native::api::workspace_search::{
    self, WorkspaceReplaceFileExpectation, WorkspaceReplaceOptions, WorkspaceReplaceRequest,
    WorkspaceSearchOptions,
};
use async_channel::{Receiver, Sender};

use crate::workspace_git::{git_action, git_snapshot};
pub use crate::workspace_git::{GitAction, GitSnapshot};
use crate::workspace_preview::resolve_image_path;

const COMMAND_CAPACITY: usize = 32;

#[derive(Clone)]
pub struct WorkspaceService {
    commands: Sender<Command>,
}

enum Command {
    List {
        workspace_path: String,
        relative_path: String,
        reply: Sender<Result<Vec<FileEntry>, String>>,
    },
    Read {
        workspace_path: String,
        relative_path: String,
        reply: Sender<Result<EditorDocument, String>>,
    },
    Write {
        workspace_path: String,
        document: EditorDocument,
        display_content: String,
        overwrite: bool,
        reply: Sender<Result<EditorDocument, String>>,
    },
    Search {
        options: SearchOptions,
        reply: Sender<Result<SearchResults, String>>,
    },
    ReplaceAll {
        options: SearchOptions,
        replacement: String,
        reply: Sender<Result<ReplaceSummary, String>>,
    },
    Mermaid {
        workspace_path: String,
        relative_path: String,
        reply: Sender<Result<String, String>>,
    },
    ImagePath {
        workspace_path: String,
        relative_path: String,
        reply: Sender<Result<PathBuf, String>>,
    },
    GitSnapshot {
        workspace_path: String,
        reply: Sender<Result<GitSnapshot, String>>,
    },
    GitAction {
        workspace_path: String,
        action: GitAction,
        reply: Sender<Result<String, String>>,
    },
    Close,
}

#[derive(Clone, Debug)]
pub struct FileEntry {
    pub relative_path: String,
    pub name: String,
    pub is_directory: bool,
    pub is_hidden: bool,
    pub size: u64,
    pub git_status: Option<String>,
}

#[derive(Clone, Debug)]
pub struct EditorDocument {
    pub relative_path: String,
    pub raw_content: String,
    pub display_content: String,
    pub content_token: String,
    pub modified_millis: i64,
}

#[derive(Clone, Debug)]
pub struct SearchOptions {
    pub workspace_path: String,
    pub query: String,
    pub case_sensitive: bool,
    pub whole_word: bool,
    pub use_regex: bool,
    pub include_pattern: Option<String>,
    pub exclude_pattern: Option<String>,
    pub include_ignored: bool,
}

#[derive(Clone, Debug, Default)]
pub struct SearchResults {
    pub files: Vec<SearchFile>,
    pub total_matches: u32,
    pub truncated: bool,
}

#[derive(Clone, Debug)]
pub struct SearchFile {
    pub relative_path: String,
    pub matches: Vec<SearchMatch>,
}

#[derive(Clone, Debug)]
pub struct SearchMatch {
    pub line: u32,
    pub column: u32,
    pub line_content: String,
    pub replacement_preview: Option<String>,
}

#[derive(Clone, Debug)]
pub struct ReplaceSummary {
    pub files_changed: u32,
    pub matches_replaced: u32,
    pub conflicts: Vec<String>,
}

impl WorkspaceService {
    pub fn start() -> Self {
        let (commands, receiver) = async_channel::bounded(COMMAND_CAPACITY);
        thread::Builder::new()
            .name("alera-gpui-workspace".to_string())
            .spawn(move || run(receiver))
            .expect("failed to start the GPUI workspace service");
        Self { commands }
    }

    pub async fn list(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<Vec<FileEntry>, String> {
        request(&self.commands, |reply| Command::List {
            workspace_path,
            relative_path,
            reply,
        })
        .await
    }

    pub async fn read(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<EditorDocument, String> {
        request(&self.commands, |reply| Command::Read {
            workspace_path,
            relative_path,
            reply,
        })
        .await
    }

    pub async fn write(
        &self,
        workspace_path: String,
        document: EditorDocument,
        display_content: String,
        overwrite: bool,
    ) -> Result<EditorDocument, String> {
        request(&self.commands, |reply| Command::Write {
            workspace_path,
            document,
            display_content,
            overwrite,
            reply,
        })
        .await
    }

    pub async fn search(&self, options: SearchOptions) -> Result<SearchResults, String> {
        request(&self.commands, |reply| Command::Search { options, reply }).await
    }

    pub async fn replace_all(
        &self,
        options: SearchOptions,
        replacement: String,
    ) -> Result<ReplaceSummary, String> {
        request(&self.commands, |reply| Command::ReplaceAll {
            options,
            replacement,
            reply,
        })
        .await
    }

    pub async fn mermaid(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<String, String> {
        request(&self.commands, |reply| Command::Mermaid {
            workspace_path,
            relative_path,
            reply,
        })
        .await
    }

    pub async fn image_path(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<PathBuf, String> {
        request(&self.commands, |reply| Command::ImagePath {
            workspace_path,
            relative_path,
            reply,
        })
        .await
    }

    pub async fn git_snapshot(&self, workspace_path: String) -> Result<GitSnapshot, String> {
        request(&self.commands, |reply| Command::GitSnapshot {
            workspace_path,
            reply,
        })
        .await
    }

    pub async fn git_action(
        &self,
        workspace_path: String,
        action: GitAction,
    ) -> Result<String, String> {
        request(&self.commands, |reply| Command::GitAction {
            workspace_path,
            action,
            reply,
        })
        .await
    }
}

impl Drop for WorkspaceService {
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
        .map_err(|_| "Workspace service is closed.".to_string())?;
    response
        .recv()
        .await
        .map_err(|_| "Workspace service closed before replying.".to_string())?
}

fn run(commands: Receiver<Command>) {
    while let Ok(command) = commands.recv_blocking() {
        match command {
            Command::List {
                workspace_path,
                relative_path,
                reply,
            } => send(&reply, list_files(workspace_path, relative_path)),
            Command::Read {
                workspace_path,
                relative_path,
                reply,
            } => send(&reply, read_file(workspace_path, relative_path)),
            Command::Write {
                workspace_path,
                document,
                display_content,
                overwrite,
                reply,
            } => send(
                &reply,
                write_file(workspace_path, document, display_content, overwrite),
            ),
            Command::Search { options, reply } => send(&reply, search(options)),
            Command::ReplaceAll {
                options,
                replacement,
                reply,
            } => send(&reply, replace_all(options, replacement)),
            Command::Mermaid {
                workspace_path,
                relative_path,
                reply,
            } => send(
                &reply,
                merman_viewer::render_merman_workspace_file(workspace_path, relative_path)
                    .map(|render| render.svg)
                    .map_err(|error| error.context),
            ),
            Command::ImagePath {
                workspace_path,
                relative_path,
                reply,
            } => send(&reply, resolve_image_path(workspace_path, relative_path)),
            Command::GitSnapshot {
                workspace_path,
                reply,
            } => send(&reply, git_snapshot(workspace_path)),
            Command::GitAction {
                workspace_path,
                action,
                reply,
            } => send(&reply, git_action(workspace_path, action)),
            Command::Close => return,
        }
    }
}

fn send<T>(reply: &Sender<Result<T, String>>, result: Result<T, String>) {
    let _ = reply.send_blocking(result);
}

fn list_files(workspace_path: String, relative_path: String) -> Result<Vec<FileEntry>, String> {
    workspace_files::list_workspace_children(workspace_path, relative_path, true)
        .map_err(|error| error.context)
        .map(|entries| {
            entries
                .into_iter()
                .map(|entry| FileEntry {
                    relative_path: entry.relative_path,
                    name: entry.name,
                    is_directory: entry.kind == WorkspaceFileKind::Directory,
                    is_hidden: entry.is_hidden,
                    size: entry.size,
                    git_status: entry.git_status.map(|status| format!("{status:?}")),
                })
                .collect()
        })
}

fn read_file(workspace_path: String, relative_path: String) -> Result<EditorDocument, String> {
    workspace_files::read_workspace_editor_text_file(workspace_path, relative_path.clone(), 4)
        .map_err(|error| error.context)
        .map(|file| EditorDocument {
            relative_path,
            raw_content: file.raw_content,
            display_content: file.display_content,
            content_token: file.content_token,
            modified_millis: file.modified_millis,
        })
}

fn write_file(
    workspace_path: String,
    document: EditorDocument,
    display_content: String,
    overwrite: bool,
) -> Result<EditorDocument, String> {
    let relative_path = document.relative_path.clone();
    workspace_files::write_workspace_editor_text_file(
        workspace_path,
        relative_path.clone(),
        display_content,
        Some(document.raw_content),
        Some(document.display_content),
        Some(document.content_token),
        overwrite,
        4,
    )
    .map_err(|error| error.context)
    .map(|file| EditorDocument {
        relative_path,
        raw_content: file.raw_content,
        display_content: file.display_content,
        content_token: file.content_token,
        modified_millis: file.modified_millis,
    })
}

fn native_search_options(options: SearchOptions) -> WorkspaceSearchOptions {
    WorkspaceSearchOptions {
        workspace_path: options.workspace_path,
        query: options.query,
        case_sensitive: options.case_sensitive,
        whole_word: options.whole_word,
        use_regex: options.use_regex,
        include_pattern: options.include_pattern,
        exclude_pattern: options.exclude_pattern,
        include_ignored: options.include_ignored,
        max_results: None,
    }
}

fn search(options: SearchOptions) -> Result<SearchResults, String> {
    workspace_search::search_workspace(native_search_options(options))
        .map_err(|error| error.context)
        .map(map_search_results)
}

fn replace_all(options: SearchOptions, replacement: String) -> Result<ReplaceSummary, String> {
    let replace_options = WorkspaceReplaceOptions {
        search: native_search_options(options),
        replacement,
        preserve_case: false,
    };
    let preview = workspace_search::preview_workspace_replace(replace_options.clone())
        .map_err(|error| error.context)?;
    let match_ids = preview
        .result
        .files
        .iter()
        .flat_map(|file| file.matches.iter().map(|item| item.id.clone()))
        .collect();
    let expected_files = preview
        .result
        .files
        .iter()
        .map(|file| WorkspaceReplaceFileExpectation {
            relative_path: file.relative_path.clone(),
            content_token: file.content_token.clone(),
        })
        .collect();
    workspace_search::replace_workspace_matches(WorkspaceReplaceRequest {
        options: replace_options,
        match_ids,
        expected_files,
    })
    .map_err(|error| error.context)
    .map(|result| ReplaceSummary {
        files_changed: result.files_changed,
        matches_replaced: result.matches_replaced,
        conflicts: result
            .conflicts
            .into_iter()
            .map(|conflict| format!("{}: {}", conflict.relative_path, conflict.reason))
            .collect(),
    })
}

fn map_search_results(result: workspace_search::WorkspaceSearchResult) -> SearchResults {
    SearchResults {
        files: result
            .files
            .into_iter()
            .map(|file| SearchFile {
                relative_path: file.relative_path,
                matches: file
                    .matches
                    .into_iter()
                    .map(|item| SearchMatch {
                        line: item.line,
                        column: item.column,
                        line_content: item.line_content,
                        replacement_preview: item.replacement_preview,
                    })
                    .collect(),
            })
            .collect(),
        total_matches: result.total_matches,
        truncated: result.truncated,
    }
}
