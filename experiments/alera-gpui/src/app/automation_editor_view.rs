use gpui::{AnyElement, Context, FontWeight, InteractiveElement as _, IntoElement as _, ParentElement as _, Role, StatefulInteractiveElement as _, Styled as _, Toggled, div, px, prelude::FluentBuilder as _};
use gpui_component::scroll::ScrollableElement as _;
use uuid::Uuid;

use super::{AleraApp, automation_editor_state::EditorInput, automation_form::{Choice, Field}};
use crate::{design_system::{self, ButtonKind}, theme};

impl AleraApp {
    pub(super) fn render_automation_editor(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(editor) = &self.automation_editor else { return div().into_any_element(); };
        let epoch = editor.epoch;
        let schedule = editor.form.choice(Choice::Schedule);
        let target = editor.form.choice(Choice::Target);
        let mut fields = vec![self.automation_text(Field::Name), self.automation_text(Field::Slug), self.automation_text(Field::Description),
            self.automation_id_picker(Field::Project, cx), self.automation_text(Field::Tags), self.automation_text(Field::Prompt),
            self.automation_choice(Choice::Schedule, cx), self.automation_text(if schedule == "oneTime" {Field::At} else {Field::Cron}), self.automation_text(Field::Timezone)];
        if schedule == "recurring" { fields.extend([self.automation_text(Field::Start),self.automation_text(Field::End),self.automation_text(Field::MaxRuns)]); }
        fields.extend([self.automation_choice(Choice::Target,cx),self.automation_id_picker(Field::Workspace,cx)]);
        if target == "existingTab" { fields.extend([self.automation_id_picker(Field::Tab,cx),self.automation_text(Field::Conversation)]); }
        else { fields.push(self.automation_id_picker(Field::Profile,cx)); }
        if target == "managedWorkspace" { fields.extend([self.automation_text(Field::Branch),self.automation_text(Field::NameTemplate)]); }
        fields.extend([self.automation_text(Field::Precheck),self.automation_text(Field::PrecheckTimeout),
            form_pair(self.automation_choice(Choice::Setup,cx),self.automation_choice(Choice::Overlap,cx)),
            form_pair(self.automation_choice(Choice::Misfire,cx),self.automation_choice(Choice::Cleanup,cx)),
            self.automation_text(Field::QueueCap),self.automation_text(Field::Inactivity),self.automation_text(Field::Heartbeat),
            form_pair(self.automation_text(Field::RetryAttempts),self.automation_text(Field::RetryBackoff)),
            form_pair(self.automation_text(Field::CircuitThreshold),self.automation_text(Field::CircuitOpen))]);
        let notify = editor.form.notify_on_success;
        let busy = self.automation_action_busy;
        let form = div().w_full().min_w_0().flex().flex_col().gap(px(12.0)).flex_shrink_0().children(fields)
            .child(div().id("automation-notify-success").role(Role::Switch).aria_label("Notify On Success")
                .aria_toggled(if notify {Toggled::True} else {Toggled::False}).focusable().tab_stop(!busy)
                .h(px(40.0)).flex().items_center().gap(px(12.0))
                .on_key_down(cx.listener(move |this,event: &gpui::KeyDownEvent,_,cx| {
                    if matches!(event.keystroke.key.as_str(),"space"|"enter") && this.automation_editor_is_current(epoch) {
                        if let Some(editor)=&mut this.automation_editor {editor.form.notify_on_success=!editor.form.notify_on_success;}
                        cx.stop_propagation(); cx.notify();
                    }
                }))
                .on_click(cx.listener(move |this, _, _, cx| {
                    if this.automation_editor_is_current(epoch) { if let Some(editor) = &mut this.automation_editor { editor.form.notify_on_success = !notify; } cx.notify(); }
                }))
                .child(div().flex_1().child("Notify On Success")).child(notification_switch(notify,!busy)));
        div().flex().flex_col().w_full().min_w_0().flex_1().min_h_0()
            .child(div().text_size(theme::title_size()).font_weight(FontWeight::SEMIBOLD).child(if self.automation_editor_id.is_some(){"Edit Automation"}else{"New Automation"}))
            .child(div().mt(px(16.0)).w_full().min_w_0().flex_1().min_h_0().overflow_hidden()
                .child(div().id("automation-editor-form-scroll").size_full().overflow_y_scrollbar().child(form)))
            .when_some(self.automation_editor_error.clone(),|body,error|body.child(div().id("automation-form-error").role(Role::Alert).aria_label(error.clone()).mt(px(12.0)).text_size(px(13.0)).text_color(theme::danger()).line_clamp(3).child(error)))
            .child(div().mt(px(16.0)).flex().justify_end().items_center().gap(px(8.0))
                .child(design_system::button("cancel-automation-editor","Cancel",ButtonKind::Text,busy).on_click(cx.listener(move |this,_,window,cx| { if this.automation_editor_is_current(epoch) { this.cancel_automation_editor(window,cx); } })))
                .child(design_system::button_with_loading("save-automation-editor",if busy{"Saving"}else{"Save Automation"},ButtonKind::Filled,busy,busy).on_click(cx.listener(move |this,_,window,cx| { if this.automation_editor_is_current(epoch) { this.save_automation_editor(window,cx); } }))))
            .into_any_element()
    }

    pub(super) fn automation_editor_is_current(&self, epoch: Uuid) -> bool {
        self.show_automations_dialog && self.automation_editor_open && !self.automation_action_busy && self.automation_editor.as_ref().is_some_and(|editor| editor.epoch == epoch)
    }

    fn automation_text(&self, field: Field) -> AnyElement {
        let Some(input) = self.automation_editor.as_ref().and_then(|editor|editor.inputs.get(&field)) else { return div().into_any_element(); };
        match input {
            EditorInput::Line(input) => design_system::text_field(input).label(field.label()).disabled(self.automation_action_busy).into_any_element(),
            EditorInput::Area(input) => design_system::AleraTextArea::new(input,field.label()).disabled(self.automation_action_busy).into_any_element(),
        }
    }


}

fn form_pair(left: AnyElement, right: AnyElement) -> AnyElement {
    div().w_full().min_w_0().flex().gap(px(12.0)).child(div().flex_1().min_w_0().child(left)).child(div().flex_1().min_w_0().child(right)).into_any_element()
}

pub(super) fn notification_switch(selected: bool, interactive: bool) -> gpui::Div {
    if !cfg!(target_os="macos") {return design_system::switch(selected,interactive);}
    div().w(px(60.0)).h(px(40.0)).flex().items_center().justify_center()
        .when(interactive,|control|control.cursor(gpui::CursorStyle::PointingHand))
        .child(div().w(px(51.0)).h(px(31.0)).px(px(1.5)).flex().items_center().rounded_full().bg(theme::adaptive_switch_track(selected))
            .child(div().w(px(28.0)).h(px(28.0)).rounded_full().bg(theme::adaptive_switch_thumb()).when(selected,|thumb|thumb.ml_auto())))
}
