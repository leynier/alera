use std::collections::BTreeMap;
use gpui::{App, AppContext as _, Context, Entity, Subscription, Window};
use gpui_component::input::{InputEvent, InputState, TextareaState};
use uuid::Uuid;

use super::automation_form::{AutomationForm, Field};

pub(super) enum EditorInput { Line(Entity<InputState>), Area(Entity<TextareaState>) }

impl EditorInput {
    pub fn value(&self, cx: &App) -> String { match self { Self::Line(state) => state.read(cx).value().to_string(), Self::Area(state) => state.read(cx).value().to_string() } }
    pub fn set(&self, value: String, window: &mut Window, cx: &mut App) {
        match self {
            Self::Line(state) => state.update(cx, |state, cx| state.set_value(value, window, cx)),
            Self::Area(state) => state.update(cx, |state, cx| state.set_value(value, window, cx)),
        }
    }
}

pub(super) struct AutomationEditor {
    pub epoch: Uuid,
    pub form: AutomationForm,
    pub inputs: BTreeMap<Field, EditorInput>,
    pub profiles: Vec<(String, String)>,
    pub profiles_loading: bool,
    pub selects: super::automation_editor_select::AutomationSelects,
    _subscriptions: Vec<Subscription>,
}

impl AutomationEditor {
    pub fn new<T: 'static>(form: AutomationForm, window: &mut Window, cx: &mut Context<T>) -> Self {
        let mut subscriptions = Vec::new();
        let inputs = Field::ALL.iter().map(|field| {
            let value = form.fields.get(field).cloned().unwrap_or_else(|| field.default_value().into());
            let input = if field.rows() == 1 {
                let state = cx.new(|cx| InputState::new(window, cx).default_value(value));
                subscriptions.push(cx.subscribe_in(&state, window, |_, _, _: &InputEvent, _, cx| cx.notify()));
                EditorInput::Line(state)
            } else {
                let state = cx.new(|cx| TextareaState::new(window, cx).soft_wrap(true).auto_grow(field.rows(), field.rows()));
                state.update(cx, |state, cx| state.set_value(value, window, cx));
                subscriptions.push(cx.subscribe_in(&state, window, |_, _, _: &InputEvent, _, cx| cx.notify()));
                EditorInput::Area(state)
            };
            (*field, input)
        }).collect();
        Self { epoch: Uuid::new_v4(), form, inputs, profiles: Vec::new(), profiles_loading: false, selects: super::automation_editor_select::AutomationSelects::new(cx), _subscriptions: subscriptions }
    }

    pub fn snapshot(&self, cx: &App) -> AutomationForm {
        let mut form = self.form.clone();
        for (field, input) in &self.inputs { form.set(*field, input.value(cx)); }
        form
    }
    pub fn text(&self, field: Field, cx: &App) -> String {
        self.inputs.get(&field).map(|input| input.value(cx)).unwrap_or_else(|| field.default_value().into())
    }
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{IntoElement as _, InteractiveElement as _, ParentElement as _, Render, Styled as _, TestAppContext, div, px};
    use serde_json::json;

    struct Probe { editor: AutomationEditor }
    impl Render for Probe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            div().w(px(520.0)).flex().flex_col().children(self.editor.inputs.iter().map(|(field,input)| match input {
                EditorInput::Line(input) => crate::design_system::text_field(input).label(field.label()).into_any_element(),
                EditorInput::Area(input) => {
                    let name = field.label();
                    div().debug_selector(move || name.into()).child(crate::design_system::AleraTextArea::new(input,name)).into_any_element()
                },
            }))
        }
    }

    #[gpui::test]
    fn automation_form_inputs_draw_all_fields_and_keep_unicode_in_separate_drafts(cx: &mut TestAppContext) {
        cx.update(gpui_component::init);
        cx.update(crate::design_system::configure_component_theme);
        let form = AutomationForm::from_definition(&json!({"name":"Revisión 😀","description":"one\ntwo\nthree","promptTemplate":"á {{workspace.name}}"}),"2030-01-01T00:00:00Z");
        let (view,cx) = cx.add_window_view(|window,cx|Probe{editor:AutomationEditor::new(form,window,cx)});
        cx.run_until_parked();
        cx.update(|window,cx|{let _=window.draw(cx);});
        assert_eq!(cx.debug_bounds("Description").unwrap().size.height,px(75.0));
        assert_eq!(cx.debug_bounds("Prompt Template").unwrap().size.height,px(117.0));
        cx.update(|window,cx|view.update(cx,|view,cx|{
            assert_eq!(view.editor.inputs.len(),Field::ALL.len());
            view.editor.inputs.get(&Field::Name).unwrap().set("Edited á".into(),window,cx);
            let snapshot=view.editor.snapshot(cx);
            assert_eq!(snapshot.text(Field::Name),"Edited á");
            assert_eq!(snapshot.text(Field::Prompt),"á {{workspace.name}}");
            assert_eq!(snapshot.text(Field::Description),"one\ntwo\nthree");
            let next=AutomationForm::from_definition(&json!({"name":"Another"}),"2030-01-01T00:00:00Z");
            view.editor=AutomationEditor::new(next,window,cx);
            assert_eq!(view.editor.snapshot(cx).text(Field::Name),"Another");
            assert_eq!(view.editor.snapshot(cx).text(Field::Description),"");
        }));
        cx.run_until_parked();
    }
}
