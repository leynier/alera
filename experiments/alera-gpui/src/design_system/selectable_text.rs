use gpui::{App, Bounds, Element, ElementId, GlobalElementId, Hitbox, InspectorElementId, IntoElement, LayoutId, Pixels, Point, SharedString, StyledText, Window};
use gpui_base::{TextSelectionHandle, TextSelectionRegistration, TextSelectionRun};

pub struct AleraSelectableText {
    selection: TextSelectionHandle,
    text: SharedString,
    styled: StyledText,
}

impl AleraSelectableText {
    pub fn new(selection: &TextSelectionHandle, text: impl Into<SharedString>) -> Self {
        let text=text.into();
        Self{selection:selection.clone(),styled:StyledText::new(text.clone()),text}
    }
}

impl IntoElement for AleraSelectableText {
    type Element=Self;
    fn into_element(self)->Self{self}
}

impl Element for AleraSelectableText {
    type RequestLayoutState=();
    type PrepaintState=Hitbox;
    fn id(&self)->Option<ElementId>{Some(("alera-selectable-text",self.selection.entity_id()).into())}
    fn source_location(&self)->Option<&'static std::panic::Location<'static>>{None}
    fn request_layout(&mut self,id:Option<&GlobalElementId>,inspector:Option<&InspectorElementId>,window:&mut Window,cx:&mut App)->(LayoutId,()){
        self.styled.request_layout(id,inspector,window,cx)
    }
    fn prepaint(&mut self,id:Option<&GlobalElementId>,inspector:Option<&InspectorElementId>,bounds:Bounds<Pixels>,_:&mut (),window:&mut Window,cx:&mut App)->Hitbox{
        self.styled.prepaint(id,inspector,bounds,&mut (),window,cx);
        let selection=self.selection.clone();
        window.use_keyed_state(("alera-selection-refresh",self.selection.entity_id()),cx,move|window,cx|selection.refresh_window_on_change(window,cx));
        let hitbox=window.insert_hitbox(bounds,gpui::HitboxBehavior::Normal);
        self.selection.register(TextSelectionRegistration::new(hitbox.clone(),bounds).with_text_bounds(vec![bounds]),window,cx);
        hitbox
    }
    fn paint(&mut self,id:Option<&GlobalElementId>,inspector:Option<&InspectorElementId>,bounds:Bounds<Pixels>,_:&mut (),_:&mut Hitbox,window:&mut Window,cx:&mut App){
        let layout=self.styled.layout().clone();
        let projection=self.selection.update_runs(&[TextSelectionRun::new(self.text.clone(),layout.clone(),bounds)],cx);
        if let Some(range)=projection.ranges().first().and_then(Clone::clone).filter(|range|!range.is_empty()){
            if let (Some(start),Some(end))=(layout.position_for_index(range.start),layout.position_for_index(range.end)){
                for bounds in selection_quads(start,end,layout.bounds(),layout.line_height()){
                    window.paint_quad(gpui::PaintQuad{bounds,background:crate::theme::ui_text_selection().into(),corner_radii:Default::default(),border_widths:Default::default(),border_color:gpui::transparent_black(),border_style:Default::default()});
                }
            }
        }
        self.styled.paint(id,inspector,bounds,&mut (),&mut (),window,cx);
    }
}

fn selection_quads(start:Point<Pixels>,end:Point<Pixels>,bounds:Bounds<Pixels>,line_height:Pixels)->Vec<Bounds<Pixels>>{
    if start.y==end.y{return vec![Bounds::from_corners(Point::new(start.x.min(end.x),start.y),Point::new(start.x.max(end.x),end.y+line_height))];}
    let mut quads=vec![Bounds::from_corners(start,Point::new(bounds.right(),start.y+line_height))];
    if end.y>start.y+line_height{quads.push(Bounds::from_corners(Point::new(bounds.left(),start.y+line_height),Point::new(bounds.right(),end.y)));}
    quads.push(Bounds::from_corners(Point::new(bounds.left(),end.y),Point::new(end.x,end.y+line_height)));quads
}

#[cfg(all(test,feature="gpui-tests"))]
mod tests{
    use super::*;
    use gpui::{AppContext as _,Context,Modifiers,MouseButton,ParentElement as _,Render,Styled as _,TestAppContext,div,point,px};
    struct Probe{selection:TextSelectionHandle}
    impl Render for Probe{
        fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl IntoElement{
            div().w(gpui::px(500.0)).h(gpui::px(50.0)).text_size(gpui::px(13.0))
                .child(AleraSelectableText::new(&self.selection,"**not markup** á 😀"))
        }
    }
    #[gpui::test]
    fn automation_prompt_plain_selection_preserves_markup_and_unicode(cx:&mut TestAppContext){
        cx.update(gpui_component::init);
        let (_,cx)=cx.add_window_view(|window,cx|{
            let content=cx.new(|cx|Probe{selection:TextSelectionHandle::new("",cx)});
            gpui_component::Root::new(content,window,cx)
        });
        cx.run_until_parked();cx.update(|window,cx|{let _=window.draw(cx);});
        cx.simulate_mouse_down(point(px(1.0),px(8.0)),MouseButton::Left,Modifiers::default());
        cx.simulate_mouse_move(point(px(490.0),px(8.0)),Some(MouseButton::Left),Modifiers::default());
        cx.simulate_mouse_up(point(px(490.0),px(8.0)),MouseButton::Left,Modifiers::default());
        cx.update(|window,cx|{let _=window.draw(cx);});
        assert_eq!(cx.update(|window,cx|gpui_base::TextSelection::selected_text(window,cx)).trim(),"**not markup** á 😀");
    }
    #[test]
    fn automation_prompt_selection_paints_wrapped_lines_without_gaps(){
        let bounds=Bounds::from_corners(point(px(10.0),px(10.0)),point(px(200.0),px(100.0)));
        let quads=selection_quads(point(px(30.0),px(10.0)),point(px(40.0),px(50.0)),bounds,px(20.0));
        assert_eq!(quads.len(),3);assert_eq!(quads[0].right(),px(200.0));assert_eq!(quads[1].top(),quads[0].bottom());assert_eq!(quads[2].top(),quads[1].bottom());
    }
}
