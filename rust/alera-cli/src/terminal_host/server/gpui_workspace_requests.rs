use serde_json::Value;

use crate::terminal_host::host_error::HostResult;

use super::super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_gpui_workspace_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let value = match request_type {
            "workspaceFiles.list" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::list_workspace_files(payload).await?
            }
            "workspaceFiles.metadata" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::workspace_file_metadata(payload).await?
            }
            "workspaceFiles.readEditor" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::read_workspace_file(payload).await?
            }
            "workspaceFiles.writeEditor" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::write_workspace_file(payload).await?
            }
            "workspaceFiles.createFile" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::create_workspace_file_request(payload)
                    .await?
            }
            "workspaceFiles.createDirectory" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::create_workspace_directory_request(payload)
                    .await?
            }
            "workspaceFiles.rename" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::rename_workspace_file(payload).await?
            }
            "workspaceFiles.copy" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::copy_workspace_file(payload).await?
            }
            "workspaceFiles.move" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::move_workspace_file(payload).await?
            }
            "workspaceFiles.delete" => {
                self.require_auth(client_id)?;
                super::super::workspace_file_requests::delete_workspace_file(payload).await?
            }
            "workspaceGit.snapshot" => {
                self.require_auth(client_id)?;
                super::super::workspace_git_requests::snapshot(payload).await?
            }
            "workspaceGit.explorerStatus" => {
                self.require_auth(client_id)?;
                super::super::workspace_git_requests::explorer_status(payload).await?
            }
            "workspaceGit.action" => {
                self.require_auth(client_id)?;
                super::super::workspace_git_requests::action(payload).await?
            }
            "workspaceGit.commitCompare" => {
                self.require_auth(client_id)?;
                super::super::workspace_git_requests::commit_compare(payload).await?
            }
            "workspaceGit.diff" => {
                self.require_auth(client_id)?;
                super::super::workspace_git_requests::diff(payload).await?
            }
            "workspaceGit.diffBlob" => {
                self.require_auth(client_id)?;
                super::super::workspace_git_requests::diff_blob(payload).await?
            }
            "workspaceSearch.search" => {
                self.require_auth(client_id)?;
                super::super::workspace_search_requests::search(payload).await?
            }
            "workspaceSearch.previewReplace" => {
                self.require_auth(client_id)?;
                super::super::workspace_search_requests::preview_replace(payload).await?
            }
            "workspaceSearch.cancel" => {
                self.require_auth(client_id)?;
                super::super::workspace_search_requests::cancel(payload).await?
            }
            "workspaceSearch.replaceAll" => {
                self.require_auth(client_id)?;
                super::super::workspace_search_requests::replace_all(payload).await?
            }
            "workspaceSearch.replaceMatches" => {
                self.require_auth(client_id)?;
                super::super::workspace_search_requests::replace_matches(payload).await?
            }
            "workspacePreview.mermaid" => {
                self.require_auth(client_id)?;
                super::super::workspace_preview_requests::render_mermaid(payload).await?
            }
            "workspacePreview.image" => {
                self.require_auth(client_id)?;
                super::super::workspace_preview_requests::read_image(payload).await?
            }
            _ => return Ok(None),
        };
        Ok(Some(value))
    }
}
