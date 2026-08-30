use gpui::{AnyElement, Context, CursorStyle, FontWeight, InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, div, px, prelude::FluentBuilder as _};
use gpui_component::scroll::ScrollableElement as _;
use serde_json::{Value,json};

use super::{AleraApp,automation_detail_data::{self as data,DetailTab}};
use crate::{design_system::{self,ButtonKind},icons::{AleraIcon,icon,loading_indicator},theme};

impl AleraApp {
    pub(super) fn render_automation_detail_tabs(&self,detail:&Value,cx:&mut Context<Self>)->AnyElement{
        let id=detail["automation"]["id"].as_str().unwrap_or_default().to_owned();
        let selected=self.automation_detail_tab;
        let body=match selected{
            DetailTab::Overview=>self.automation_overview(detail).into_any_element(),
            DetailTab::Runs=>self.automation_runs(detail,cx).into_any_element(),
            DetailTab::Audit=>automation_audit(detail).into_any_element(),
        };
        div().w_full().min_w_0().flex().flex_col().flex_1().min_h_0().mt(px(16.0))
            .child(div().id("automation-detail-tablist").role(Role::TabList).aria_label("Automation Details").w_full().h(px(48.0)).flex_shrink_0().flex().border_b_1().border_color(theme::text_faint())
                .children(DetailTab::ALL.into_iter().enumerate().map(|(index,tab)|{
                    let id=id.clone();let key_id=id.clone();
                    div().id(SharedString::from(format!("automation-detail-tab-{}",tab.label()))).role(Role::Tab).aria_label(tab.label()).aria_selected(tab==selected)
                        .track_focus(&self.automation_detail_tab_focus[index]).tab_stop(tab==selected).flex_1().h_full().flex().items_center().justify_center().cursor(CursorStyle::PointingHand)
                        .on_click(cx.listener(move|this,_,window,cx|{
                            if this.automation_selected_id.as_deref()==Some(id.as_str()){
                                this.automation_detail_tab=tab;this.automation_detail_tab_focus[index].focus(window,cx);cx.notify();
                            }
                        }))
                        .on_key_down(cx.listener(move|this,event:&gpui::KeyDownEvent,window,cx|{
                            if this.automation_selected_id.as_deref()!=Some(key_id.as_str()){return;}
                            let next=match event.keystroke.key.as_str(){"right"=>tab.next(true),"left"=>tab.next(false),_=>return};
                            this.automation_detail_tab=next;
                            let index=DetailTab::ALL.iter().position(|tab|*tab==next).unwrap_or(0);
                            this.automation_detail_tab_focus[index].focus(window,cx);cx.stop_propagation();cx.notify();
                        }))
                        .child(div().relative().h_full().flex().items_center().text_size(px(13.0)).font_weight(FontWeight::MEDIUM).text_color(if tab==selected{theme::text()}else{theme::text_muted()}).child(tab.label())
                            .when(tab==selected,|label|label.child(div().absolute().bottom_0().w_full().h(px(2.0)).bg(theme::accent()))))
                })))
            .child(div().w_full().min_w_0().flex_1().min_h_0().overflow_hidden().child(div().id(SharedString::from(format!("automation-detail-scroll-{id}-{}",selected.label()))).size_full().overflow_y_scrollbar()
                .child(div().w_full().min_w_0().pt(px(12.0)).child(body)))).into_any_element()
    }

