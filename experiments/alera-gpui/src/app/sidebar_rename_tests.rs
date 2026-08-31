use gpui::{AppContext as _, Entity, Focusable as _, TestAppContext, VisualTestContext};

use super::{AleraApp, SidebarDialogKind};
use crate::model::{Project, Workspace};
use crate::runtime_bridge_test_support::{self, ControlledRuntime};

fn fixture(cx: &mut TestAppContext) -> (Entity<AleraApp>, &mut VisualTestContext, ControlledRuntime) {
    cx.executor().allow_parking();
    cx.update(gpui_component::init);
    cx.update(crate::design_system::configure_component_theme);
    let (bridge, runtime) = runtime_bridge_test_support::pair();
    let instance = std::rc::Rc::new(std::cell::RefCell::new(None));
    let captured = instance.clone();
    let (_, cx) = cx.add_window_view(|window, cx| {
        let app = cx.new(|cx| AleraApp::new_for_test(bridge, window, cx));
        *captured.borrow_mut() = Some(app.clone());
        gpui_component::Root::new(app, window, cx)
    });
    let app = instance.borrow_mut().take().unwrap();
    cx.update(|_, cx| app.update(cx, |app, _| {
        app.snapshot.projects = vec![Project {
            id: "project".into(), name: "Project á 😀".into(), repo_path: "/fixture/project".into(),
            kind: "gitRepository".into(), updated_at: String::new(),
            workspaces: vec![Workspace {
                id: "workspace".into(), name: "Workspace á 😀".into(), path: "/fixture/workspace".into(),
                branch: Some("main".into()), source_branch: None, kind: "main".into(), status: "active".into(),
                updated_at: String::new(), host_id: "local".into(), reuses_existing_branch: false,
                is_pinned: false, tag_ids: vec![], tag_names: vec![],
            }],
        }];
    }));
    (app, cx, runtime)
}

#[gpui::test]
fn sidebar_rename_initial_typing_replaces_selected_name(cx: &mut TestAppContext) {
    let (app, cx, _runtime) = fixture(cx);
    for (kind, id) in [(SidebarDialogKind::RenameProject, "project"), (SidebarDialogKind::RenameWorkspace, "workspace")] {
        cx.update(|window, cx| app.update(cx, |app, cx| app.open_sidebar_dialog(kind, id.into(), window, cx)));
        cx.run_until_parked();
        cx.update(|window, cx| {
            let _ = window.draw(cx);
            assert!(app.read(cx).sidebar_action_input.focus_handle(cx).is_focused(window), "rename input must receive initial focus");
        });
        cx.simulate_keystrokes("x");
        cx.update(|_, cx| assert_eq!(app.read(cx).sidebar_action_input.read(cx).value().as_ref(), "x"));
    }
}

#[gpui::test]
fn sidebar_rename_tab_cycle_and_escape_restore_invoker(cx: &mut TestAppContext) {
    let (app, cx, _runtime) = fixture(cx);
    cx.update(|window, cx| app.update(cx, |app, cx| {
        app.sidebar_filter_input.update(cx, |input, cx| input.focus(window, cx));
        app.open_sidebar_dialog(SidebarDialogKind::RenameWorkspace, "workspace".into(), window, cx);
    }));
    cx.run_until_parked();
    cx.update(|window, cx| { let _ = window.draw(cx); });
    for (key, expected) in [("tab", 1), ("tab", 2), ("tab", 0), ("shift-tab", 2), ("shift-tab", 1), ("shift-tab", 0)] {
        cx.simulate_keystrokes(key);
        cx.update(|window, cx| {
            let _ = window.draw(cx);
            let app = app.read(cx);
            let handles = [app.sidebar_action_input.focus_handle(cx), app.sidebar_rename_button_focus[0].clone(), app.sidebar_rename_button_focus[1].clone()];
            assert!(handles[expected].is_focused(window), "focus escaped rename on {key}: input/cancel/confirm={:?}, in_trap={}, trap_focused={}", handles.iter().map(|handle| handle.is_focused(window)).collect::<Vec<_>>(), app.sidebar_rename_focus.contains_focused(window, cx), app.sidebar_rename_focus.is_focused(window));
        });
    }
    cx.simulate_keystrokes("escape");
    cx.run_until_parked();
    cx.update(|window, cx| {
        assert!(app.read(cx).sidebar_dialog.is_none());
        assert!(app.read(cx).sidebar_filter_input.focus_handle(cx).is_focused(window));
        let _ = window.draw(cx);
    });
    cx.simulate_keystrokes("z");
    cx.update(|_, cx| assert_eq!(app.read(cx).sidebar_filter_input.read(cx).value().as_ref(), "z"));
}

