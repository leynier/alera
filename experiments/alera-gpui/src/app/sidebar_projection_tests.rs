use gpui::{AppContext as _,Context,Entity,IntoElement,Render,TestAppContext,VisualTestContext,Window,div};

use super::{AleraApp,SidebarGroupBy,SidebarSortBy};
use crate::model::{Project,Workspace,WorkspaceRelation};
use crate::runtime_bridge_test_support::{self,ControlledRuntime};

struct Probe {app:Entity<AleraApp>}
impl Render for Probe {fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl IntoElement{div()}}

fn fixture(cx:&mut TestAppContext)->(Entity<AleraApp>,&mut VisualTestContext,ControlledRuntime) {
    cx.executor().allow_parking();cx.update(gpui_component::init);cx.update(crate::design_system::configure_component_theme);
    let (bridge,runtime)=runtime_bridge_test_support::pair();
    let (host,cx)=cx.add_window_view(|window,cx|Probe{app:cx.new(|cx|AleraApp::new_for_test(bridge,window,cx))});
    let app=cx.update(|_,cx|host.read(cx).app.clone());
    (app,cx,runtime)
}

fn workspace(id:&str,name:&str,main:bool,pinned:bool,date:&str)->Workspace {
    Workspace{id:id.into(),name:name.into(),path:format!("/fixture/{id}"),branch:Some(name.into()),source_branch:None,
        kind:if main{"main"}else{"linked"}.into(),status:"active".into(),updated_at:date.into(),host_id:"local".into(),
        reuses_existing_branch:false,is_pinned:pinned,tag_ids:vec![],tag_names:vec![]}
}
fn project(id:&str,name:&str,workspaces:Vec<Workspace>)->Project {
    Project{id:id.into(),name:name.into(),repo_path:format!("/fixture/{id}"),kind:"gitRepository".into(),updated_at:String::new(),workspaces}
}

#[gpui::test]
fn sidebar_flat_recent_does_not_pin_main_before_newer_workspaces(cx:&mut TestAppContext) {
    let (app,cx,_runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,_|{
        app.sidebar_group_by=SidebarGroupBy::None;app.sidebar_workspace_sort=SidebarSortBy::Recent;
        app.snapshot.projects=vec![project("p","Project",vec![workspace("main","Main",true,false,"2026-08-01T00:00:00Z"),workspace("new","New",false,false,"2026-08-30T00:00:00Z")])];
        let project=&app.snapshot.projects[0];
        let mut pairs=project.workspaces.iter().map(|workspace|(project,workspace)).collect();
        app.sort_sidebar_workspace_pairs(&mut pairs);
        assert_eq!(pairs[0].1.id,"new");
        let mut grouped=project.workspaces.iter().collect();app.sort_sidebar_workspaces(&mut grouped);
        assert_eq!(grouped[0].id,"main");
    }));
}

#[gpui::test]
fn sidebar_pinned_order_is_global_for_none_and_agent_activity(cx:&mut TestAppContext) {
    let (app,cx,_runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,_|{
        app.snapshot.projects=vec![project("p1","Alpha",vec![workspace("z","Zulu",false,true,"")]),project("p2","Zulu",vec![workspace("a","Alpha",false,true,"")])];
        let projects=app.snapshot.projects.iter().collect::<Vec<_>>();
        for (group,sort,expected) in [(SidebarGroupBy::None,SidebarSortBy::Name,vec!["a","z"]),(SidebarGroupBy::Project,SidebarSortBy::Activity,vec!["a","z"]),(SidebarGroupBy::Project,SidebarSortBy::Name,vec!["z","a"])] {
            app.sidebar_group_by=group;app.sidebar_workspace_sort=sort;
            let rows=app.pinned_workspace_groups(&projects,"");
            let ids=rows.iter().flatten().map(|(_,workspace)|workspace.id.as_str()).collect::<Vec<_>>();
            assert_eq!(ids,expected);
        }
    }));
}

#[gpui::test]
fn sidebar_pinned_child_remains_visible_when_parent_is_collapsed_below(cx:&mut TestAppContext) {
    let (app,cx,_runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|{
        app.sidebar_group_by=SidebarGroupBy::None;app.sidebar_repeat_pinned=false;
        app.snapshot.projects=vec![project("p","Project",vec![workspace("root","Root",true,true,""),workspace("child","Child",false,true,"")])];
        app.snapshot.relations=vec![WorkspaceRelation{parent_workspace_id:"root".into(),child_workspace_id:"child".into()}];
        app.sidebar_collapsed_parent_workspace_ids.insert("root".into());
        assert_eq!(app.render_sidebar_rows("",cx).len(),3,"pinned header plus both pinned workspaces");
    }));
}

#[gpui::test]
fn sidebar_search_respects_collapsed_project_and_all_sections(cx:&mut TestAppContext) {
    let (app,cx,_runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|{
        app.sidebar_group_by=SidebarGroupBy::Project;
        app.snapshot.projects=vec![project("p","Project",vec![workspace("target","Target",true,false,"")])];
        app.collapsed_project_ids.insert("p".into());
        assert_eq!(app.render_sidebar_rows("target",cx).len(),1,"search must preserve project collapse");
        app.sidebar_group_by=SidebarGroupBy::None;app.sidebar_repeat_pinned=false;app.sidebar_all_collapsed=true;
        app.snapshot.projects[0].workspaces.push(workspace("pin","Target Pinned",false,true,""));
        assert_eq!(app.render_sidebar_rows("target",cx).len(),3,"pinned header, pinned row and collapsed All header");
    }));
}

#[gpui::test]
fn sidebar_collapsed_stale_cycle_keeps_a_recoverable_root(cx:&mut TestAppContext) {
    let (app,cx,_runtime)=fixture(cx);
    cx.update(|_,cx|app.update(cx,|app,cx|{
        app.sidebar_group_by=SidebarGroupBy::None;
        app.snapshot.projects=vec![project("p","Project",vec![workspace("a","Alpha",false,false,""),workspace("b","Beta",false,false,"")])];
        app.snapshot.relations=vec![WorkspaceRelation{parent_workspace_id:"a".into(),child_workspace_id:"b".into()},WorkspaceRelation{parent_workspace_id:"b".into(),child_workspace_id:"a".into()}];
        app.sidebar_collapsed_parent_workspace_ids.extend(["a".to_owned(),"b".to_owned()]);
        assert_eq!(app.render_sidebar_rows("",cx).len(),1,"collapsed stale cycle must retain a root row");
        app.snapshot.relations.pop();
        assert_eq!(app.render_sidebar_rows("",cx).len(),1,"normal collapsed subtree stays hidden");
        assert_eq!(app.render_sidebar_rows("beta",cx).len(),1,"a filtered parent must not hide a matching child");
    }));
}
