use std::{cell::Cell, collections::BTreeMap, rc::Rc};
use gpui::{AnyElement, Bounds, Context, CursorStyle, FocusHandle, InteractiveElement as _, IntoElement as _, ParentElement as _, Pixels, Role, ScrollHandle, SharedString, StatefulInteractiveElement as _, Styled as _, Window, anchored, canvas, deferred, div, point, px, prelude::FluentBuilder as _};
use uuid::Uuid;

use super::{AleraApp, automation_form::{Choice, Field}};
use crate::{icons::{AleraIcon,icon}, theme};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub(super) enum Selection { Choice(Choice), Field(Field) }
impl Selection {
    fn all() -> impl Iterator<Item=Self> {
        Choice::ALL.iter().copied().map(Self::Choice).chain([Field::Project,Field::Workspace,Field::Tab,Field::Profile].map(Self::Field))
    }
}

pub(super) struct SelectField {
    focus: FocusHandle,
    bounds: Rc<Cell<Bounds<Pixels>>>,
}

pub(super) struct AutomationSelects {
    fields: BTreeMap<Selection,SelectField>,
    menu_focus: FocusHandle,
    scroll: ScrollHandle,
    menu: Option<SelectMenu>,
}

struct SelectMenu {
    id: Uuid,
    selection: Selection,
    label: &'static str,
    options: Vec<(String,String)>,
    index: usize,
    initial_index: usize,
    max_height: Pixels,
}

impl AutomationSelects {
    pub fn new(cx:&gpui::App) -> Self {
        Self { fields:Selection::all().map(|selection|(selection,SelectField{focus:cx.focus_handle(),bounds:Rc::default()})).collect(), menu_focus:cx.focus_handle(), scroll:ScrollHandle::new(), menu:None }
    }
}

impl AleraApp {
    pub(super) fn automation_choice(&self, choice: Choice, cx:&mut Context<Self>) -> AnyElement {
        let current=self.automation_editor.as_ref().map(|editor|editor.form.choice(choice)).unwrap_or(choice.default_value()).to_owned();
        self.automation_select(Selection::Choice(choice),choice.label(),current,choice.options().iter().map(|(id,label)|(id.to_string(),label.to_string())).collect(),false,cx)
    }

    pub(super) fn automation_id_picker(&self, field:Field,cx:&mut Context<Self>) -> AnyElement {
        let Some(editor)=&self.automation_editor else{return div().into_any_element();};
        let project=editor.text(Field::Project,cx);
        let workspace=editor.text(Field::Workspace,cx);
        let options=match field {
            Field::Project=>std::iter::once((String::new(),"None".into())).chain(self.snapshot.projects.iter().map(|project|(project.id.clone(),project.name.clone()))).collect(),
            Field::Workspace=>self.snapshot.projects.iter().filter(|item|project.trim().is_empty()||item.id==project.trim()).flat_map(|project|project.workspaces.iter().map(|workspace|(workspace.id.clone(),workspace.name.clone()))).collect(),
            Field::Tab=>self.snapshot.all_tabs.iter().filter(|tab|tab.workspace_id==workspace.trim()).map(|tab|(tab.id.clone(),tab.title.clone())).collect(),
            Field::Profile=>editor.profiles.clone(),
            _=>Vec::new(),
        };
        let label=if field==Field::Workspace&&editor.form.choice(Choice::Target)=="managedWorkspace"{"Source Workspace"}else{field.label()};
        self.automation_select(Selection::Field(field),label,editor.text(field,cx).trim().to_owned(),options,field==Field::Profile&&editor.profiles_loading,cx)
    }

