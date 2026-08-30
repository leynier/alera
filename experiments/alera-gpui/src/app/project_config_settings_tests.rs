use super::*;

fn effective(prompt: &str) -> EffectiveProjectConfig {
    EffectiveProjectConfig {
        config: ProjectConfig {
            new_workspace: NewWorkspaceConfig {
                prompt_append: prompt.into(),
            },
            ..Default::default()
        },
        origin: "uiOverride".into(),
        error: None,
    }
}

#[gpui::test]
fn project_response_guards_preserve_live_input_drafts(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let cx = cx.add_empty_window();
    cx.update(|window, cx| {
        let mut state = ProjectConfigSettingsState::new(window, cx);
        state.select_project("a".into());
        state.seed(effective("saved a"), "a", true, window, cx);
        let save = ProjectConfigRequestScope::new(
            "a".into(),
            state.selection_epoch,
            state.draft_signature(cx),
        );

        state.select_project("b".into());
        state.seed(effective("saved b"), "b", true, window, cx);
        let read = ProjectConfigRequestScope::new(
            "b".into(),
            state.selection_epoch,
            state.draft_signature(cx),
        );
        state.prompt_append_input.update(cx, |input, cx| {
            input.set_value("unsaved b á\nsecond line", window, cx)
        });
        assert!(!save.is_selected(state.selected_project_id.as_deref(), state.selection_epoch));
        let replace =
            read.may_replace_draft(&state.draft_signature(cx), state.seeded_draft.as_deref());
        state.seed(effective("late server b"), "b", replace, window, cx);
        assert_eq!(
            state.prompt_append_input.read(cx).value().as_str(),
            "unsaved b á\nsecond line"
        );

        let save_b = ProjectConfigRequestScope::new(
            "b".into(),
            state.selection_epoch,
            state.draft_signature(cx),
        );
        state.prompt_append_input.update(cx, |input, cx| {
            input.set_value("typed while saving", window, cx)
        });
        assert!(!save_b.draft_is_unchanged(&state.draft_signature(cx)));
    });
}