    fn automation_overview(&self,detail:&Value)->gpui::Div{
        let automation=&detail["automation"];
        let mut body=div().w_full().min_w_0().flex().flex_col()
            .child(info_panel(data::info_rows(automation)))
            .child(section_title("Prompt Preview"))
            .child(div().w_full().min_w_0().text_size(px(13.0)).child(design_system::AleraSelectableText::new(&self.automation_prompt_selection,automation["promptTemplate"].as_str().unwrap_or_default().to_owned())))
            .child(section_title("Effective Policy"))
            .child(info_panel(detail["effectivePolicies"].as_object().into_iter().flatten().map(|(key,value)|(key.clone(),data::text(value))).collect()))
            .child(section_title("Signature Timeline"));
        let active=detail["runs"].as_array().into_iter().flatten().filter(|run|!data::is_final(run["status"].as_str().unwrap_or_default()));
        let upcoming=detail["occurrences"].as_array().into_iter().flatten().take(5);
        let mut has_entries=false;
        for run in active{
            has_entries=true;
            body=body.child(timeline_row(loading_indicator(16.0,theme::info()),format!("Active Run #{}",data::text(&run["number"])),data::text(&run["status"])));
        }
        for occurrence in upcoming{
            has_entries=true;
            body=body.child(timeline_row(icon(AleraIcon::ListChecks,16.0,theme::text()),occurrence.get("localTime").or_else(||occurrence.get("scheduledAt")).map(data::text).unwrap_or_else(||"Upcoming".into()),"Scheduled occurrence".into()));
        }
        if !has_entries{body=body.child("No active run or upcoming occurrence.");}
        body
    }

    fn automation_runs(&self,detail:&Value,cx:&mut Context<Self>)->gpui::Div{
        let automation_id=detail["automation"]["id"].as_str().unwrap_or_default().to_owned();
        let mut body=div().w_full().min_w_0().flex().flex_col();
        let runs=detail["runs"].as_array().map(Vec::as_slice).unwrap_or_default();
        if runs.is_empty(){return body.child("No runs yet.");}
        for run in runs{
            let status=run["status"].as_str().unwrap_or_default();
            let (symbol,color)=match status{
                "success"=>(AleraIcon::Success,theme::success()),
                "failure"|"timeout"=>(AleraIcon::Error,theme::danger()),
                "blocked"|"cancelled"=>(AleraIcon::Stop,theme::warning()),
                _=>(AleraIcon::Loading,theme::info()),
            };
            let mut actions=div().flex().flex_wrap().gap(px(4.0));
            if let Some(run_id)=run["id"].as_str().filter(|_|!data::is_final(status)){
                for (label,request) in [("Resume","automation.wait"),("Extend","automation.extend"),("Cancel","automation.cancel")]{
                    if label!="Cancel"&&status!="waitingForUser"{continue;}
                    let run_id=run_id.to_owned();let automation_id=automation_id.clone();let identity=run["targetIdentity"].clone();
                    actions=actions.child(design_system::button(SharedString::from(format!("automation-{run_id}-{label}")),label,ButtonKind::Text,self.automation_action_busy)
                        .on_click(cx.listener(move|this,_,_,cx|this.automation_run_action(request,&automation_id,&run_id,&identity,cx))));
                }
            }
            body=body.child(div().w_full().min_w_0().min_h(px(56.0)).flex().items_center()
                .child(div().w(px(24.0)).flex_shrink_0().child(icon(symbol,16.0,color)))
                .child(div().ml(px(12.0)).flex_1().min_w_0().child(format!("#{} · {status}",data::text(&run["number"])))
                    .child(div().text_size(px(12.0)).text_color(theme::text_muted()).child(run.get("summary").filter(|v|!v.is_null()).or_else(||run.get("error").filter(|v|!v.is_null())).or_else(||run.get("trigger")).map(data::text).unwrap_or_default())))
                .child(actions));
        }
        body
    }

