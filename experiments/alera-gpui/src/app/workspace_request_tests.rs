use gpui::{AppContext as _,Context,Entity,IntoElement,ParentElement as _,Render,TestAppContext,Window,div};
use serde_json::json;

use super::{AleraApp,NewWorkspaceMode,NewWorkspaceStep};
use crate::runtime_bridge_test_support::{self as test_support,ControlledRuntime};

struct Probe {app:Entity<AleraApp>}
impl Render for Probe {
    fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl IntoElement {div().child("Controlled runtime requests")}
}

fn initialize(cx:&mut TestAppContext) {
    // The real bridge wakes from Tokio; the fixture controls response order.
    cx.executor().allow_parking();
    cx.update(gpui_component::init);cx.update(crate::design_system::configure_component_theme);
}

fn seed(app:&Entity<AleraApp>,window:&mut Window,cx:&mut gpui::App) {
    app.update(cx,|app,cx|{
        app.snapshot.projects=vec![crate::model::Project{id:"project".into(),name:"Fixture".into(),repo_path:"/nonexistent/review-fixture".into(),kind:"gitRepository".into(),updated_at:String::new(),workspaces:vec![]}];
        app.selected_workspace_project_id=Some("project".into());
        app.selected_workspace_source_branch=Some("main".into());
        app.show_new_workspace_dialog=true;
        app.new_workspace_mode=NewWorkspaceMode::Manual;
        app.new_workspace_step=NewWorkspaceStep::ManualSettings;
        app.workspace_branch_input.update(cx,|input,cx|input.set_value("feature/kept",window,cx));
        app.workspace_name_input.update(cx,|input,cx|input.set_value("Unsaved draft",window,cx));
    });
}

#[gpui::test]
fn manual_workspace_pending_request_blocks_reentry_and_preserves_failed_draft(cx:&mut TestAppContext) {
    initialize(cx);
    let (bridge,runtime)=test_support::pair();
    let (host,cx)=cx.add_window_view(|window,cx|Probe{app:cx.new(|cx|AleraApp::new_for_test(bridge,window,cx))});
    let app=cx.update(|window,cx|{let app=host.read(cx).app.clone();seed(&app,window,cx);app});
    cx.run_until_parked();
    assert!(runtime.try_take().is_none(),"construction must not contact the runtime");
    cx.update(|window,cx|app.update(cx,|app,cx|app.create_workspace(window,cx)));
    cx.run_until_parked();
    let request=runtime.take();
    assert_eq!(request.kind,"workspace.createManaged");
    assert_eq!(request.payload["projectId"],"project");
    assert_eq!(request.payload["branch"],"feature/kept");
    cx.update(|window,cx|app.update(cx,|app,cx|{
        app.create_workspace(window,cx);
        app.open_new_workspace_dialog_for_project(Some("other".into()),window,cx);
        app.select_new_workspace_mode(NewWorkspaceMode::FromPrompt,cx);
        app.back_new_workspace(cx);
        app.continue_manual_workspace(cx);
        app.select_workspace_project("other".into(),cx);
        app.toggle_create_another_workspace(cx);
        assert!(app.workspace_creation_busy);
        assert_eq!(app.new_workspace_step,NewWorkspaceStep::ManualSettings);
        assert_eq!(app.selected_workspace_project_id.as_deref(),Some("project"));
        assert!(!app.create_another_workspace);
    }));
    cx.run_until_parked();
    assert!(runtime.try_take().is_none(),"busy interaction issued another request");
    request.respond(Err("controlled creation failure".into()));
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    cx.update(|_,cx|{
        let state=app.read(cx);
        assert!(!state.workspace_creation_busy);
        assert!(state.show_new_workspace_dialog);
        assert_eq!(state.error.as_deref(),Some("controlled creation failure"));
        assert_eq!(state.workspace_branch_input.read(cx).value().as_ref(),"feature/kept");
        assert_eq!(state.workspace_name_input.read(cx).value().as_ref(),"Unsaved draft");
    });
    cx.update(|window,cx|app.update(cx,|app,cx|app.create_workspace(window,cx)));
    cx.run_until_parked();
    let retry=runtime.take();assert_eq!(retry.payload["branch"],"feature/kept");
    retry.respond(Err("controlled retry failure".into()));let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
}

