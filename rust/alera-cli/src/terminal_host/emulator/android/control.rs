use bytes::{BufMut as _, BytesMut};

use crate::terminal_host::emulator::contract::{EmulatorFailure, EmulatorResult};

const INJECT_KEYCODE: u8 = 0;
const INJECT_TEXT: u8 = 1;
const INJECT_TOUCH: u8 = 2;
const ACTION_DOWN: u8 = 0;
const ACTION_UP: u8 = 1;
const ACTION_MOVE: u8 = 2;
const POINTER_ID: u64 = u64::MAX;
const BUTTON_PRIMARY: u32 = 1;
const MAX_TEXT_BYTES: usize = 300;

pub fn touch(kind: &str, x: f64, y: f64, width: u32, height: u32) -> EmulatorResult<Vec<u8>> {
    let action = match kind {
        "begin" | "down" => ACTION_DOWN,
        "move" => ACTION_MOVE,
        "end" | "up" => ACTION_UP,
        _ => return Err(EmulatorFailure::invalid("Unknown pointer event type.")),
    };
    let screen_width = u16::try_from(width).map_err(|_| {
        EmulatorFailure::new(
            "provider_incompatible",
            "The Android viewport is wider than scrcpy supports.",
            ["Reduce the emulator display resolution."],
        )
    })?;
    let screen_height = u16::try_from(height).map_err(|_| {
        EmulatorFailure::new(
            "provider_incompatible",
            "The Android viewport is taller than scrcpy supports.",
            ["Reduce the emulator display resolution."],
        )
    })?;
    let px = (x * f64::from(width.saturating_sub(1))).round() as i32;
    let py = (y * f64::from(height.saturating_sub(1))).round() as i32;
    let pressure = if action == ACTION_UP { 0 } else { u16::MAX };
    let mut bytes = BytesMut::with_capacity(32);
    bytes.put_u8(INJECT_TOUCH);
    bytes.put_u8(action);
    bytes.put_u64(POINTER_ID);
    bytes.put_i32(px);
    bytes.put_i32(py);
    bytes.put_u16(screen_width);
    bytes.put_u16(screen_height);
    bytes.put_u16(pressure);
    bytes.put_u32(BUTTON_PRIMARY);
    bytes.put_u32(if action == ACTION_UP {
        0
    } else {
        BUTTON_PRIMARY
    });
    Ok(bytes.to_vec())
}

pub fn text(value: &str) -> EmulatorResult<Vec<u8>> {
    let value = value.as_bytes();
    if value.len() > MAX_TEXT_BYTES {
        return Err(EmulatorFailure::invalid(
            "Android text input is limited to 300 UTF-8 bytes per action.",
        ));
    }
    let len = u32::try_from(value.len()).map_err(|_| {
        EmulatorFailure::invalid("Text input is too large for one emulator action.")
    })?;
    let mut bytes = BytesMut::with_capacity(5 + value.len());
    bytes.put_u8(INJECT_TEXT);
    bytes.put_u32(len);
    bytes.extend_from_slice(value);
    Ok(bytes.to_vec())
}

pub fn key(name: &str, pressed: bool) -> EmulatorResult<Vec<u8>> {
    let keycode = match name {
        "home" => 3,
        "back" => 4,
        "power" => 26,
        "volumeUp" | "volume_up" => 24,
        "volumeDown" | "volume_down" => 25,
        "appSwitcher" | "app_switcher" => 187,
        "menu" => 82,
        "enter" => 66,
        "escape" => 111,
        "delete" | "backspace" => 67,
        "tab" => 61,
        "deleteForward" | "delete_forward" => 112,
        "arrowUp" | "arrow_up" => 19,
        "arrowDown" | "arrow_down" => 20,
        "arrowLeft" | "arrow_left" => 21,
        "arrowRight" | "arrow_right" => 22,
        _ => {
            return Err(EmulatorFailure::unsupported(format!(
                "Android button `{name}` is not supported."
            )))
        }
    };
    let mut bytes = BytesMut::with_capacity(14);
    bytes.put_u8(INJECT_KEYCODE);
    bytes.put_u8(if pressed { ACTION_DOWN } else { ACTION_UP });
    bytes.put_i32(keycode);
    bytes.put_i32(0);
    bytes.put_i32(0);
    Ok(bytes.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn touch_message_matches_scrcpy_wire_size() {
        let bytes = touch("begin", 0.5, 0.25, 1080, 2400).unwrap();
        assert_eq!(bytes.len(), 32);
        assert_eq!(bytes[0], INJECT_TOUCH);
        assert_eq!(bytes[1], ACTION_DOWN);
    }

    #[test]
    fn text_prefix_uses_utf8_byte_count() {
        let bytes = text("é").unwrap();
        assert_eq!(&bytes[1..5], &[0, 0, 0, 2]);
    }

    #[test]
    fn text_respects_scrcpy_message_limit() {
        assert!(text(&"a".repeat(MAX_TEXT_BYTES)).is_ok());
        assert!(text(&"a".repeat(MAX_TEXT_BYTES + 1)).is_err());
    }

    #[test]
    fn interactive_navigation_keys_use_android_keycodes() {
        assert_eq!(&key("tab", true).unwrap()[2..6], &[0, 0, 0, 61]);
        assert_eq!(&key("deleteForward", true).unwrap()[2..6], &[0, 0, 0, 112]);
        assert_eq!(&key("arrowLeft", false).unwrap()[2..6], &[0, 0, 0, 21]);
    }
}
