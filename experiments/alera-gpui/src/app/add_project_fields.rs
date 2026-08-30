use gpui::{Context, PathPromptOptions, Window};
use gpui_component::input::InputEvent;

use super::{AddProjectMode, AleraApp};

pub(super) enum ProjectField { LocalPath, CloneUrl, Destination, Name }

impl AleraApp {
    pub(super) fn add_project(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.show_add_project_dialog || self.add_project_busy { return; }
        self.add_project_previous_focus = window.focused(cx);
        self.add_project_draft.reset();
        self.add_project_mode = AddProjectMode::LocalFolder;
        self.show_add_project_dialog = true;
        self.error = None;
        for input in [&self.local_project_path_input, &self.clone_project_url_input,
            &self.clone_project_destination_input, &self.project_display_name_input] {
            input.update(cx, |input, cx| input.set_value("", window, cx));
        }
        self.local_project_path_input.update(cx, |input, cx| input.focus(window, cx));
        cx.notify();
    }

    pub(super) fn select_add_project_mode(&mut self, mode: AddProjectMode, window: &mut Window, cx: &mut Context<Self>) {
        if self.add_project_busy || self.add_project_mode == mode { return; }
        self.add_project_mode = mode;
        self.error = None;
        self.sync_add_project_defaults(true, window, cx);
        cx.notify();
    }

    pub(super) fn close_add_project_dialog(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.add_project_busy { return; }
        self.add_project_draft.invalidate();
        self.show_add_project_dialog = false;
        self.error = None;
        if let Some(focus) = self.add_project_previous_focus.take() { focus.focus(window, cx); }
        cx.notify();
    }

    pub(super) fn on_add_project_input(&mut self, field: ProjectField, event: &InputEvent, window: &mut Window, cx: &mut Context<Self>) {
        if !self.show_add_project_dialog || self.add_project_busy { return; }
        match event {
            InputEvent::Change => match field {
                ProjectField::Name => self.add_project_draft.observe_name(self.project_display_name_input.read(cx).value().as_ref()),
                ProjectField::Destination => self.add_project_draft.observe_destination(self.clone_project_destination_input.read(cx).value().as_ref()),
                ProjectField::LocalPath | ProjectField::CloneUrl => self.sync_add_project_defaults(false, window, cx),
            },
            InputEvent::PressEnter { .. } => self.submit_add_project(window, cx),
            _ => {}
        }
        cx.notify();
    }

    pub(super) fn sync_add_project_defaults(&mut self, mode_changed: bool, window: &mut Window, cx: &mut Context<Self>) {
        if !self.show_add_project_dialog || self.add_project_busy { return; }
        let suggestions = self.add_project_draft.suggestions(
            self.add_project_mode,
            self.local_project_path_input.read(cx).value().as_ref(),
            self.clone_project_url_input.read(cx).value().as_ref(),
            self.project_display_name_input.read(cx).value().as_ref(),
            self.clone_project_destination_input.read(cx).value().as_ref(),
            mode_changed,
        );
        if let Some(name) = suggestions.name {
            self.project_display_name_input.update(cx, |input, cx| input.set_value(name, window, cx));
        }
        if let Some(destination) = suggestions.destination {
            self.clone_project_destination_input.update(cx, |input, cx| input.set_value(destination, window, cx));
        }
        cx.notify();
    }

    pub(super) fn browse_local_project(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.browse_project_folder(false, window, cx);
    }

    pub(super) fn browse_clone_parent(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.browse_project_folder(true, window, cx);
    }

    fn browse_project_folder(&mut self, clone_parent: bool, window: &mut Window, cx: &mut Context<Self>) {
        if !self.show_add_project_dialog || self.add_project_busy { return; }
        let request = self.add_project_draft.begin_picker();
        let mode = self.add_project_mode;
        let selection = cx.prompt_for_paths(PathPromptOptions {
            files: false, directories: true, multiple: false,
            prompt: Some(if clone_parent { "Select Parent Folder" } else { "Select Folder" }.into()),
        });
        let this = cx.entity().downgrade();
        window.spawn(cx, async move |cx| {
            let result = selection.await;
            let _ = this.update_in(cx, |this, window, cx| {
                if !this.show_add_project_dialog || this.add_project_busy
                    || this.add_project_mode != mode || !this.add_project_draft.accepts(request) { return; }
                let path = match result {
                    Ok(Ok(Some(paths))) => paths.into_iter().next(),
                    Ok(Ok(None)) => None,
                    _ => {
                        this.local_message = Some("Native folder picker is not available; paste path manually.".into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                        cx.notify();
                        return;
                    }
                };
                let Some(path) = path else { return; };
                if clone_parent {
                    let current = this.clone_project_destination_input.read(cx).value().to_string();
                    this.add_project_draft.choose_parent(path, &current);
                } else {
                    this.local_project_path_input.update(cx, |input, cx| input.set_value(path.to_string_lossy().into_owned(), window, cx));
                }
                this.sync_add_project_defaults(false, window, cx);
            });
        }).detach();
    }
}
