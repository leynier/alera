use alera_core::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, APPROVAL_MESSAGE_MAX_BYTES,
};

/// Called only by the local desktop decision flow after explicit user action.
/// Neither the runtime RPC nor terminal CLI exposes a signing operation.
pub fn sign_workflow_decision(
    runtime_dir: String,
    statement_json: String,
) -> Result<Vec<u8>, String> {
    if statement_json.len() > APPROVAL_MESSAGE_MAX_BYTES {
        return Err("Workflow approval exceeds the byte limit.".into());
    }
    let statement: WorkflowApprovalStatement = serde_json::from_str(&statement_json)
        .map_err(|_| "Invalid workflow approval statement.".to_owned())?;
    let credential = DesktopWorkflowCredential::load_or_create(std::path::Path::new(&runtime_dir))
        .map_err(|_| "Desktop workflow credential is unavailable.".to_owned())?;
    credential
        .sign(&statement)
        .map_err(|_| "Cannot sign this workflow decision.".to_owned())
}