    fn automation_select(&self,selection:Selection,label:&'static str,current:String,mut options:Vec<(String,String)>,loading:bool,cx:&mut Context<Self>) -> AnyElement {
        let Some(editor)=&self.automation_editor else{return div().into_any_element();};
        let Some(field)=editor.selects.fields.get(&selection) else{return div().into_any_element();};
        let epoch=editor.epoch;
        let expanded=editor.selects.menu.as_ref().is_some_and(|menu|menu.selection==selection);
        if !options.iter().any(|(id,_)|id==&current){options.push((current.clone(),if current.is_empty(){"Select...".into()}else{current.clone()}));}
        let text=options.iter().find(|(id,_)|id==&current).map(|(_,label)|label.clone()).unwrap_or_default();
        let geometry=field.bounds.clone();
        let enabled=!self.automation_action_busy&&!loading;
        let keyboard_options=options.clone();let keyboard_current=current.clone();
        let trigger=div().id(SharedString::from(format!("automation-select-{epoch}-{label}"))).role(Role::ComboBox).aria_expanded(expanded)
            .aria_label(format!("{label}: {text}")).focusable().tab_stop(enabled).track_focus(&field.focus)
            .w_full().h(px(48.0)).px(px(16.0)).flex().items_center().gap(px(8.0)).rounded(px(6.0)).border_1().border_color(theme::border()).bg(theme::surface_selected())
            .when(enabled,|field|field.cursor(CursorStyle::PointingHand))
            .child(div().min_w_0().flex_1().text_ellipsis().text_size(px(14.0)).child(text))
            .child(icon(AleraIcon::ArrowDropDown,24.0,theme::text_muted()))
            .on_key_down(cx.listener(move|this,event:&gpui::KeyDownEvent,window,cx|{
                if enabled&&matches!(event.keystroke.key.as_str(),"space"|"enter"|"down"|"up") {
                    this.open_automation_select(epoch,selection,label,keyboard_current.clone(),keyboard_options.clone(),window,cx);
                    cx.stop_propagation();
                }
            }))
            .on_click(cx.listener(move|this,_,window,cx|{
                if !enabled||!this.automation_editor_is_current(epoch){return;}
                if expanded{this.close_automation_select(window,cx);return;}
                this.open_automation_select(epoch,selection,label,current.clone(),options.clone(),window,cx);
            }));
        div().relative().w_full().min_w_0().child(trigger)
            .child(canvas(move|bounds,window,_|{if geometry.replace(bounds)!=bounds&&expanded{window.request_animation_frame();}},|_,_,_,_|{}).absolute().top_0().left_0().size_full())
            .child(div().absolute().top(px(-6.0)).left(px(8.0)).px(px(4.0)).text_size(px(8.25)).line_height(px(12.0)).text_color(theme::text_muted())
                .child(div().absolute().left_0().right_0().top(px(6.0)).h(px(1.0)).bg(theme::surface_selected())).child(label))
            .when(expanded,|container|container.child(self.render_automation_select_menu(cx))).into_any_element()
    }

    fn open_automation_select(&mut self,epoch:Uuid,selection:Selection,label:&'static str,current:String,options:Vec<(String,String)>,window:&mut Window,cx:&mut Context<Self>){
        if !self.automation_editor_is_current(epoch){return;}
        let Some(editor)=&mut self.automation_editor else{return;};
        let index=options.iter().position(|(id,_)|id==&current).unwrap_or(0);
        editor.selects.scroll.set_offset(point(px(0.0),px(0.0)));
        editor.selects.scroll.scroll_to_item(index);
        editor.selects.menu=Some(SelectMenu{id:Uuid::new_v4(),selection,label,options,index,initial_index:index,max_height:(window.viewport_size().height-px(96.0)).max(px(48.0))});
        editor.selects.menu_focus.focus(window,cx);cx.notify();
    }

    pub(super) fn close_automation_select(&mut self,window:&mut Window,cx:&mut Context<Self>) -> bool {
        let Some(editor)=&mut self.automation_editor else{return false;};
        let Some(menu)=editor.selects.menu.take() else{return false;};
        if let Some(field)=editor.selects.fields.get(&menu.selection){field.focus.focus(window,cx);}
        cx.notify();true
    }

    fn choose_automation_option(&mut self,epoch:Uuid,menu_id:Uuid,index:usize,window:&mut Window,cx:&mut Context<Self>){
        if !self.automation_editor_is_current(epoch){return;}
        let Some(editor)=&mut self.automation_editor else{return;};
        let Some(menu)=&editor.selects.menu else{return;};
        if !menu.accepts(menu_id){return;}
        let Some((value,_))=menu.options.get(index).cloned() else{return;};
        match menu.selection {
            Selection::Choice(choice)=>{editor.form.choices.insert(choice,value);},
            Selection::Field(field)=>{if let Some(input)=editor.inputs.get(&field){input.set(value,window,cx);}},
        }
        self.automation_editor_error=None;
        self.close_automation_select(window,cx);
    }

