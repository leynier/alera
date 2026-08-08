use gpui::{actions, AnyWindowHandle, App, Entity, Menu, MenuItem, OsAction, SystemMenuType};
use gpui_component::input::{Copy, Cut, Paste, Redo, SelectAll, Undo};

use crate::app::AleraApp;

actions!(
    alera_menu,
    [
        MenuOpenSettings,
        MenuOpenExecutionPlans,
        MenuMinimizeWindow,
        MenuZoomWindow,
        MenuToggleFullScreen,
        MenuQuitApp,
        HideApp,
        HideOtherApps,
        ShowAllApps,
    ]
);

pub fn install(
    app_name: &'static str,
    app: &Entity<AleraApp>,
    window_handle: AnyWindowHandle,
    cx: &mut App,
) {
    let settings_app = app.downgrade();
    cx.on_action(move |_: &MenuOpenSettings, cx| {
        if let Some(app) = settings_app.upgrade() {
            app.update(cx, |app, cx| {
                app.open_settings_dialog_from_menu(cx);
            });
        }
    });
    let plans_app = app.downgrade();
    cx.on_action(move |_: &MenuOpenExecutionPlans, cx| {
        if let Some(app) = plans_app.upgrade() {
            app.update(cx, |app, cx| {
                app.open_execution_plans_from_menu(cx);
            });
        }
    });
    cx.on_action(move |_: &MenuMinimizeWindow, cx| {
        cx.defer(move |cx| {
            let _ = window_handle.update(cx, |_, window, _| window.minimize_window());
        });
    });
    cx.on_action(move |_: &MenuZoomWindow, cx| {
        cx.defer(move |cx| {
            let _ = window_handle.update(cx, |_, window, _| window.zoom_window());
        });
    });
    cx.on_action(move |_: &MenuToggleFullScreen, cx| {
        cx.defer(move |cx| {
            let _ = window_handle.update(cx, |_, window, _| window.toggle_fullscreen());
        });
    });
    cx.on_action(|_: &MenuQuitApp, cx| cx.quit());
    cx.on_action(|_: &HideApp, cx| cx.hide());
    cx.on_action(|_: &HideOtherApps, cx| cx.hide_other_apps());
    cx.on_action(|_: &ShowAllApps, cx| cx.unhide_other_apps());
    cx.set_menus(vec![
        Menu {
            name: app_name.into(),
            items: vec![
                MenuItem::action("Settings", MenuOpenSettings),
                MenuItem::action("Execution Plans", MenuOpenExecutionPlans),
                MenuItem::separator(),
                MenuItem::os_submenu("Services", SystemMenuType::Services),
                MenuItem::separator(),
                MenuItem::action(format!("Hide {app_name}"), HideApp),
                MenuItem::action("Hide Others", HideOtherApps),
                MenuItem::action("Show All", ShowAllApps),
                MenuItem::separator(),
                MenuItem::action(format!("Quit {app_name}"), MenuQuitApp),
            ],
        },
        Menu {
            name: "Edit".into(),
            items: vec![
                MenuItem::os_action("Undo", Undo, OsAction::Undo),
                MenuItem::os_action("Redo", Redo, OsAction::Redo),
                MenuItem::separator(),
                MenuItem::os_action("Cut", Cut, OsAction::Cut),
                MenuItem::os_action("Copy", Copy, OsAction::Copy),
                MenuItem::os_action("Paste", Paste, OsAction::Paste),
                MenuItem::os_action("Select All", SelectAll, OsAction::SelectAll),
            ],
        },
        Menu {
            name: "Window".into(),
            items: vec![
                MenuItem::action("Minimize", MenuMinimizeWindow),
                MenuItem::action("Zoom", MenuZoomWindow),
                MenuItem::action("Enter Full Screen", MenuToggleFullScreen),
            ],
        },
    ]);
}
