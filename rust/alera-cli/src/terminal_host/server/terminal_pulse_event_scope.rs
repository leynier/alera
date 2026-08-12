use std::path::Path;

use notify::event::{ModifyKind, RenameMode};
use notify::{Event, EventKind};

pub(in crate::terminal_host::server::terminal_pulse) fn event_invalidates_workspace_root(
    root: &Path,
    event: &Event,
) -> bool {
    event.paths.iter().any(|path| path == root)
        && matches!(
            event.kind,
            EventKind::Remove(_) | EventKind::Modify(ModifyKind::Name(_))
        )
}

pub(super) fn path_is_rename_source(event: &Event, path_index: usize) -> bool {
    matches!(event.kind, EventKind::Remove(_))
        || matches!(
            event.kind,
            EventKind::Modify(ModifyKind::Name(RenameMode::From))
        )
        || matches!(
            event.kind,
            EventKind::Modify(ModifyKind::Name(RenameMode::Both))
        ) && path_index == 0
}

pub(super) fn event_can_remove_paths(event: &Event) -> bool {
    matches!(
        event.kind,
        EventKind::Remove(_) | EventKind::Modify(ModifyKind::Name(_))
    )
}

pub(in crate::terminal_host::server::terminal_pulse) fn retain_workspace_paths(
    root: &Path,
    event: &mut Event,
) {
    if matches!(
        event.kind,
        EventKind::Modify(ModifyKind::Name(RenameMode::Both))
    ) && event.paths.len() >= 2
    {
        let from_inside = path_is_in_workspace(root, &event.paths[0]);
        let to_inside = path_is_in_workspace(root, &event.paths[1]);
        match (from_inside, to_inside) {
            (true, false) => {
                event.paths.truncate(1);
                event.kind = EventKind::Modify(ModifyKind::Name(RenameMode::From));
                return;
            }
            (false, true) => {
                let destination = event.paths[1].clone();
                event.paths = vec![destination];
                event.kind = EventKind::Modify(ModifyKind::Name(RenameMode::To));
                return;
            }
            _ => {}
        }
    }
    event.paths.retain(|path| path_is_in_workspace(root, path));
}

pub(super) fn path_is_in_workspace(root: &Path, path: &Path) -> bool {
    let Ok(relative) = path.strip_prefix(root) else {
        return false;
    };
    !relative.as_os_str().is_empty()
        && !relative
            .components()
            .any(|component| component.as_os_str() == ".git")
}
