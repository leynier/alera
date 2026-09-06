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
    if is_serialized_runtime_mutation(request_type) {
        return false;
    }
    mutates_codex_runtime_state(request_type)
        || matches!(
            request_type,
            "workspace.createManaged"
                | "workspace.runSetup"
                | "createOrAttach"
                | "write"
                | "terminate"
                | "terminal.create"
                | "terminal.attach"
                | "terminal.restart"
                | "terminal.pulse.configure"
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
                | "workspaceSection.create"
                | "workspaceSection.setForWorkspace"
                | "workspaceSection.remove"
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
                | "automation.upsert"
                | "automation.approve"
                | "automation.resume"
                | "automation.restore"
                | "automation.runNow"
                | "automation.import"
        )
        || matches!(
            request_type,
            "orchestration.agentSpawn"
                | "orchestration.dispatch"
                | "orchestration.dispatchAccept"
                | "orchestration.run"
                | "orchestration.taskRecover"
                | "orchestration.terminalPrune"
        )
}

fn mutates_codex_runtime_state(request_type: &str) -> bool {
    request_type.starts_with("codex.")
        && !matches!(
            request_type,
            "codex.thread.list"
                | "codex.threads.list"
                | "codex.session.list"
                | "codex.thread.history"
                | "codex.thread.turns.list"
                | "codex.session.history"
                | "codex.thread.snapshot"
                | "codex.thread.items.list"
                | "codex.model.list"
                | "codex.collaborationModes.list"
                | "codex.skills.list"
                | "codex.apps.list"
                | "codex.turn.interrupt"
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
            "terminal.pulse.configure",
            "codex.turn.start",
            "codex.thread.resume",
            "codex.response",
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
            "automation.upsert",
            "automation.approve",
            "automation.resume",
            "automation.restore",
            "automation.runNow",
            "automation.import",
        ] {
            assert!(
                conflicts_with_runtime_mutation(writer),
                "{writer} should be blocked"
            );
        }
        for read_or_serialized_mutation in [
            "tab.list",
            "terminal.read",
            "tab.remove",
            "browser.settings.get",
            "browser.profiles.list",
            "browser.certificates.list",
            "browser.tabs.list",
            "browser.driver.register",
            "codex.thread.list",
            "codex.thread.history",
            "codex.thread.snapshot",
            "codex.model.list",
            "codex.turn.interrupt",
        ] {
            assert!(
                !conflicts_with_runtime_mutation(read_or_serialized_mutation),
                "{read_or_serialized_mutation} should remain available"
            );
        }
    }
}
