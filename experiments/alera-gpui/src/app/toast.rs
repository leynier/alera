use gpui::{div, px, AnyElement, IntoElement as _, ParentElement as _, SharedString, Styled as _};

use crate::icons::{icon, AleraIcon};
use crate::theme;

pub(super) fn render_toast(message: SharedString, stack_index: usize) -> AnyElement {
    let kind = toast_icon(&message);
    let color = match kind {
        AleraIcon::Error => theme::danger(),
        AleraIcon::Success => theme::success(),
        _ => theme::accent(),
    };
    div()
        .absolute()
        .right(px(16.0))
        .bottom(px(40.0 + stack_index as f32 * 58.0))
        .max_w(px(380.0))
        .flex()
        .items_start()
        .gap_2()
        .px_3()
        .py_2()
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_raised())
        .shadow_lg()
        .text_sm()
        .child(icon(kind, 16.0, color))
        .child(div().flex_1().child(message))
        .into_any_element()
}

fn toast_icon(message: &str) -> AleraIcon {
    let normalized = message.to_ascii_lowercase();
    // Flutter keeps clipboard confirmations informational by default in the
    // Explorer and About surfaces. Workspace paths and commit text opt into a
    // success tone at their call sites, so only infer success for the latter
    // instead of treating every message containing "copied" as successful.
    if matches!(
        normalized.as_str(),
        "copied" | "path copied" | "version copied"
    ) {
        return AleraIcon::Info;
    }
    if normalized.contains("error")
        || normalized.contains("failed")
        || normalized.contains("could not")
        || normalized.contains("required")
        || normalized.contains("already exists")
        || normalized.contains("path is ")
        || normalized.contains("outside the workspace")
        || normalized.contains("operation is unsupported")
        || normalized.contains("item not found")
        || normalized.contains("file changed on disk")
        || normalized.contains("operation failed")
    {
        AleraIcon::Error
    } else if normalized.contains("created")
        || normalized.contains("saved")
        || normalized.contains("completed")
        || normalized.contains("generated")
        || normalized.contains("exported")
        || normalized.contains("updated")
        || normalized.contains("copied")
        || normalized.contains("linked")
    {
        AleraIcon::Success
    } else {
        AleraIcon::Info
    }
}

#[cfg(test)]
mod tests {
    use super::toast_icon;
    use crate::icons::AleraIcon;

    #[test]
    fn explorer_errors_use_error_toast_icon() {
        for message in [
            "Item already exists",
            "Path is protected",
            "Path is outside the workspace",
            "Operation is unsupported",
            "Item not found",
            "File changed on disk",
        ] {
            assert_eq!(toast_icon(message), AleraIcon::Error, "{message}");
        }
    }

    #[test]
    fn diagnostics_export_uses_success_toast_icon() {
        assert_eq!(toast_icon("Diagnostics exported."), AleraIcon::Success);
    }

    #[test]
    fn generic_clipboard_toasts_keep_flutter_info_tone() {
        for message in ["Copied", "Path Copied", "Version Copied"] {
            assert_eq!(toast_icon(message), AleraIcon::Info, "{message}");
        }
        assert_eq!(toast_icon("Workspace Path Copied"), AleraIcon::Success);
        assert_eq!(toast_icon("Commit Hash Copied"), AleraIcon::Success);
    }
}
