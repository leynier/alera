use std::time::Duration;

use gpui::{Context, Entity, Window};
use gpui_component::input::InputState;
use serde_json::{Value, json};

use super::{AleraApp, NewWorkspaceStep};
use super::workspace_actions::deferred_setup_command_from_payload;

impl AleraApp {
    pub(super) fn create_workspace(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.workspace_creation_busy { return; }
        let branch = if self.workspace_reuse_existing_branch {
            self.selected_workspace_source_branch.clone().unwrap_or_default()
        } else { self.workspace_branch_input.read(cx).value().trim().to_string() };
        if branch.is_empty() {
            self.error = Some(if self.workspace_reuse_existing_branch {"Existing branch is required"} else {"New branch name is required"}.into());
            cx.notify(); return;
        }
        if !self.workspace_reuse_existing_branch && self.workspace_source_branches.contains(&branch) {
            self.error = Some(format!("Branch \"{branch}\" already exists").into());
            cx.notify(); return;
        }
        let Some(project_id) = self.selected_workspace_project().map(|project|project.id.clone()) else {
            self.error = Some("No Git project is available".into()); cx.notify(); return;
        };
        let name = self.workspace_name_input.read(cx).value().trim().to_string();
        let request = json!({
            "projectId": project_id,
            "branch": branch,
            "sourceBranch": self.selected_workspace_source_branch.clone().unwrap_or_else(||"main".into()),
            "reuseExistingBranch": self.workspace_reuse_existing_branch,
            "deferSetup": true,
            "name": (!name.is_empty()).then_some(name),
            "parentWorkspaceId": self.workspace_selected_parent_id,
        });
        let create_another = self.create_another_workspace;
        let bridge = self.bridge.clone();
        self.workspace_creation_busy = true;
        self.error = None;
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge.request_with_timeout("workspace.createManaged", request, Duration::from_secs(30*60)).await;
            let _ = this.update_in(cx, |this, window, cx| {
                this.workspace_creation_busy = false;
                match result.and_then(|payload|created_workspace_id(&payload,&project_id).map(|id|(id,payload))) {
                    Ok((workspace_id,payload)) => {
                        this.queue_deferred_workspace_setup(workspace_id.clone(),deferred_setup_command_from_payload(&payload),None);
                        this.show_new_workspace_dialog = create_another;
                        this.error = None;
                        if create_another { this.reset_manual_workspace_after_creation(window,cx); }
                        // Reuse the selection pipeline so the new snapshot owns
                        // editor cleanup, initial terminal creation and cwd.
                        this.select_workspace(workspace_id,cx);
                        this.active_project_id = Some(project_id.clone());
                        this.local_message = Some("Workspace created".into());
                    }
                    Err(error) => { this.error = Some(error.into()); }
                }
                cx.notify();
            });
        }).detach();
    }

    fn reset_manual_workspace_after_creation(&mut self, window:&mut Window, cx:&mut Context<Self>) {
        self.new_workspace_step = NewWorkspaceStep::ManualSettings;
        self.workspace_selected_parent_id = None;
        self.workspace_reuse_existing_branch = false;
        self.workspace_synced_name = None;
        reset_manual_inputs(&self.workspace_branch_search_input,&self.workspace_manual_source_input,
            &self.workspace_branch_input,&self.workspace_name_input,window,cx);
        if let Some(project_id)=self.selected_workspace_project_id.clone() {self.load_workspace_branches(project_id,cx);}
    }
}

fn reset_manual_inputs(search:&Entity<InputState>,source:&Entity<InputState>,branch:&Entity<InputState>,name:&Entity<InputState>,window:&mut Window,cx:&mut gpui::App) {
    for input in [search,source,branch,name] {input.update(cx,|input,cx|input.set_value("",window,cx));}
    branch.update(cx,|input,cx|input.focus(window,cx));
}

fn created_workspace_id(payload:&Value,project_id:&str)->Result<String,String> {
    let workspace=&payload["workspace"];
    if workspace["projectId"].as_str()!=Some(project_id) {return Err("Created workspace response has an unexpected project".into());}
    workspace["id"].as_str().filter(|id|!id.trim().is_empty()).map(str::to_owned)
        .ok_or_else(||"Created workspace response omitted its identity".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn manual_workspace_creation_requires_scoped_runtime_identity() {
        assert_eq!(created_workspace_id(&json!({"workspace":{"id":"child","projectId":"project"}}),"project").unwrap(),"child");
        assert!(created_workspace_id(&json!({"workspace":{"id":"child","projectId":"other"}}),"project").is_err());
        assert!(created_workspace_id(&json!({"workspace":{"projectId":"project"}}),"project").is_err());
        assert!(created_workspace_id(&json!({"workspace":{"id":" ","projectId":"project"}}),"project").is_err());
    }
    #[cfg(feature="gpui-tests")]
    #[gpui::test]
    fn manual_workspace_create_another_clears_fields_and_moves_focus(cx:&mut gpui::TestAppContext) {
        use gpui::{AppContext as _,ParentElement as _,Render,Styled as _};
        struct Probe {fields:[Entity<InputState>;4]}
        impl Render for Probe {
            fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl gpui::IntoElement {
                gpui::div().w(gpui::px(480.0)).child(crate::design_system::text_field(&self.fields[2]))
            }
        }
        cx.update(gpui_component::init);cx.update(crate::design_system::configure_component_theme);
        let (view,cx)=cx.add_window_view(|window,cx|Probe{fields:std::array::from_fn(|_|cx.new(|cx|InputState::new(window,cx)))});
        cx.update(|window,cx|view.update(cx,|view,cx| {
            for field in &view.fields {field.update(cx,|input,cx|input.set_value("previous draft",window,cx));}
            reset_manual_inputs(&view.fields[0],&view.fields[1],&view.fields[2],&view.fields[3],window,cx);
        }));
        cx.run_until_parked();cx.update(|window,cx|{let _=window.draw(cx);});
        cx.simulate_keystrokes("n e w");
        cx.update(|_,cx|{for (index,field) in view.read(cx).fields.iter().enumerate() {
            assert_eq!(field.read(cx).value().as_ref(),if index==2{"new"}else{""});
        }});
    }
}
