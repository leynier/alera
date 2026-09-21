use super::{WorkspaceEditorTextFile, WorkspaceTextFile};

pub(super) use alera_core::workspace_files::encode_workspace_editor_text_for_save;

pub(super) fn editor_text_file_from_raw(
    file: WorkspaceTextFile,
    tab_size: i32,
) -> WorkspaceEditorTextFile {
    let display_content =
        alera_core::workspace_files::expand_workspace_editor_tabs(&file.content, tab_size);
    WorkspaceEditorTextFile {
        raw_content: file.content,
        display_content,
        content_token: file.content_token,
        modified_millis: file.modified_millis,
        size: file.size,
    }
}
