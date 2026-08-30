use gpui::{AnyElement, Context, FocusHandle, FontWeight, InteractiveElement as _, IntoElement as _, MouseButton, ParentElement as _, Role, StatefulInteractiveElement as _, Styled as _, Toggled, Window, div, px};
use gpui_component::{FocusTrapElement as _, button::{Button,ButtonVariants as _}, menu::{DropdownMenu as _,PopupMenuItem}};
use serde_json::{Value,json};
use uuid::Uuid;

use super::AleraApp;
use crate::{design_system::{self,ButtonKind}, icons::{AleraIcon,icon},theme};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ActionKind { RunNow, Pause }

#[derive(Clone, Copy)]
enum RunToggle { Precheck, DraftTest, ExactRevision }

#[derive(Clone)]
struct RunChoice { precheck:bool, draft_test:bool, exact_revision:bool, overlap:String }

impl Default for RunChoice {
    fn default()->Self{Self{precheck:true,draft_test:false,exact_revision:false,overlap:"skip".into()}}
}

impl RunChoice {
    fn toggle(&mut self,toggle:RunToggle){
        match toggle {
            RunToggle::Precheck=>self.precheck=!self.precheck,
            RunToggle::DraftTest=>{self.draft_test=!self.draft_test;if self.draft_test{self.exact_revision=false;}},
            RunToggle::ExactRevision=>{self.exact_revision=!self.exact_revision;if self.exact_revision{self.draft_test=false;}},
        }
    }
    fn payload(&self,id:&str,revision:i64)->Value{
        let mut value=json!({"id":id,"precheck":self.precheck,"overlap":self.overlap,"draftTest":self.draft_test});
        if self.exact_revision{value["revision"]=json!(revision);}
        value
    }
}

pub(super) struct AutomationActionDialog {
    nonce:Uuid,
    automation_id:String,
    revision:i64,
    kind:ActionKind,
    choice:RunChoice,
    focus:FocusHandle,
    previous_focus:Option<FocusHandle>,
}

impl AutomationActionDialog {
    fn matches(&self,nonce:Uuid,selected:Option<&str>,record:&Value)->bool{
        self.nonce==nonce&&record_matches(&self.automation_id,self.revision,self.kind,selected,record)
    }
}

impl AleraApp {
    pub(super) fn open_automation_action_choice(&mut self,id:String,revision:i64,kind:ActionKind,window:&mut Window,cx:&mut Context<Self>){
        if self.automation_action_busy||!self.show_automations_dialog||self.automation_editor_open||self.automation_action_dialog.is_some(){return;}
        let Some(record)=self.automation_detail.as_ref().map(|detail|&detail["automation"]).filter(|record|record["id"]==id) else{return;};
        if self.automation_selected_id.as_deref()!=Some(id.as_str())||record["revision"].as_i64()!=Some(revision)||(kind==ActionKind::Pause&&record["state"]!="active"){return;}
        let previous_focus=window.focused(cx);let focus=cx.focus_handle();focus.focus(window,cx);
        self.automation_action_dialog=Some(AutomationActionDialog{nonce:Uuid::new_v4(),automation_id:id,revision,kind,choice:RunChoice::default(),focus,previous_focus});cx.notify();
    }

    pub(super) fn cancel_automation_action_choice(&mut self,window:&mut Window,cx:&mut Context<Self>)->bool{
        let Some(dialog)=self.automation_action_dialog.take()else{return false;};
        dialog.previous_focus.unwrap_or_else(||self.automation_dialog_focus.clone()).focus(window,cx);cx.notify();true
    }

    fn edit_run_choice(&mut self,nonce:Uuid,edit:impl FnOnce(&mut RunChoice),cx:&mut Context<Self>){
        if self.automation_action_busy{return;}
        if let Some(dialog)=&mut self.automation_action_dialog{if dialog.nonce==nonce{edit(&mut dialog.choice);cx.notify();}}
    }

