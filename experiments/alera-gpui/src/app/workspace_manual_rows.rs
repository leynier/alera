use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Toggled,
};

use super::AleraApp;
use crate::theme;
use crate::icons::{icon, AleraIcon};

impl AleraApp {
    pub(super) fn manual_workspace_source_required(&self) -> bool {
        let count=if self.workspace_reuse_existing_branch {self.available_local_workspace_branches().len()} else {self.workspace_source_branches.len()};
        manual_source_required(self.workspace_branches_loading,count)
    }

    pub(super) fn reset_manual_workspace_source(&mut self, window:&mut gpui::Window, cx:&mut Context<Self>) {
        self.workspace_manual_source_input.update(cx,|input,cx|input.set_value("",window,cx));
    }

    fn select_manual_workspace_project(&mut self,id:String,window:&mut gpui::Window,cx:&mut Context<Self>) {
        if self.selected_workspace_project_id.as_deref()==Some(id.as_str()) {return;}
        self.reset_manual_workspace_source(window,cx);
        self.select_workspace_project(id,cx);
    }

    pub(super) fn manual_workspace_branch_mode(&self, cx: &mut Context<Self>) -> gpui::Div {
        div().flex().mt(px(16.0)).h(px(32.0)).flex_shrink_0().child(
            div().flex().rounded(px(6.0)).overflow_hidden().border_1().border_color(theme::border())
                .children([(false, "New Branch"), (true, "Existing Branch")].map(|(reuse, label)| {
                    let selected = self.workspace_reuse_existing_branch == reuse;
                    div().id(if reuse {"workspace-existing-branch-mode"} else {"workspace-new-branch-mode"})
                        .focusable().tab_stop(true).role(Role::RadioButton).aria_label(label).aria_selected(selected)
                        .aria_toggled(if selected {Toggled::True} else {Toggled::False})
                        .min_w(px(120.0)).h_full().px(px(12.0)).flex().items_center().justify_center()
                        .text_size(px(13.0)).font_weight(gpui::FontWeight::MEDIUM).cursor(CursorStyle::PointingHand)
                        .text_color(if selected {theme::text()} else {theme::text_muted()})
                        .when(selected,|button|button.bg(theme::surface_raised()))
                        .hover(|style|style.bg(theme::surface_raised()))
                        .on_click(cx.listener(move|this,_,window,cx|this.set_workspace_reuse_existing_branch(reuse,window,cx)))
                        .on_key_down(cx.listener(move|this,event:&gpui::KeyDownEvent,window,cx|{
                            if matches!(event.keystroke.key.as_str(),"enter"|"space") {
                                this.set_workspace_reuse_existing_branch(reuse,window,cx);
                                cx.stop_propagation();
                            }
                        })).child(label)
                })))
    }

    pub(super) fn manual_workspace_project_rows(
        &self,
        query: &str,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        matching_projects(&self.snapshot.projects, query)
            .into_iter()
            .map(|project| {
                let project_id = project.id.clone();
                let keyboard_id = project_id.clone();
                let selected =
                    self.selected_workspace_project_id.as_deref() == Some(project.id.as_str());
                let branch = project
                    .workspaces
                    .iter()
                    .find_map(|workspace| workspace.branch.as_deref())
                    .unwrap_or("HEAD");
                picker_row(
                    format!("workspace-project-choice-{}", project.id).into(),
                    project.name.clone(),
                    Some(format!("{}  •  ({branch})", project.repo_path)),
                    selected,
                )
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.select_manual_workspace_project(project_id.clone(),window,cx);
                    }))
                    .on_key_down(cx.listener(move |this, event: &gpui::KeyDownEvent, window, cx| {
                        if matches!(event.keystroke.key.as_str(), "enter" | "space") {
                            this.select_manual_workspace_project(keyboard_id.clone(),window,cx);
                            cx.stop_propagation();
                        }
                    }))
                    .into_any_element()
            })
            .collect()
    }

    pub(super) fn manual_workspace_branch_rows(
        &self,
        query: &str,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let branches = if self.workspace_reuse_existing_branch {
            self.available_local_workspace_branches()
        } else {
            self.workspace_source_branches.clone()
        };
        branches
            .into_iter()
            .filter(|branch| query.is_empty() || branch.to_lowercase().contains(query))
            .map(|branch| {
                let selected = self.selected_workspace_source_branch.as_deref() == Some(&branch);
                let branch_value = branch.clone();
                let keyboard_branch = branch.clone();
                let default = matches!(
                    branch.as_str(),
                    "main" | "origin/main" | "master" | "origin/master"
                );
                picker_row(format!("workspace-source-branch-{branch}").into(),
                    if default { format!("{branch} (default)") } else { branch }, None, selected)
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.select_manual_workspace_source_branch(
                            branch_value.clone(),
                            window,
                            cx,
                        );
                    }))
                    .on_key_down(cx.listener(move |this, event: &gpui::KeyDownEvent, window, cx| {
                        if matches!(event.keystroke.key.as_str(), "enter" | "space") {
                            this.select_manual_workspace_source_branch(keyboard_branch.clone(), window, cx);
                            cx.stop_propagation();
                        }
                    }))
                    .into_any_element()
            })
            .collect()
    }
}

