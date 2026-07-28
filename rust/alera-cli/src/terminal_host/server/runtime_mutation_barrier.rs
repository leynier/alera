pub(super) fn is_serialized_runtime_mutation(request_type: &str) -> bool {
    matches!(
        request_type,
        "workspace.removeManaged"
            | "project.remove"
            | "workspace.remove"
            | "workspace.removeForProject"
            | "workspace.sleep"
            | "tab.remove"
            | "tab.removeForWorkspace"
    )
}

pub(super) fn conflicts_with_runtime_mutation(request_type: &str) -> bool {
    if request_type.starts_with("emulator.") || is_serialized_runtime_mutation(request_type) {
        return false;
    }
    matches!(
        request_type,
        "workspace.createManaged"
            | "createOrAttach"
            | "write"
            | "terminate"
            | "terminal.create"
            | "terminal.attach"
            | "terminal.restart"
            | "project.register"
            | "project.rename"
            | "project.upsert"
            | "projectConfig.remove"
            | "projectConfig.upsert"
            | "workspace.rename"
            | "workspace.setPinned"
            | "workspace.upsert"
            | "workspaceActivity.remove"
            | "workspaceActivity.upsertAll"
            | "workspaceRelation.link"
            | "workspaceRelation.unlink"
            | "workspaceTag.assign"
            | "workspaceTag.create"
            | "workspaceTag.remove"
            | "workspaceTag.setForWorkspace"
            | "workspaceTag.unassign"
            | "workspaceTag.upsert"
            | "tab.rename"
            | "tab.upsert"
            | "layout.remove"
            | "layout.upsert"
            | "linkedReview.remove"
            | "linkedReview.upsert"
            | "workbenchViewPrefs.update"
            | "browser.settings.set"
            | "browser.profiles.upsert"
            | "browser.profiles.remove"
            | "browser.history.clear"
            | "browser.closedTabs.remove"
            | "browser.permissions.set"
            | "browser.permissions.remove"
            | "browser.certificates.trust"
            | "browser.certificates.remove"
            | "browser.tabs.open"
            | "browser.tabs.close"
            | "browser.tabs.reopen"
            | "browser.closedTabs.reopen"
            | "browser.driver.sync"
            | "browser.driver.pageChanged"
    ) || matches!(
        request_type,
        "orchestration.agentSpawn"
            | "orchestration.dispatch"
            | "orchestration.dispatchAccept"
            | "orchestration.run"
            | "orchestration.taskRecover"
            | "orchestration.terminalPrune"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_runtime_store_writers_and_session_spawners_but_not_reads() {
        for writer in [
            "tab.upsert",
            "createOrAttach",
            "orchestration.agentSpawn",
            "browser.settings.set",
            "browser.profiles.upsert",
            "browser.profiles.remove",
            "browser.history.clear",
            "browser.closedTabs.remove",
            "browser.permissions.set",
            "browser.permissions.remove",
            "browser.certificates.trust",
            "browser.certificates.remove",
            "browser.tabs.open",
            "browser.tabs.close",
            "browser.tabs.reopen",
            "browser.closedTabs.reopen",
            "browser.driver.sync",
            "browser.driver.pageChanged",
        ] {
            assert!(
                conflicts_with_runtime_mutation(writer),
                "{writer} should be blocked"
            );
        }
        for read_or_serialized_mutation in [
            "tab.list",
            "terminal.read",
            "emulator.list",
            "tab.remove",
            "browser.settings.get",
            "browser.profiles.list",
            "browser.certificates.list",
            "browser.tabs.list",
            "browser.driver.register",
        ] {
            assert!(
                !conflicts_with_runtime_mutation(read_or_serialized_mutation),
                "{read_or_serialized_mutation} should remain available"
            );
        }
    }
}