    fn submit_automation_action_choice(&mut self,nonce:Uuid,active_runs:Option<&'static str>,window:&mut Window,cx:&mut Context<Self>){
        if self.automation_action_busy||!self.show_automations_dialog{return;}
        let Some(dialog)=&self.automation_action_dialog else{return;};
        let valid=self.automation_detail.as_ref().is_some_and(|detail|dialog.matches(nonce,self.automation_selected_id.as_deref(),&detail["automation"]));
        if !valid{
            self.cancel_automation_action_choice(window,cx);
            self.automations_error=Some("This automation changed while the action dialog was open. Review it and try again.".into());cx.notify();return;
        }
        let (request,payload,message)=match dialog.kind{
            ActionKind::RunNow=>("automation.runNow",dialog.choice.payload(&dialog.automation_id,dialog.revision),"Automation run started"),
            ActionKind::Pause=>{
                let Some(policy @ ("continue-active"|"cancel-active"))=active_runs else{return;};
                ("automation.pause",json!({"id":dialog.automation_id,"activeRuns":policy}),"Automation paused")
            }
        };
        self.cancel_automation_action_choice(window,cx);
        self.run_automation_request(request,payload,message,cx);
    }

    pub(super) fn render_automation_action_choice(&self,cx:&mut Context<Self>)->AnyElement{
        let Some(dialog)=&self.automation_action_dialog else{return div().into_any_element();};
        let nonce=dialog.nonce;
        let title=if dialog.kind==ActionKind::RunNow{"Run Now"}else{"Pause Automation"};
        let mut body=div().w_full().flex().flex_col();
        let mut footer=div().mt(px(24.0)).flex().justify_end().items_center().gap(px(8.0));
        if dialog.kind==ActionKind::RunNow{
            for (label,toggle,selected) in [("Run Precheck",RunToggle::Precheck,dialog.choice.precheck),("Audited Draft Test",RunToggle::DraftTest,dialog.choice.draft_test),("Approve Exact Revision",RunToggle::ExactRevision,dialog.choice.exact_revision)]{
                body=body.child(div().id(label).role(Role::Switch).aria_label(label).aria_toggled(if selected{Toggled::True}else{Toggled::False})
                    .focusable().tab_stop(true).min_h(px(40.0)).px(px(16.0)).flex().items_center().gap(px(16.0))
                    .on_click(cx.listener(move|this,_,_,cx|this.edit_run_choice(nonce,|choice|choice.toggle(toggle),cx)))
                    .on_key_down(cx.listener(move|this,event:&gpui::KeyDownEvent,_,cx|{if matches!(event.keystroke.key.as_str(),"space"|"enter"){this.edit_run_choice(nonce,|choice|choice.toggle(toggle),cx);cx.stop_propagation();}}))
                    .child(div().flex_1().min_w_0().text_size(px(13.0)).child(label))
                    .child(super::automation_editor_view::notification_switch(selected,true)));
            }
            let current=dialog.choice.overlap.clone();let app=cx.entity().downgrade();
            body=body.child(div().relative().mt(px(4.0)).child(Button::new("run-now-overlap").accessibility_label(format!("Overlap: {}",overlap_label(&current))).ghost().w_full().h(px(48.0)).px(px(16.0)).border_1().border_color(theme::border()).bg(theme::surface_selected())
                .child(div().flex_1().text_size(px(14.0)).child(overlap_label(&current))).child(icon(AleraIcon::ArrowDropDown,24.0,theme::text_muted()))
                .dropdown_menu(move|mut menu,_,_|{
                    menu=menu.min_w(px(256.0)).max_w(px(256.0));
                    for (value,label) in OVERLAP_OPTIONS{let app=app.clone();menu=menu.item(PopupMenuItem::new(*label).checked(current==*value).on_click(move|_,_,cx|{let _=app.update(cx,|this,cx|this.edit_run_choice(nonce,|choice|choice.overlap=(*value).into(),cx));}));}menu
                }))
                .child(div().absolute().top(px(-6.0)).left(px(12.0)).text_size(px(8.25)).bg(theme::surface_selected()).text_color(theme::text_muted()).child("Overlap")));
            footer=footer.child(design_system::button("run-choice-cancel","Cancel",ButtonKind::Text,false).on_click(cx.listener(move|this,_,window,cx|{if this.automation_action_dialog.as_ref().is_some_and(|dialog|dialog.nonce==nonce){this.cancel_automation_action_choice(window,cx);}})))
                .child(design_system::button("run-choice-submit","Run",ButtonKind::Filled,false).on_click(cx.listener(move|this,_,window,cx|this.submit_automation_action_choice(nonce,None,window,cx))));
        }else{
            body=body.child("Choose what to do with active runs.");
            footer=footer.child(design_system::button("pause-choice-continue","Continue Active",ButtonKind::Text,false).on_click(cx.listener(move|this,_,window,cx|this.submit_automation_action_choice(nonce,Some("continue-active"),window,cx))))
                .child(design_system::button("pause-choice-cancel-active","Cancel Active",ButtonKind::Filled,false).on_click(cx.listener(move|this,_,window,cx|this.submit_automation_action_choice(nonce,Some("cancel-active"),window,cx))));
        }
        div().absolute().inset_0().occlude().flex().items_center().justify_center().bg(theme::overlay_scrim())
            .on_mouse_down(MouseButton::Left,cx.listener(move|this,_,window,cx|{if this.automation_action_dialog.as_ref().is_some_and(|dialog|dialog.nonce==nonce){this.cancel_automation_action_choice(window,cx);}}))
            .child(div().id("automation-action-dialog").role(Role::Dialog).aria_label(title).w(px(if dialog.kind==ActionKind::RunNow{304.0}else{420.0})).max_w_full()
                .on_mouse_down(MouseButton::Left,|_,_,cx|cx.stop_propagation()).p(px(24.0)).rounded(px(12.0)).bg(theme::surface())
                .child(div().flex().flex_col().child(div().text_size(px(16.0)).line_height(px(24.0)).font_weight(FontWeight::SEMIBOLD).child(title)).child(div().mt(px(12.0)).child(body)).child(footer)
                    .focus_trap("automation-action-focus",&dialog.focus))).into_any_element()
    }
}

