use alera_core::runtime::RuntimeStore;

use crate::hosted_review_retention::{self, HostedReviewRetention};

use super::RuntimeMutationRequest;

pub(super) async fn for_request(
    runtime_store: &RuntimeStore,
    request: &RuntimeMutationRequest,
) -> Vec<HostedReviewRetention> {
    match request {
        RuntimeMutationRequest::RemoveProject { project_id }
        | RuntimeMutationRequest::RemoveProjectWorkspaces { project_id } => {
            hosted_review_retention::for_project(runtime_store, project_id).await
        }
        RuntimeMutationRequest::RemoveWorkspace {
            workspace_id,
            cascade_tabs: true,
        }
        | RuntimeMutationRequest::RemoveWorkspaceTabs { workspace_id }
        | RuntimeMutationRequest::SleepWorkspace { workspace_id } => {
            hosted_review_retention::for_workspace(runtime_store, workspace_id).await
        }
        RuntimeMutationRequest::RemoveManagedWorkspace { request } => {
            hosted_review_retention::for_workspace(runtime_store, &request.id).await
        }
        RuntimeMutationRequest::RemoveTab { tab_id } => {
            hosted_review_retention::for_tab(runtime_store, tab_id).await
        }
        RuntimeMutationRequest::RemoveWorkspace {
            cascade_tabs: false,
            ..
        } => Vec::new(),
    }
}
