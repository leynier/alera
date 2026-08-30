use gpui::{AnyElement, App, AppContext as _, Context, FontWeight, InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, div, px, prelude::FluentBuilder as _};
use gpui_component::{button::{Button, ButtonVariants as _}, menu::{DropdownMenu as _, PopupMenuItem}, scroll::ScrollableElement as _, tooltip::Tooltip};
use serde_json::Value;

use super::{AleraApp, SettingsMasterResizeTarget, automation_catalog_state::{self, AutomationFilter}};
use crate::{design_system::{self, ButtonKind}, icons::{AleraIcon, icon, loading_indicator}, theme};

impl AleraApp {
    pub(super) fn cancel_automation_editor(&mut self, window: &mut gpui::Window, cx: &mut Context<Self>) {
        if self.automation_action_busy { return; }
        self.automation_editor_open = false;
        self.automation_editor = None;
        self.automation_editor_error = None;
        self.automation_dialog_focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn filtered_automations<'a>(&'a self, cx: &App) -> Vec<&'a Value> {
        let query = self.automation_search_input.read(cx).value().trim().to_lowercase();
        self.automations.iter().filter(|item| self.automation_filters.matches(item, &query)).collect()
    }

    pub(super) fn reconcile_automation_selection(&mut self, refresh_detail: bool, cx: &mut Context<Self>) {
        let visible = self.filtered_automations(cx);
        let next = visible.iter().find_map(|item| item["id"].as_str().filter(|id| self.automation_selected_id.as_deref() == Some(id)))
            .or_else(|| visible.first().and_then(|item| item["id"].as_str())).map(str::to_owned);
        if let Some(id) = next {
            if refresh_detail || self.automation_selected_id.as_ref() != Some(&id) { self.load_automation_detail(id, cx); }
        } else {
            self.automation_requests.begin_detail();
            self.automation_selected_id = None;
            self.automation_detail = None;
            self.automation_detail_loading = false;
        }
        cx.notify();
    }

    pub(super) fn render_automation_catalog(&self, cx: &mut Context<Self>) -> AnyElement {
        let header = div().flex().items_center().h(px(24.0)).flex_shrink_0()
            .child(div().mr(px(8.0)).child(icon(AleraIcon::ListChecks, 24.0, theme::text_muted())))
            .child(div().flex_1().text_size(px(16.0)).font_weight(FontWeight::SEMIBOLD).child("Automations"))
            .child(design_system::icon_button("automation-import", "Import", AleraIcon::Download, !self.automation_action_busy, 22.0, None, None)
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Import")).into())
                .on_click(cx.listener(|this, _, _, cx| this.automation_import(cx))))
            .child(design_system::icon_button("automation-export", "Export", AleraIcon::CloudUpload, !self.automation_action_busy, 22.0, None, None)
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Export")).into())
                .on_click(cx.listener(|this, _, _, cx| this.automation_export(cx))))
            .child(design_system::icon_button("automation-close", "Close", AleraIcon::Close, true, 22.0, None, None)
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Close")).into())
                .on_click(cx.listener(|this, _, window, cx| this.close_automations_dialog(window, cx))));
        let body = if self.automations_loading && self.automations.is_empty() {
            div().flex().flex_1().items_center().justify_center().child(loading_indicator(24.0, theme::text_muted())).into_any_element()
        } else if let Some(error) = self.automations_error.clone().filter(|_| self.automations.is_empty()) {
            design_system::empty_state_with_action("automations-load-error", AleraIcon::Error, Some("Automations unavailable".into()), error,
                Some(design_system::button("automation-retry", "Retry", ButtonKind::Filled, false)
                    .on_click(cx.listener(|this, _, _, cx| this.load_automations(cx))).into_any_element())).into_any_element()
        } else {
            self.render_automation_master_detail(cx)
        };
        catalog_frame(header.into_any_element(),body)
            .when_some(self.automations_error.clone().filter(|_| !self.automations.is_empty()), |catalog, error| catalog.child(div().text_size(px(12.0)).text_color(theme::danger()).child(error)))
            .into_any_element()
    }

    fn render_automation_master_detail(&self, cx: &mut Context<Self>) -> AnyElement {
        let visible = self.filtered_automations(cx);
        let list = if self.automations.is_empty() {
            design_system::empty_state_with_action("automations-empty-list", AleraIcon::ListChecks, Some("No automations".into()),
                "Create a schedule to run approved work in a runtime-owned target.".into(), Some(
                    design_system::button("automation-new-empty", "New Automation", ButtonKind::Filled, self.automation_action_busy)
                        .on_click(cx.listener(|this, _, window, cx| this.open_automation_editor(None, window, cx))).into_any_element())).into_any_element()
        } else {
            div().id("automations-list").flex_1().min_h_0().overflow_y_scrollbar().rounded_lg().border_1().border_color(theme::border_subtle()).bg(theme::surface_selected())
                .child(div().p(px(8.0)).flex().flex_col().gap(px(8.0))
                    .child(design_system::text_field(&self.automation_search_input).label("Search").prefix(icon(AleraIcon::Search, 16.0, theme::text_muted()).into_any_element()))
                    .child(self.render_automation_filters(cx)))
                .children(visible.iter().map(|item| self.render_automation_list_row(item, cx)))
                .when(visible.is_empty(), |list| list.child(div().p(px(12.0)).text_size(px(13.0)).text_color(theme::text_muted()).child("No automations match these filters.")))
                .into_any_element()
        };
        let detail = if self.automation_detail_loading {
            div().flex().flex_1().items_center().justify_center().child(loading_indicator(24.0, theme::text_muted())).into_any_element()
        } else if self.automation_selected_id.is_none() {
            design_system::empty_state("automation-selection-empty", AleraIcon::ListChecks, "Select an automation", "Choose an automation to inspect its schedule, target, and runs.").into_any_element()
        } else { self.render_automation_detail(cx) };
        let master = div().w(px(self.automation_master_width)).h_full().flex_shrink_0().min_h_0().flex().flex_col()
            .child(div().flex().items_center().h(px(22.0)).flex_shrink_0().pl(px(4.0)).mb(px(8.0))
                .child(div().flex_1().text_size(px(13.0)).font_weight(FontWeight::SEMIBOLD).child("Automations"))
                .child(design_system::icon_button("automation-new", "New Automation", AleraIcon::Add, !self.automation_action_busy, 22.0, None, None)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("New Automation")).into())
                    .on_click(cx.listener(|this, _, window, cx| this.open_automation_editor(None, window, cx)))))
            .child(list);
        catalog_columns(master.into_any_element(), super::settings_panes::settings_master_resize_handle(SettingsMasterResizeTarget::Automations, cx).into_any_element(), detail).into_any_element()
    }

    fn render_automation_filters(&self, cx: &mut Context<Self>) -> gpui::Div {
        let view = self.automation_requests.view();
        div().flex().flex_wrap().gap(px(8.0))
            .children([AutomationFilter::State, AutomationFilter::Project, AutomationFilter::Profile, AutomationFilter::Tag].map(|filter| {
                let selected = self.automation_filters.0.get(&filter).cloned();
                let options = automation_catalog_state::options(&self.automations, filter);
                let app = cx.entity().downgrade();
                Button::new(SharedString::from(format!("automation-filter-{}", filter.label()))).ghost().compact()
                    .label(selected.clone().unwrap_or_else(|| filter.label().into())).text_size(px(13.0))
                    .child(icon(AleraIcon::ChevronDown, 16.0, theme::text_muted()))
                    .dropdown_menu(move |mut menu, _, _| {
                        for value in std::iter::once(None).chain(options.iter().cloned().map(Some)) {
                            let app = app.clone();
                            let label = value.clone().unwrap_or_else(|| format!("All {}", filter.label()));
                            menu = menu.item(PopupMenuItem::new(label).checked(value == selected).on_click(move |_, _, cx| {
                                let _ = app.update(cx, |this, cx| {
                                    if this.show_automations_dialog && this.automation_requests.view() == view {
                                        this.automation_filters.set(filter, value.clone());
                                        this.reconcile_automation_selection(false, cx);
                                    }
                                });
                            }));
                        }
                        menu
                    })
            }))
            .child(design_system::button("automation-trash-filter", "Trash", if self.automation_include_trashed { ButtonKind::Elevated } else { ButtonKind::Outlined }, false)
                .role(Role::CheckBox).aria_toggled(if self.automation_include_trashed { gpui::Toggled::True } else { gpui::Toggled::False })
                .on_click(cx.listener(|this, _, _, cx| { this.automation_include_trashed = !this.automation_include_trashed; this.load_automations(cx); })))
    }
}