    fn automation_run_action(&mut self,request:&'static str,automation_id:&str,run_id:&str,identity:&Value,cx:&mut Context<Self>){
        if self.automation_selected_id.as_deref()!=Some(automation_id)||self.automation_action_busy{return;}
        let run=self.automation_detail.as_ref().and_then(|detail|detail["runs"].as_array()).and_then(|runs|runs.iter().find(|run|run["id"]==run_id));
        let Some(run)=run else{return;};
        let status=run["status"].as_str().unwrap_or_default();
        if run["targetIdentity"]!=*identity||data::is_final(status)||(request!="automation.cancel"&&status!="waitingForUser"){return;}
        let mut payload=json!({"run":run_id,"targetIdentity":identity});
        let message=match request{
            "automation.wait"=>{payload["waiting"]=json!(false);"Waiting run resumed"},
            "automation.extend"=>{payload["seconds"]=json!(3600);"Waiting run extended"},
            "automation.cancel"=>"Automation cancellation requested",
            _=>return,
        };
        self.run_automation_request(request,payload,message,cx);
    }
}

fn section_title(label:&'static str)->gpui::Div{div().mt(px(12.0)).mb(px(8.0)).text_size(px(13.0)).font_weight(FontWeight::MEDIUM).child(label)}

pub(super) fn info_panel(rows:Vec<(String,String)>)->gpui::Div{
    div().debug_selector(||"automation-info-panel".into()).w_full().min_w_0().rounded(px(8.0)).border_1().border_color(theme::border_subtle()).bg(theme::surface_selected())
        .children(rows.into_iter().enumerate().map(|(index,(label,value))|{
            div().w_full().min_w_0().py(px(6.0)).flex().items_start()
                .when(index>0,|row|row.border_t_1().border_color(theme::border_subtle()))
                .child(div().w(px(100.0)).flex_shrink_0().text_size(px(12.0)).text_color(theme::text_muted()).child(label))
                .child(div().flex_1().min_w_0().line_clamp(4).text_size(px(13.0)).child(value))
        }))
}

pub(super) fn detail_frame()->gpui::Stateful<gpui::Div>{
    div().id("automation-detail").flex().flex_col().size_full().min_w_0().min_h_0()
}

#[cfg(all(test,feature="gpui-tests"))]
mod tests{
    use super::*;use gpui::{Render,TestAppContext,Window};
    struct Probe;
    impl Render for Probe{
        fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl gpui::IntoElement{
            div().w(px(400.0)).text_size(px(13.0)).line_height(theme::body_line_height())
                .child(info_panel(vec![("Description".into(),"Unicode á 😀 long value ".repeat(200))]))
        }
    }
    #[gpui::test]
    fn automation_detail_info_panel_constrains_long_values(cx:&mut TestAppContext){
        let (_,cx)=cx.add_window_view(|_,_|Probe);cx.run_until_parked();cx.update(|window,cx|{let _=window.draw(cx);});
        let bounds=cx.debug_bounds("automation-info-panel").unwrap();
        assert_eq!(bounds.size.width,px(400.0));assert!(bounds.size.height<px(100.0),"{:?}",bounds);
    }
}

fn timeline_row(leading:AnyElement,title:String,subtitle:String)->gpui::Div{
    div().w_full().min_w_0().min_h(px(56.0)).flex().items_center().child(div().w(px(24.0)).flex_shrink_0().child(leading))
        .child(div().ml(px(12.0)).flex_1().min_w_0().text_size(px(13.0)).child(title).child(div().text_size(px(12.0)).text_color(theme::text_muted()).child(subtitle)))
}

fn automation_audit(detail:&Value)->gpui::Div{
    let mut body=div().w_full().min_w_0().flex().flex_col();
    let events=detail["audit"].as_array().map(Vec::as_slice).unwrap_or_default();
    if events.is_empty(){return body.child("No audit events yet.");}
    for event in events{
        body=body.child(div().w_full().min_w_0().min_h(px(56.0)).flex().flex_col().justify_center()
            .child(event["action"].as_str().unwrap_or("Event").to_owned())
            .child(div().text_size(px(12.0)).text_color(theme::text_muted()).child(format!("{} · {}",event.get("createdAt").map(data::text).unwrap_or_default(),event.get("actor").map(data::text).unwrap_or_default()))));
    }
    body
}
