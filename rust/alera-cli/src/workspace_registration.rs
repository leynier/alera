use alera_core::runtime::{Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID};
use chrono::Utc;
use uuid::Uuid;

use crate::cli::{WorkspaceKindArg, WorkspaceRegisterArgs};

pub fn from_args(args: WorkspaceRegisterArgs) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: args.id.unwrap_or_else(|| Uuid::new_v4().to_string()),
        instance_id: args
            .instance_id
            .unwrap_or_else(|| Uuid::new_v4().to_string()),
        host_id: args.host_id.unwrap_or_else(|| LOCAL_HOST_ID.to_string()),
        project_id: args.project_id,
        name: args.name,
        branch: args.branch,
        path: args.path,
        created_at: now,
        updated_at: now,
        kind: match args.kind {
            WorkspaceKindArg::Main => WorkspaceKind::Main,
            WorkspaceKindArg::Linked => WorkspaceKind::Linked,
        },
        status: WorkspaceStatus::Active,
        source_branch: args.source_branch,
        reuses_existing_branch: args.reuses_existing_branch,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}
