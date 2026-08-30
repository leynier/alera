use std::path::{Path, PathBuf};

use super::AddProjectMode;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct PickerRequest(u64, u64);

#[derive(Default)]
pub(super) struct AddProjectDraft {
    view_epoch: u64,
    picker_epoch: u64,
    name_touched: bool,
    destination_touched: bool,
    suggested_name: String,
    suggested_destination: String,
    clone_parent: Option<PathBuf>,
}

#[derive(Default, Debug, PartialEq, Eq)]
pub(super) struct ProjectSuggestions {
    pub name: Option<String>,
    pub destination: Option<String>,
}

impl AddProjectDraft {
    pub(super) fn reset(&mut self) {
        let epoch = self.view_epoch.wrapping_add(1);
        *self = Self { view_epoch: epoch, ..Self::default() };
    }

    pub(super) fn invalidate(&mut self) {
        self.view_epoch = self.view_epoch.wrapping_add(1);
    }

    pub(super) fn begin_picker(&mut self) -> PickerRequest {
        self.picker_epoch = self.picker_epoch.wrapping_add(1);
        PickerRequest(self.view_epoch, self.picker_epoch)
    }

    pub(super) fn accepts(&self, request: PickerRequest) -> bool {
        request == PickerRequest(self.view_epoch, self.picker_epoch)
    }

    pub(super) fn observe_name(&mut self, value: &str) {
        self.name_touched |= value != self.suggested_name;
    }

    pub(super) fn observe_destination(&mut self, value: &str) {
        if value != self.suggested_destination {
            self.destination_touched = true;
            self.clone_parent = None;
        }
    }

    pub(super) fn choose_parent(&mut self, parent: PathBuf, current_destination: &str) {
        self.clone_parent = Some(parent);
        self.destination_touched = false;
        self.suggested_destination = current_destination.to_owned();
    }

    pub(super) fn suggestions(
        &mut self,
        mode: AddProjectMode,
        local_path: &str,
        clone_url: &str,
        current_name: &str,
        current_destination: &str,
        mode_changed: bool,
    ) -> ProjectSuggestions {
        // Observe live drafts before applying defaults, including edits whose
        // queued InputEvent has not reached the parent yet.
        self.observe_name(current_name);
        self.observe_destination(current_destination);
        let repo_name = repository_name(clone_url);
        let name = match mode {
            AddProjectMode::LocalFolder => Some(local_name(local_path)),
            AddProjectMode::CloneFromUrl if mode_changed => Some(repo_name.clone().unwrap_or_default()),
            AddProjectMode::CloneFromUrl => repo_name.clone(),
        };
        let mut result = ProjectSuggestions::default();
        if !self.name_touched {
            if let Some(name) = name {
                self.suggested_name = name.clone();
                if name != current_name { result.name = Some(name); }
            }
        }
        if mode == AddProjectMode::CloneFromUrl && !self.destination_touched {
            if let (Some(parent), Some(name)) = (&self.clone_parent, repo_name) {
                let destination = parent.join(name).to_string_lossy().into_owned();
                self.suggested_destination = destination.clone();
                if destination != current_destination { result.destination = Some(destination); }
            }
        }
        result
    }
}

fn local_name(value: &str) -> String {
    let value = value.trim();
    Path::new(value).file_name().and_then(|name| name.to_str()).unwrap_or(value).to_owned()
}

pub(super) fn repository_name(value: &str) -> Option<String> {
    let url = value.trim().split('?').next()?.trim_end_matches(['/', '\\']);
    let name = url.rsplit(['/', '\\', ':']).next()?;
    let name = name.strip_suffix(".git").unwrap_or(name).trim();
    (!name.is_empty()).then(|| name.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn project_defaults_follow_paths_until_the_name_is_manually_edited() {
        let mut draft = AddProjectDraft::default();
        let mode = AddProjectMode::LocalFolder;
        assert_eq!(draft.suggestions(mode, "/tmp/á-project/", "", "", "", false).name.as_deref(), Some("á-project"));
        draft.observe_name("á-project");
        assert_eq!(draft.suggestions(mode, "/tmp/second", "", "á-project", "", false).name.as_deref(), Some("second"));
        assert_eq!(draft.suggestions(mode, "/tmp/third", "", "custom", "", false).name, None);
        assert_eq!(draft.suggestions(mode, "/tmp/fourth", "", "", "", false).name, None);
    }

    #[test]
    fn project_defaults_allow_parent_before_url_and_preserve_manual_destination() {
        let mut draft = AddProjectDraft::default();
        let mode = AddProjectMode::CloneFromUrl;
        draft.choose_parent(PathBuf::from("/review"), "");
        assert_eq!(draft.suggestions(mode, "", "", "", "", false), ProjectSuggestions::default());
        let first = draft.suggestions(mode, "", "git@example:org/one.git", "", "", false);
        assert_eq!(first.name.as_deref(), Some("one"));
        assert_eq!(first.destination.map(PathBuf::from), Some(PathBuf::from("/review").join("one")));
        let previous = PathBuf::from("/review").join("one").to_string_lossy().into_owned();
        let next = draft.suggestions(mode, "", "https://example/two.git?ref=x", "one", &previous, false);
        assert_eq!(next.destination.map(PathBuf::from), Some(PathBuf::from("/review").join("two")));
        assert_eq!(draft.suggestions(mode, "", "three.git", "two", "/custom", false).destination, None);
        draft.choose_parent(PathBuf::from("/new"), "/custom");
        assert_eq!(draft.suggestions(mode, "", "three.git", "three", "/custom", false).destination.map(PathBuf::from), Some(PathBuf::from("/new").join("three")));
    }

    #[test]
    fn project_defaults_clear_untouched_name_on_mode_switch_and_preserve_it_for_empty_url_edits() {
        let mut draft = AddProjectDraft::default();
        draft.suggestions(AddProjectMode::LocalFolder, "/tmp/local", "", "", "", false);
        assert_eq!(draft.suggestions(AddProjectMode::CloneFromUrl, "", "", "local", "", true).name.as_deref(), Some(""));
        draft.suggestions(AddProjectMode::CloneFromUrl, "", "repo.git", "", "", false);
        assert_eq!(draft.suggestions(AddProjectMode::CloneFromUrl, "", "", "repo", "", false).name, None);
    }

    #[test]
    fn project_picker_requests_cannot_update_a_newer_picker_or_reopened_form() {
        let mut draft = AddProjectDraft::default();
        let old = draft.begin_picker();
        let latest = draft.begin_picker();
        assert!(!draft.accepts(old));
        assert!(draft.accepts(latest));
        draft.invalidate();
        assert!(!draft.accepts(latest));
        draft.reset();
        assert!(!draft.accepts(old));
    }
}