    fn automation_select_key(&mut self,event:&gpui::KeyDownEvent,window:&mut Window,cx:&mut Context<Self>){
        let Some(editor)=&mut self.automation_editor else{return;};
        let Some(menu)=&mut editor.selects.menu else{return;};
        let count=menu.options.len();if count==0{return;}
        let epoch=editor.epoch;
        match event.keystroke.key.as_str(){
            "up"=>menu.index=(menu.index+count-1)%count,
            "down"=>menu.index=(menu.index+1)%count,
            "home"=>menu.index=0,
            "end"=>menu.index=count-1,
            "enter"=>{let index=menu.index;let menu_id=menu.id;self.choose_automation_option(epoch,menu_id,index,window,cx);cx.stop_propagation();return;},
            "escape"=>{self.close_automation_select(window,cx);cx.stop_propagation();return;},
            _=>return,
        }
        editor.selects.scroll.scroll_to_item(menu.index);cx.stop_propagation();cx.notify();
    }

    fn render_automation_select_menu(&self,cx:&mut Context<Self>)->AnyElement{
        let Some(editor)=&self.automation_editor else{return div().into_any_element();};
        let Some(menu)=&editor.selects.menu else{return div().into_any_element();};
        let Some(field)=editor.selects.fields.get(&menu.selection) else{return div().into_any_element();};
        let bounds=field.bounds.get();let epoch=editor.epoch;let menu_id=menu.id;
        let menu_bounds=menu_geometry(bounds,menu.initial_index,menu.options.len());
        let position=menu_bounds.origin;
        deferred(anchored().position(position).snap_to_window_with_margin(px(8.0)).child(
            div().id("automation-select-options").role(Role::ListBox).aria_label(format!("{} Options",menu.label)).track_focus(&editor.selects.menu_focus)
                .on_mouse_down(gpui::MouseButton::Left,|_,_,cx|cx.stop_propagation())
                .on_key_down(cx.listener(Self::automation_select_key))
                .on_mouse_down_out(cx.listener(move|this,_,window,cx|{
                    if this.automation_editor_is_current(epoch)&&this.automation_editor.as_ref().and_then(|editor|editor.selects.menu.as_ref()).is_some_and(|menu|menu.accepts(menu_id)) {
                        this.close_automation_select(window,cx);cx.stop_propagation();
                    }
                }))
                .occlude().w(menu_bounds.size.width).max_h(menu.max_height).flex().flex_col().py(px(8.0)).bg(theme::surface()).shadow_lg().track_scroll(&editor.selects.scroll).overflow_y_scroll()
                .children(menu.options.iter().enumerate().map(|(index,(_,label))|{
                    div().id(("automation-select-option",index)).role(Role::ListBoxOption).aria_label(label.clone()).aria_selected(index==menu.index)
                        .h(px(48.0)).flex_shrink_0().px(px(16.0)).flex().items_center().cursor(CursorStyle::PointingHand).text_size(px(14.0))
                        .when(index==menu.index,|row|row.bg(theme::accent_subtle())).hover(|style|style.bg(theme::surface_raised()))
                        .on_click(cx.listener(move|this,_,window,cx|this.choose_automation_option(epoch,menu_id,index,window,cx))).child(label.clone())
                }))
        )).with_priority(3).into_any_element()
    }
}

impl SelectMenu {
    fn accepts(&self,id:Uuid)->bool {self.id==id}
}

fn menu_geometry(trigger:Bounds<Pixels>,selected:usize,count:usize)->Bounds<Pixels>{
    // Flutter's unaligned Material dropdown expands by start16/end24 and
    // centers the selected 48 px row on the field, with 8 px menu padding.
    Bounds::new(point(trigger.left()-px(16.0),trigger.top()-px(8.0+48.0*selected as f32)),gpui::size(trigger.size.width+px(40.0),px(16.0+48.0*count as f32)))
}

#[cfg(test)]
mod tests{
    use super::*;
    #[test]
    fn automation_select_geometry_aligns_selected_row_and_expands_field(){
        let trigger=Bounds::new(point(px(100.0),px(200.0)),gpui::size(px(520.0),px(48.0)));
        let menu=menu_geometry(trigger,1,2);
        assert_eq!(menu.left(),px(84.0));assert_eq!(menu.size.width,px(560.0));
        assert_eq!(menu.top()+px(8.0+48.0+24.0),trigger.center().y);
    }
    #[test]
    fn automation_select_reopening_rejects_old_menu_callbacks(){
        let old=Uuid::new_v4();
        let menu=SelectMenu{id:Uuid::new_v4(),selection:Selection::Choice(Choice::Target),label:"Target",options:vec![],index:0,initial_index:0,max_height:px(300.0)};
        assert!(!menu.accepts(old));assert!(menu.accepts(menu.id));
    }
}
