use gpui::{AppContext as _,Context,Entity,IntoElement,Render,TestAppContext,VisualTestContext,Window,div};
use serde_json::{Value,json};

use super::{AleraApp,SidebarGroupBy};
use crate::runtime_bridge_test_support::{self,ControlledRuntime};
use crate::workbench_prefs_store::WorkbenchPrefsStore;

struct Probe {app:Entity<AleraApp>}
impl Render for Probe {fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl IntoElement{div()}}

fn fixture(cx:&mut TestAppContext)->(Entity<AleraApp>,&mut VisualTestContext,ControlledRuntime) {
    cx.executor().allow_parking();cx.update(gpui_component::init);cx.update(crate::design_system::configure_component_theme);
    let (bridge,runtime)=runtime_bridge_test_support::pair();
    let (host,cx)=cx.add_window_view(|window,cx|Probe{app:cx.new(|cx|AleraApp::new_for_test(bridge,window,cx))});
    let app=cx.update(|_,cx|host.read(cx).app.clone());
    let local:Value=serde_json::from_str(include_str!("../../tests/fixtures/workbench_view_prefs.json")).unwrap();
    cx.update(|_,cx|app.update(cx,|app,_|app.workbench_prefs_store=WorkbenchPrefsStore::memory(Some(local))));
    (app,cx,runtime)
}

fn settle(runtime:&ControlledRuntime,app:&Entity<AleraApp>,cx:&mut VisualTestContext) {
    let bridge=cx.update(|_,cx|app.read(cx).bridge.clone());runtime.settle(cx,bridge);
}

fn record(initialized:bool,revision:u64,group:&str)->Value {
    json!({"desktopInitialized":initialized,"revision":revision,"prefs":{"groupBy":group,"projectSort":"name","workspaceSort":"name","selectedProjectIds":[],"selectedTagIds":[],"collapsedProjectIds":[],"collapsedParentWorkspaceIds":[],"showPinnedWorkspacesBelow":true,"workspaceKindFilter":"all"}})
}

#[gpui::test]
fn view_prefs_first_desktop_load_keeps_and_seeds_local_choices(cx:&mut TestAppContext) {
    let (app,cx,runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_sidebar_view_prefs(cx)));cx.run_until_parked();
    let load=runtime.take();assert_eq!(load.kind,"workbenchViewPrefs.get");
    load.respond(Ok(record(false,0,"project")));settle(&runtime,&app,cx);
    cx.update(|_,cx|{
        let app=app.read(cx);assert_eq!(app.sidebar_group_by,SidebarGroupBy::None);
        assert_eq!(app.sidebar_width,412.0);assert!(app.sidebar_selected_project_ids.contains("project-1"));
    });
    let initialize=runtime.take();assert_eq!(initialize.kind,"workbenchViewPrefs.update");
    assert_eq!(initialize.payload["prefs"]["groupBy"],"none");
    initialize.respond(Ok(record(true,1,"none")));settle(&runtime,&app,cx);
}

#[gpui::test]
fn view_prefs_initialized_runtime_overrides_shared_but_not_local_fields(cx:&mut TestAppContext) {
    let (app,cx,runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_sidebar_view_prefs(cx)));cx.run_until_parked();
    runtime.take().respond(Ok(record(true,2,"project")));settle(&runtime,&app,cx);
    cx.update(|_,cx|{
        let app=app.read(cx);assert_eq!(app.sidebar_group_by,SidebarGroupBy::Project);
        assert_eq!(app.sidebar_width,412.0);assert!(app.sidebar_expanded_workspace_ids.contains("workspace-1"));
    });
    assert!(runtime.try_take().is_none());
}

#[gpui::test]
fn view_prefs_older_load_cannot_replace_newer_shared_choices(cx:&mut TestAppContext) {
    let (app,cx,runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_sidebar_view_prefs(cx)));cx.run_until_parked();let older=runtime.take();
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_sidebar_view_prefs(cx)));cx.run_until_parked();let newer=runtime.take();
    newer.respond(Ok(record(true,3,"none")));settle(&runtime,&app,cx);
    older.respond(Ok(record(true,2,"project")));settle(&runtime,&app,cx);
    cx.update(|_,cx|assert_eq!(app.read(cx).sidebar_group_by,SidebarGroupBy::None));
}

#[gpui::test]
fn view_prefs_pending_initial_load_cannot_undo_a_later_user_choice(cx:&mut TestAppContext) {
    let (app,cx,runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_sidebar_view_prefs(cx)));cx.run_until_parked();let older=runtime.take();
    cx.update(|_,cx|app.update(cx,|app,cx|app.set_sidebar_group_by(SidebarGroupBy::None,cx)));cx.run_until_parked();
    let write=runtime.take();assert_eq!(write.kind,"workbenchViewPrefs.update");write.respond(Ok(record(true,4,"none")));settle(&runtime,&app,cx);
    older.respond(Ok(record(false,0,"project")));settle(&runtime,&app,cx);
    cx.update(|_,cx|assert_eq!(app.read(cx).sidebar_group_by,SidebarGroupBy::None));
    assert!(runtime.try_take().is_none(),"stale first-load response issued another write");
}

#[gpui::test]
fn view_prefs_runtime_error_uses_local_preferences_without_resaving(cx:&mut TestAppContext) {
    let (app,cx,runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|app.load_sidebar_view_prefs(cx)));cx.run_until_parked();
    runtime.take().respond(Err("controlled unavailable runtime".into()));settle(&runtime,&app,cx);
    cx.update(|_,cx|{
        let app=app.read(cx);assert_eq!(app.sidebar_group_by,SidebarGroupBy::None);
        assert_eq!(app.sidebar_width,412.0);assert!(app.error.is_none());
    });
    assert!(runtime.try_take().is_none());
}

#[gpui::test]
fn view_prefs_shared_update_waits_until_local_save_finishes(cx:&mut TestAppContext) {
    let (app,cx,runtime)=fixture(cx);
    let (release,gate)=async_channel::bounded(1);
    cx.update(|_,cx|app.update(cx,|app,cx|{
        app.workbench_prefs_store=WorkbenchPrefsStore::gated_memory(None,gate);
        app.set_sidebar_group_by(SidebarGroupBy::None,cx);
    }));cx.run_until_parked();settle(&runtime,&app,cx);
    let premature=runtime.take_with_timeout(std::time::Duration::from_millis(100));
    let sent_early=premature.is_some();
    if let Some(request)=premature {request.respond(Ok(record(true,1,"none")));}
    release.try_send(()).unwrap();cx.run_until_parked();
    if !sent_early {let request=runtime.take();assert_eq!(request.kind,"workbenchViewPrefs.update");request.respond(Ok(record(true,1,"none")));}
    settle(&runtime,&app,cx);
    assert!(!sent_early,"runtime notification could arrive before local preferences were saved");
    let store=cx.update(|_,cx|app.read(cx).workbench_prefs_store.clone());
    assert_eq!(futures::executor::block_on(store.load()).unwrap()["groupBy"],"none");
}