const OVERLAP_OPTIONS:&[(&str,&str)]=&[("skip","Skip"),("queue","Queue"),("runLatestOnce","Run Latest Once"),("forceParallel","Force Parallel")];
fn overlap_label(value:&str)->String{OVERLAP_OPTIONS.iter().find(|(id,_)|*id==value).map(|(_,label)|(*label).into()).unwrap_or_else(||value.into())}

fn record_matches(id:&str,revision:i64,kind:ActionKind,selected:Option<&str>,record:&Value)->bool{
    selected==Some(id)&&record["id"]==id&&record["revision"].as_i64()==Some(revision)&&(kind!=ActionKind::Pause||record["state"]=="active")
}

#[cfg(test)]
mod tests{
    use super::*;
    #[test]
    fn automation_run_choice_keeps_draft_test_and_exact_approval_exclusive(){
        let mut choice=RunChoice::default();assert_eq!(choice.payload("id",7),json!({"id":"id","precheck":true,"overlap":"skip","draftTest":false}));
        choice.toggle(RunToggle::ExactRevision);assert_eq!(choice.payload("id",7)["revision"],7);
        choice.toggle(RunToggle::DraftTest);assert!(choice.draft_test);assert!(!choice.exact_revision);assert!(choice.payload("id",7).get("revision").is_none());
        choice.toggle(RunToggle::ExactRevision);assert!(!choice.draft_test);assert!(choice.exact_revision);
        choice.overlap="queue".into();choice.toggle(RunToggle::Precheck);assert_eq!(choice.payload("id",7)["precheck"],false);assert_eq!(choice.payload("id",7)["overlap"],"queue");
    }
    #[test]
    fn automation_action_choice_rejects_changed_selection_revision_and_pause_state(){
        let active=json!({"id":"a","revision":7,"state":"active"});
        assert!(record_matches("a",7,ActionKind::Pause,Some("a"),&active));
        assert!(!record_matches("a",6,ActionKind::RunNow,Some("a"),&active));
        assert!(!record_matches("a",7,ActionKind::RunNow,Some("b"),&active));
        assert!(!record_matches("a",7,ActionKind::Pause,Some("a"),&json!({"id":"a","revision":7,"state":"paused"})));
        assert!(!record_matches("a",7,ActionKind::RunNow,Some("a"),&Value::Null));
    }
}