pub(super) fn catalog_columns(master: AnyElement, divider: AnyElement, detail: AnyElement) -> gpui::Div {
    div().w_full().min_w_0().flex().flex_1().min_h_0().child(master).child(divider)
        .child(div().debug_selector(|| "automation-detail-column".into()).flex().flex_1().min_w_0().min_h_0().child(detail))
}

fn catalog_frame(header:AnyElement,body:AnyElement)->gpui::Div{
    div().w_full().min_w_0().flex().flex_col().flex_1().min_h_0().child(header).child(div().mt(px(16.0)).w_full().min_w_0().flex().flex_1().min_h_0().child(body))
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Render, TestAppContext, Window};

    struct CatalogProbe;
    impl Render for CatalogProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            div().w(px(1140.0)).h(px(640.0)).flex().flex_col().child(catalog_columns(
                div().w(px(240.0)).h_full().flex_shrink_0().into_any_element(),
                div().w(px(33.0)).h_full().flex_shrink_0().into_any_element(),
                design_system::empty_state("automation-probe-empty", AleraIcon::ListChecks, "Select an automation", "Choose an automation.").into_any_element()))
        }
    }

    #[gpui::test]
    fn automation_catalog_detail_fills_height_after_resizable_master(cx: &mut TestAppContext) {
        let (_, cx) = cx.add_window_view(|_, _| CatalogProbe);
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let detail = cx.debug_bounds("automation-detail-column").unwrap();
        assert_eq!(detail.left(), px(273.0));
        assert_eq!(detail.size.width, px(867.0));
        assert_eq!(detail.size.height, px(640.0));
    }

    struct PopulatedProbe{selection:gpui_base::TextSelectionHandle}
    impl Render for PopulatedProbe{
        fn render(&mut self,_:&mut Window,_:&mut Context<Self>)->impl gpui::IntoElement{
            let rows=super::super::automation_detail_data::info_rows(&serde_json::json!({"name":"Review","promptTemplate":"Review the current workspace and report the result.","description":"Disposable fixture. Unicode á 😀.","target":{"existingTab":{"workspaceId":"0fcf91b0-e48a-4397-a304-b7115871a2ca"}}}));
            let content=super::super::automation_detail_view::detail_frame()
                .child(div().debug_selector(||"automation-probe-toolbar".into()).w_full().h(px(22.0)).child("Review"))
                .child(div().w_full().flex_1().min_h_0().overflow_y_scrollbar().child(super::super::automation_detail_view::info_panel(rows))
                    .child(design_system::AleraSelectableText::new(&self.selection,"Review the current workspace and report the result."))
                    .child(super::super::automation_detail_view::info_panel(vec![("project".into(),"{projectId: e4419ec8-8543-4a01-bf4d-6034596fa8f3, repoDeclared: false, localApproved: false, restrictive: false, updatedAt: 2026-08-30T17:30:57.313311Z}".into())])));
            div().w(px(1140.0)).h(px(640.0)).flex().flex_col().child(catalog_frame(div().h(px(24.0)).into_any_element(),catalog_columns(
                div().w(px(240.0)).h_full().flex_shrink_0().into_any_element(),div().w(px(33.0)).flex_shrink_0().into_any_element(),content.into_any_element()).into_any_element()))
        }
    }
    #[gpui::test]
    fn automation_catalog_populated_detail_cannot_widen_the_dialog(cx:&mut TestAppContext){
        cx.update(gpui_component::init);cx.update(crate::design_system::configure_component_theme);
        let (_,cx)=cx.add_window_view(|_,cx|PopulatedProbe{selection:gpui_base::TextSelectionHandle::new("",cx)});cx.run_until_parked();cx.update(|window,cx|{let _=window.draw(cx);});
        let toolbar=cx.debug_bounds("automation-probe-toolbar").unwrap();assert!(toolbar.right()<=px(1140.0),"{toolbar:?}");
    }
}
