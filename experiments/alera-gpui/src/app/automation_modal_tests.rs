use std::{cell::Cell,rc::Rc};
use gpui::{AppContext as _,Context,InteractiveElement as _,IntoElement as _,Modifiers,MouseButton,ParentElement as _,Render,Styled as _,TestAppContext,Window,div,point,px};
use gpui_base::{TextSelection,TextSelectionHandle};

struct ModalProbe{selection:TextSelectionHandle,dismissed:Rc<Cell<usize>>}
impl Render for ModalProbe{
    fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl gpui::IntoElement{
        let dismissed=self.dismissed.clone();
        div().size_full().child(super::automations::automation_modal_surface(true,"Editor",div().debug_selector(||"modal-selection-prompt".into()).w_full().h(px(40.0))
            .child(crate::design_system::AleraSelectableText::new(&self.selection,"Automation plain á 😀")).into_any_element(),move|_,_,_|dismissed.set(dismissed.get()+1)))
    }
}

#[gpui::test]
fn automation_modal_allows_plain_selection_without_dismissing(cx:&mut TestAppContext){
    cx.update(gpui_component::init);
    let dismissed=Rc::new(Cell::new(0));let counter=dismissed.clone();
    let (_,cx)=cx.add_window_view(|window,cx|{
        let content=cx.new(|cx|ModalProbe{selection:TextSelectionHandle::new("",cx),dismissed:counter});
        gpui_component::Root::new(content,window,cx)
    });
    cx.run_until_parked();cx.update(|window,cx|{let _=window.draw(cx);});
    let bounds=cx.debug_bounds("modal-selection-prompt").unwrap();
    let start=bounds.origin+point(px(1.0),px(8.0));let end=point(bounds.right()-px(1.0),start.y);
    cx.simulate_mouse_down(start,MouseButton::Left,Modifiers::default());
    cx.simulate_mouse_move(end,Some(MouseButton::Left),Modifiers::default());
    cx.simulate_mouse_up(end,MouseButton::Left,Modifiers::default());
    cx.update(|window,cx|{let _=window.draw(cx);});
    assert_eq!(cx.update(|window,cx|TextSelection::selected_text(window,cx)).trim(),"Automation plain á 😀");
    assert_eq!(dismissed.get(),0);
    cx.simulate_click(point(px(1.0),px(1.0)),Modifiers::default());
    assert_eq!(dismissed.get(),1);
}

struct NestedProbe{dismissals:Rc<Cell<usize>>}
impl Render for NestedProbe{
    fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl gpui::IntoElement{
        let lower=self.dismissals.clone();let upper=self.dismissals.clone();
        div().size_full()
            .child(super::automations::automation_modal_surface(false,"Catalog",div().into_any_element(),move|_,_,_|lower.set(lower.get()+10)))
            .child(super::automations::automation_modal_surface(true,"Editor",div().into_any_element(),move|_,_,_|upper.set(upper.get()+1)))
    }
}

#[gpui::test]
fn automation_modal_outside_click_only_dismisses_the_top_layer(cx:&mut TestAppContext){
    cx.update(gpui_component::init);
    let dismissals=Rc::new(Cell::new(0));let counter=dismissals.clone();
    let (_,cx)=cx.add_window_view(|window,cx|{let content=cx.new(|_|NestedProbe{dismissals:counter});gpui_component::Root::new(content,window,cx)});
    cx.run_until_parked();cx.update(|window,cx|{let _=window.draw(cx);});
    cx.simulate_click(point(px(1.0),px(1.0)),Modifiers::default());
    assert_eq!(dismissals.get(),1);
}