#[gpui::test]
fn manual_workspace_branch_responses_cannot_replace_a_newer_same_project_result(cx:&mut TestAppContext) {
    initialize(cx);
    let (bridge,runtime):(_,ControlledRuntime)=test_support::pair();
    let (host,cx)=cx.add_window_view(|window,cx|Probe{app:cx.new(|cx|AleraApp::new_for_test(bridge,window,cx))});
    let app=cx.update(|window,cx|{let app=host.read(cx).app.clone();seed(&app,window,cx);app});
    cx.run_until_parked();
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_workspace_branches("project".into(),cx)));
    cx.run_until_parked();let older=runtime.take();
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_workspace_branches("project".into(),cx)));
    cx.run_until_parked();let newer=runtime.take();
    assert_eq!(older.kind,"project.branches.list");assert_eq!(newer.kind,"project.branches.list");
    newer.respond(Ok(json!({"branches":["new"],"localBranches":["new"]})));
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    older.respond(Ok(json!({"branches":["old"],"localBranches":["old"]})));
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    cx.update(|_,cx|assert_eq!(app.read(cx).workspace_source_branches,vec!["new"]));
}

#[gpui::test]
fn manual_workspace_closed_dialog_rejects_late_branch_errors(cx:&mut TestAppContext) {
    initialize(cx);
    let (bridge,runtime)=test_support::pair();
    let (host,cx)=cx.add_window_view(|window,cx|Probe{app:cx.new(|cx|AleraApp::new_for_test(bridge,window,cx))});
    let app=cx.update(|window,cx|{let app=host.read(cx).app.clone();seed(&app,window,cx);app});
    cx.run_until_parked();
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_workspace_branches("project".into(),cx)));
    cx.run_until_parked();let request=runtime.take();
    cx.update(|_,cx|app.update(cx,|app,cx|app.close_new_workspace_dialog(cx)));
    request.respond(Err("late branch error".into()));let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    cx.update(|_,cx|assert!(app.read(cx).error.is_none(),"a closed dialog published a stale error"));
}

struct DetachedProbe;
impl Render for DetachedProbe {fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl IntoElement {div()}}

#[gpui::test]
fn manual_workspace_response_after_owner_drop_does_not_resurrect_ui(cx:&mut TestAppContext) {
    initialize(cx);
    let (bridge,runtime)=test_support::pair();
    let (_,cx)=cx.add_window_view(|_,_|DetachedProbe);
    let app=cx.update(|window,cx|cx.new(|cx|AleraApp::new_for_test(bridge,window,cx)));
    cx.update(|window,cx|seed(&app,window,cx));cx.run_until_parked();
    cx.update(|window,cx|app.update(cx,|app,cx|app.create_workspace(window,cx)));
    cx.run_until_parked();let request=runtime.take();let weak=app.downgrade();let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());drop(app);cx.run_until_parked();
    assert!(weak.upgrade().is_none(),"creation retained its owner");
    request.respond(Ok(json!({"workspace":{"id":"late","projectId":"project"}})));runtime.settle(cx,bridge);
    assert!(weak.upgrade().is_none());assert!(runtime.try_take().is_none());
}

fn take_profile_load(runtime:&ControlledRuntime)->test_support::ControlledRequest {
    let mut profile=None;
    for request in [runtime.take(),runtime.take()] {
        match request.kind.as_str() {
            "project.branches.list"=>request.respond(Ok(json!({"branches":["main"],"localBranches":["main"]}))),
            "agentProfile.list"=>profile=Some(request),
            unexpected=>panic!("unexpected dialog request {unexpected}"),
        }
    }
    profile.expect("profile list request")
}

#[gpui::test]
fn manual_workspace_profile_response_is_scoped_to_current_dialog_generation(cx:&mut TestAppContext) {
    initialize(cx);
    let (bridge,runtime)=test_support::pair();
    let (host,cx)=cx.add_window_view(|window,cx|Probe{app:cx.new(|cx|AleraApp::new_for_test(bridge,window,cx))});
    let app=cx.update(|window,cx|{let app=host.read(cx).app.clone();seed(&app,window,cx);app});
    cx.run_until_parked();
    cx.update(|window,cx|app.update(cx,|app,cx|app.open_new_workspace_dialog_for_project(Some("project".into()),window,cx)));
    cx.run_until_parked();let older=take_profile_load(&runtime);
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    cx.update(|window,cx|app.update(cx,|app,cx|app.open_new_workspace_dialog_for_project(Some("project".into()),window,cx)));
    cx.run_until_parked();let newer=take_profile_load(&runtime);
    newer.respond(Ok(json!({"items":[{"id":"new","name":"New profile"}]})));
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    older.respond(Ok(json!({"items":[{"id":"old","name":"Old profile"}]})));
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    cx.update(|_,cx|assert_eq!(app.read(cx).workspace_selected_agent_profile_id.as_deref(),Some("new")));
    cx.update(|window,cx|app.update(cx,|app,cx|app.open_new_workspace_dialog_for_project(Some("project".into()),window,cx)));
    cx.run_until_parked();let late=take_profile_load(&runtime);
    cx.update(|_,cx|app.update(cx,|app,cx|app.close_new_workspace_dialog(cx)));
    late.respond(Err("late profile error".into()));
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
    cx.update(|_,cx|assert!(app.read(cx).error.is_none()));
}
