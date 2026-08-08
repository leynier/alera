use gpui::{
    div, App, CursorStyle, IntoElement, ParentElement as _, SharedString, Styled as _, Window,
};
use gpui_component::select::SelectItem;

#[derive(Clone, Debug)]
pub(super) struct SettingsSelectOption {
    value: SharedString,
}

impl SettingsSelectOption {
    pub(super) fn new(value: impl Into<SharedString>) -> Self {
        Self {
            value: value.into(),
        }
    }

    pub(super) fn as_str(&self) -> &str {
        self.value.as_ref()
    }
}

impl SelectItem for SettingsSelectOption {
    type Value = SharedString;

    fn title(&self) -> SharedString {
        self.value.clone()
    }

    fn render(&self, _: &mut Window, _: &mut App) -> impl IntoElement {
        div()
            .w_full()
            .cursor(CursorStyle::PointingHand)
            .child(self.value.clone())
    }

    fn value(&self) -> &Self::Value {
        &self.value
    }
}