#[gpui::test]
fn sidebar_rename_enter_validates_then_submits_only_the_intended_target(cx: &mut TestAppContext) {
    let (app, cx, runtime) = fixture(cx);
    for (kind, target, method, id_key, label) in [
        (SidebarDialogKind::RenameProject, "project", "project.rename", "id", "Project Name"),
        (SidebarDialogKind::RenameWorkspace, "workspace", "workspace.rename", "workspaceId", "Workspace Name"),
    ] {
        cx.update(|window, cx| app.update(cx, |app, cx| app.open_sidebar_dialog(kind, target.into(), window, cx)));
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        cx.simulate_keystrokes("backspace");
        cx.run_until_parked();
        cx.update(|window, cx| {
            assert!(app.read(cx).sidebar_action_input.read(cx).value().is_empty(), "Backspace must clear the selected initial name");
            let _ = window.draw(cx);
        });
        cx.simulate_keystrokes("enter");
        cx.run_until_parked();
        cx.update(|_, cx| {
            assert!(app.read(cx).sidebar_dialog.is_some());
            assert_eq!(app.read(cx).error.as_deref(), Some(format!("{label} is required").as_str()));
        });
        assert!(runtime.try_take().is_none(), "empty rename must not mutate runtime");
        cx.simulate_keystrokes("n e w");
        cx.run_until_parked();
        cx.update(|_, cx| assert!(app.read(cx).error.is_none(), "editing clears inline validation"));
        cx.simulate_keystrokes("enter");
        cx.run_until_parked();
        let request = runtime.take();
        assert_eq!(request.kind, method);
        assert_eq!(request.payload[id_key], target);
        assert_eq!(request.payload["name"], "new");
        cx.update(|window, cx| {
            assert!(app.read(cx).sidebar_dialog.is_none());
            assert!(app.read(cx).shell_focus.is_focused(window));
        });
        request.respond(Err("controlled rename failure".into()));
        let bridge = cx.update(|_, cx| app.read(cx).bridge.clone());
        runtime.settle(cx, bridge);
        assert!(runtime.try_take().is_none(), "one Enter must issue only one rename");
    }
}

#[gpui::test]
fn sidebar_rename_pointer_dismissal_is_scoped_to_the_scrim(cx: &mut TestAppContext) {
    let (app, cx, _runtime) = fixture(cx);
    cx.update(|window, cx| app.update(cx, |app, cx| app.open_sidebar_dialog(SidebarDialogKind::RenameWorkspace, "workspace".into(), window, cx)));
    cx.run_until_parked();
    cx.update(|window, cx| { let _ = window.draw(cx); });
    let bounds = cx.debug_bounds("sidebar-rename-dialog").unwrap();
    cx.simulate_click(bounds.origin + gpui::point(gpui::px(10.0), gpui::px(10.0)), gpui::Modifiers::default());
    cx.update(|_, cx| assert!(app.read(cx).sidebar_dialog.is_some(), "inside click dismissed rename"));
    cx.simulate_click(gpui::point(gpui::px(1.0), gpui::px(1.0)), gpui::Modifiers::default());
    cx.update(|window, cx| {
        assert!(app.read(cx).sidebar_dialog.is_none(), "outside click did not dismiss rename");
        assert!(app.read(cx).shell_focus.is_focused(window));
    });
}
