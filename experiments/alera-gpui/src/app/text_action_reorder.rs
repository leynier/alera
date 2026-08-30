use gpui::{Context, IntoElement, ParentElement as _, Render, Styled as _, Window, div, px};

use super::{AleraApp, TextActionSetting};
use crate::{design_system, icons::{AleraIcon, icon}, theme};

#[derive(Clone)]
pub(super) struct TextActionDrag {
    pub id: String,
    pub name: String,
    pub enabled: bool,
    pub width: f32,
    pub order: std::sync::Arc<Vec<String>>,
}

impl Render for TextActionDrag {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div().w(px(self.width)).h(px(52.0)).px(px(8.0)).flex().items_center().gap(px(4.0))
            .bg(theme::surface_selected()).shadow_lg()
            .child(icon(AleraIcon::DragHandle, 16.0, theme::text_faint()))
            .child(div().flex_1().min_w_0().text_ellipsis().text_size(px(13.0)).child(self.name.clone()))
            .child(div().w(px(60.0)).h(px(40.0)).flex().items_center().justify_center().child(design_system::switch(self.enabled, false)))
            .child(icon(AleraIcon::Duplicate, 16.0, theme::text_muted()))
    }
}

impl AleraApp {
    pub(super) fn reorder_text_action(&mut self, drag: &TextActionDrag, target: &str, cx: &mut Context<Self>) {
        if self.settings_state.loading || !drag.order.iter().map(String::as_str).eq(self.settings_state.text_actions.iter().map(|action| action.id.as_str())) { return; }
        if move_action(&mut self.settings_state.text_actions, &drag.id, target) {
            self.persist_text_actions(cx);
            cx.notify();
        }
    }
}

fn move_action(actions: &mut Vec<TextActionSetting>, source: &str, target: &str) -> bool {
    let Some(from) = actions.iter().position(|action| action.id == source) else { return false; };
    let Some(to) = actions.iter().position(|action| action.id == target) else { return false; };
    if from == to { return false; }
    let action = actions.remove(from);
    actions.insert(to, action);
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_action_reorder_keeps_identity_and_handles_both_directions() {
        let mut actions = ["a", "b", "c"].map(|id| TextActionSetting { id: id.into(), name: id.into(), prompt: format!("prompt {id}"), ..Default::default() }).to_vec();
        assert!(move_action(&mut actions, "a", "c"));
        assert_eq!(actions.iter().map(|action| action.id.as_str()).collect::<Vec<_>>(), ["b", "c", "a"]);
        assert_eq!(actions[2].prompt, "prompt a");
        assert!(move_action(&mut actions, "a", "b"));
        assert_eq!(actions.iter().map(|action| action.id.as_str()).collect::<Vec<_>>(), ["a", "b", "c"]);
        assert!(!move_action(&mut actions, "missing", "a"));
        assert!(!move_action(&mut actions, "a", "a"));
    }
}
