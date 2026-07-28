use serde_json::json;

use super::super::contract::{EmulatorFailure, EmulatorResult, GesturePoint};

const TOUCH_TAG: u8 = 0x03;
const BUTTON_TAG: u8 = 0x04;
const KEYBOARD_TAG: u8 = 0x06;
const ROTATE_TAG: u8 = 0x07;
const SHIFT_USAGE: u16 = 225;

pub fn touch(point: &GesturePoint, fallback_kind: &str) -> EmulatorResult<Vec<u8>> {
    tagged_json(
        TOUCH_TAG,
        &json!({
            "type": point.kind.as_deref().unwrap_or(fallback_kind),
            "x": point.x,
            "y": point.y,
            if point.edge.is_some() { "edge" } else { "_edge" }: point.edge,
        }),
    )
}

pub fn pointer(kind: &str, x: f64, y: f64) -> EmulatorResult<Vec<u8>> {
    if !matches!(kind, "begin" | "move" | "end") {
        return Err(EmulatorFailure::invalid("Unknown pointer event type."));
    }
    tagged_json(TOUCH_TAG, &json!({"type": kind, "x": x, "y": y}))
}

pub fn button(name: &str) -> EmulatorResult<Vec<u8>> {
    let name = match name {
        "home" => "home",
        "appSwitcher" | "app_switcher" => "app_switcher",
        "power" | "lock" => "lock",
        _ => {
            return Err(EmulatorFailure::unsupported(format!(
                "iOS button `{name}` is not supported."
            )))
        }
    };
    tagged_json(BUTTON_TAG, &json!({"button": name}))
}

pub fn rotate(orientation: &str) -> EmulatorResult<Vec<u8>> {
    let normalized = match orientation {
        "portrait" => "portrait",
        "portraitUpsideDown" | "portrait_upside_down" => "portrait_upside_down",
        "landscapeLeft" | "landscape_left" => "landscape_left",
        "landscapeRight" | "landscape_right" => "landscape_right",
        _ => return Err(EmulatorFailure::invalid("Unknown iOS orientation.")),
    };
    tagged_json(ROTATE_TAG, &json!({"orientation": normalized}))
}

pub fn text(value: &str) -> EmulatorResult<Vec<Vec<u8>>> {
    if value.len() > 16 * 1024 {
        return Err(EmulatorFailure::invalid(
            "iOS text input is limited to 16384 UTF-8 bytes per action.",
        ));
    }
    let mut frames = Vec::new();
    for character in value.chars() {
        if character == '\r' {
            continue;
        }
        let (usage, shift) = hid_usage(character).ok_or_else(|| {
            EmulatorFailure::unsupported(format!(
                "iOS typing does not support character `{character}` with the US keyboard."
            ))
        })?;
        if shift {
            frames.push(keyboard("down", SHIFT_USAGE)?);
        }
        frames.push(keyboard("down", usage)?);
        frames.push(keyboard("up", usage)?);
        if shift {
            frames.push(keyboard("up", SHIFT_USAGE)?);
        }
    }
    Ok(frames)
}

pub fn key(name: &str, pressed: bool) -> EmulatorResult<Vec<u8>> {
    let usage = match name {
        "enter" => 0x28,
        "escape" => 0x29,
        "backspace" => 0x2a,
        "tab" => 0x2b,
        "deleteForward" | "delete_forward" => 0x4c,
        "arrowRight" | "arrow_right" => 0x4f,
        "arrowLeft" | "arrow_left" => 0x50,
        "arrowDown" | "arrow_down" => 0x51,
        "arrowUp" | "arrow_up" => 0x52,
        _ => {
            return Err(EmulatorFailure::unsupported(format!(
                "iOS key `{name}` is not supported."
            )))
        }
    };
    keyboard(if pressed { "down" } else { "up" }, usage)
}

fn keyboard(kind: &str, usage: u16) -> EmulatorResult<Vec<u8>> {
    tagged_json(KEYBOARD_TAG, &json!({"type": kind, "usage": usage}))
}

fn tagged_json(tag: u8, value: &serde_json::Value) -> EmulatorResult<Vec<u8>> {
    let json = serde_json::to_vec(value).map_err(|error| {
        EmulatorFailure::new(
            "invalid_argument",
            format!("Could not encode emulator input: {error}"),
            ["Retry with valid input."],
        )
    })?;
    let mut frame = Vec::with_capacity(json.len() + 1);
    frame.push(tag);
    frame.extend_from_slice(&json);
    Ok(frame)
}

fn hid_usage(character: char) -> Option<(u16, bool)> {
    if character.is_ascii_alphabetic() {
        let lower = character.to_ascii_lowercase() as u8;
        return Some((u16::from(lower - b'a') + 4, character.is_ascii_uppercase()));
    }
    if character.is_ascii_digit() {
        let usage = if character == '0' {
            39
        } else {
            u16::from(character as u8 - b'1') + 30
        };
        return Some((usage, false));
    }
    Some(match character {
        '\n' => (40, false),
        '\t' => (43, false),
        ' ' => (44, false),
        '-' => (45, false),
        '_' => (45, true),
        '=' => (46, false),
        '+' => (46, true),
        '[' => (47, false),
        '{' => (47, true),
        ']' => (48, false),
        '}' => (48, true),
        '\\' => (49, false),
        '|' => (49, true),
        ';' => (51, false),
        ':' => (51, true),
        '\'' => (52, false),
        '"' => (52, true),
        '`' => (53, false),
        '~' => (53, true),
        ',' => (54, false),
        '<' => (54, true),
        '.' => (55, false),
        '>' => (55, true),
        '/' => (56, false),
        '?' => (56, true),
        '!' => (30, true),
        '@' => (31, true),
        '#' => (32, true),
        '$' => (33, true),
        '%' => (34, true),
        '^' => (35, true),
        '&' => (36, true),
        '*' => (37, true),
        '(' => (38, true),
        ')' => (39, true),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn touch_frames_use_serve_sim_tag() {
        let frame = pointer("begin", 0.5, 0.75).unwrap();
        assert_eq!(frame[0], TOUCH_TAG);
        assert!(String::from_utf8_lossy(&frame[1..]).contains("\"x\":0.5"));
    }

    #[test]
    fn uppercase_typing_wraps_key_with_shift() {
        let frames = text("A").unwrap();
        assert_eq!(frames.len(), 4);
        assert!(String::from_utf8_lossy(&frames[0]).contains("\"usage\":225"));
    }

    #[test]
    fn platform_neutral_buttons_map_to_serve_sim_names() {
        let app_switcher = button("appSwitcher").unwrap();
        assert!(String::from_utf8_lossy(&app_switcher).contains("app_switcher"));
        let power = button("power").unwrap();
        assert!(String::from_utf8_lossy(&power).contains("\"lock\""));
        assert!(button("back").is_err());
    }

    #[test]
    fn interactive_navigation_keys_use_hid_usages() {
        let enter = key("enter", true).unwrap();
        assert!(String::from_utf8_lossy(&enter[1..]).contains("\"usage\":40"));
        let left = key("arrowLeft", false).unwrap();
        assert!(String::from_utf8_lossy(&left[1..]).contains("\"usage\":80"));
    }
}
