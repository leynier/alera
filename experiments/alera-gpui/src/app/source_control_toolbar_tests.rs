use gpui::{AppContext as _, Entity, Modifiers, TestAppContext, VisualTestContext};
use serde_json::json;

use super::AleraApp;
use crate::{activity::ContextPanel, model::{Project, Workspace}, runtime_bridge_test_support::{self, ControlledRuntime}};

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
            id: "project".into(), name: "Fixture".into(), repo_path: "/fixture/project".into(),
            kind: "gitRepository".into(), updated_at: String::new(), workspaces: vec![Workspace {
                id: "workspace".into(), name: "Fixture".into(), path: "/fixture/workspace".into(),
                kind: "main".into(), branch: Some("main".into()), source_branch: None, status: "active".into(),
                updated_at: String::new(), host_id: "local".into(), reuses_existing_branch: false,
                is_pinned: false, tag_ids: vec![], tag_names: vec![],
            }],
        }];
        app.selected_workspace_id = Some("workspace".into());
        app.snapshot.selected_workspace_id = Some("workspace".into());
        app.snapshot.tabs = vec![crate::model::WorkspaceTab {
            id: "tab".into(), workspace_id: "workspace".into(), kind: "editor".into(),
            title: "Fixture".into(), payload: json!({}),
        }];
        app.context_panel = ContextPanel::SourceControl;
        app.context_sidebar_width = 440.0;
    }));
    cx.run_until_parked();
    cx.update(|window, cx| { let _ = window.draw(cx); });
    (app, cx, runtime)
}

#[gpui::test]
fn source_toolbar_tree_list_click_persists_each_canonical_mode(cx: &mut TestAppContext) {
    let (app, cx, runtime) = fixture(cx);
    assert!(runtime.try_take().is_none(), "rendering the fixture must not issue a request");
    for (mode, expected_tree) in [("flat", false), ("tree", true)] {
        let bounds = cx.debug_bounds("source-view-mode").unwrap();
        cx.simulate_click(bounds.center(), Modifiers::default());
        cx.run_until_parked();
        cx.update(|_, cx| assert_eq!(app.read(cx).source_control_tree_mode, expected_tree));
        let request = runtime.take_with_timeout(std::time::Duration::from_millis(100))
            .expect("tree/list UI callback must persist its choice");
        assert_eq!(request.kind, "workbenchViewPrefs.update");
        assert_eq!(request.payload["prefs"]["gitDiffViewMode"], mode);
        request.respond(Ok(json!({"revision":1})));
        let bridge = cx.update(|_, cx| app.read(cx).bridge.clone());
        runtime.settle(cx, bridge);
        cx.update(|window, cx| { let _ = window.draw(cx); });
    }
}