fn picker_row(id: SharedString, label: String, subtitle: Option<String>, selected: bool) -> gpui::Stateful<gpui::Div> {
    let indicator = if selected { if subtitle.is_some() { AleraIcon::CircleDot } else { AleraIcon::Success } } else { AleraIcon::Circle };
    div().id(id).focusable().tab_stop(true).role(Role::RadioButton)
        .aria_label(label.clone()).aria_selected(selected).aria_toggled(if selected {Toggled::True}else{Toggled::False})
        .w_full().min_w_0().flex().items_start().px(px(8.0)).py(px(6.0)).gap(px(6.0))
        .cursor(CursorStyle::PointingHand).hover(|style|style.bg(theme::surface_raised()))
        .focus_visible(|style|style.border_color(theme::accent()))
        .when(selected,|row|row.bg(theme::accent_subtle()))
        .child(div().debug_selector(||"workspace-picker-indicator".into()).w(px(18.0)).h(px(16.0)).flex_shrink_0()
            .child(if subtitle.is_some() {super::dialogs::radio(selected).into_any_element()} else {icon(indicator,16.0,if selected{theme::accent()}else{theme::text_faint()}).into_any_element()}))
        .child(div().debug_selector(||"workspace-picker-copy".into()).flex_1().min_w_0()
            .child(div().text_size(px(12.0)).line_height(px(16.0)).text_ellipsis()
                .text_color(if selected{theme::text()}else{theme::text_muted()})
                .font_weight(if selected{gpui::FontWeight::SEMIBOLD}else{gpui::FontWeight::NORMAL}).child(label))
            .when_some(subtitle,|copy,subtitle|copy.child(div().mt(px(2.0)).text_size(px(10.0)).line_height(px(16.0))
                .text_color(theme::text_faint()).font_weight(gpui::FontWeight::MEDIUM).text_ellipsis().child(subtitle))))
}

fn matching_projects<'a>(projects: &'a [crate::model::Project], query: &str) -> Vec<&'a crate::model::Project> {
    let query=query.trim().to_lowercase();
    let mut matches:Vec<_>=projects.iter().filter(|project| project.kind == "gitRepository")
        .filter(|project| query.is_empty() || project.name.to_lowercase().contains(&query) || project.repo_path.to_lowercase().contains(&query)).collect();
    matches.sort_by(|left,right|left.name.to_lowercase().cmp(&right.name.to_lowercase())
        .then_with(||left.name.cmp(&right.name)).then_with(||left.id.cmp(&right.id)));
    matches
}

fn manual_source_required(loading:bool,catalog_count:usize)->bool { !loading && catalog_count==0 }

#[cfg(test)]
mod tests {
    use super::*;
    fn project(id: &str, name: &str, path: &str) -> crate::model::Project {
        crate::model::Project {id:id.into(),name:name.into(),repo_path:path.into(),kind:"gitRepository".into(),updated_at:String::new(),workspaces:vec![]}
    }
    #[test]
    fn manual_workspace_projects_match_path_and_use_flutter_tie_breakers() {
        let projects=vec![project("z","clone-origin","/fixtures/clone-gpui"),project("a","clone-origin","/fixtures/clone-flutter"),project("b","Alpha","/fixtures/alpha")];
        let matches=matching_projects(&projects,"  CLONE-GPUI  ");
        assert_eq!(matches.iter().map(|p|p.id.as_str()).collect::<Vec<_>>(),vec!["z"]);
        let ordered=matching_projects(&projects,"");
        assert_eq!(ordered.iter().map(|p|p.id.as_str()).collect::<Vec<_>>(),vec!["b","a","z"]);
    }

    #[test]
    fn manual_workspace_empty_catalog_uses_source_input_but_loading_and_filtering_do_not() {
        assert!(manual_source_required(false,0));
        assert!(!manual_source_required(true,0));
        assert!(!manual_source_required(false,2));
    }

    #[cfg(feature="gpui-tests")]
    struct RowProbe;
    #[cfg(feature="gpui-tests")]
    impl gpui::Render for RowProbe {
        fn render(&mut self,_:&mut gpui::Window,_:&mut Context<Self>)->impl gpui::IntoElement {
            div().w(px(240.0)).child(picker_row("row-probe".into(),"A very long project name á 日本語".repeat(4),
                Some("/Users/review/Application Support/long-project-name/".repeat(8)),true))
        }
    }
    #[cfg(feature="gpui-tests")]
    #[gpui::test]
    fn manual_workspace_picker_bounds_preserve_icon_and_truncate_copy(cx:&mut gpui::TestAppContext) {
        cx.update(gpui_component::init);cx.update(crate::design_system::configure_component_theme);
        let (_,cx)=cx.add_window_view(|_,_|RowProbe);cx.run_until_parked();
        cx.update(|window,cx|{let _=window.draw(cx);});
        let icon=cx.debug_bounds("workspace-picker-indicator").unwrap();
        let copy=cx.debug_bounds("workspace-picker-copy").unwrap();
        assert_eq!(icon.size.width,px(18.0));
        assert_eq!(icon.size.height,px(16.0));
        assert_eq!(copy.left(),px(32.0));
        assert!(copy.right()<=px(232.0),"{copy:?}");
        assert_eq!(copy.size.height,px(34.0));
    }
}
