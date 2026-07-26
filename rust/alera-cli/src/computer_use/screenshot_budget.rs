/// Largest PNG that may reach an agent's context.
pub const MAX_PNG_BYTES: usize = 900_000;
/// Longest edge kept before any byte-budget shrinking starts.
pub const MAX_EDGE: u32 = 1280;
/// Shrink applied per attempt once the image is still too large.
pub const SCALE_STEP: f64 = 0.85;
/// Floor below which a screenshot is no longer worth looking at.
pub const MIN_SCALE: f64 = 0.25;

/// A target size for one capture attempt.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ScaledSize {
    pub width: u32,
    pub height: u32,
    /// Kept size over original size. The agent divides screenshot pixels by this
    /// to get window-local action coordinates.
    pub scale: f64,
}

/// The first size to try for a window of this size.
///
/// A 6K display would otherwise produce an image whose encoding alone costs more
/// than the whole tree it accompanies.
pub fn initial_size(width: u32, height: u32) -> ScaledSize {
    let longest = width.max(height);
    if longest <= MAX_EDGE || longest == 0 {
        return ScaledSize {
            width,
            height,
            scale: 1.0,
        };
    }
    let scale = f64::from(MAX_EDGE) / f64::from(longest);
    scaled(width, height, scale)
}

/// The next size to try after an encode came out too large, or `None` once
/// shrinking further would leave nothing readable.
///
/// Iterating on the encoded size rather than computing it is deliberate: PNG
/// compression depends on the content, so a photo and a text editor of the same
/// pixel size encode to wildly different byte counts.
pub fn next_size(width: u32, height: u32, current: ScaledSize) -> Option<ScaledSize> {
    let scale = current.scale * SCALE_STEP;
    if scale < MIN_SCALE {
        return None;
    }
    let next = scaled(width, height, scale);
    if next.width == 0 || next.height == 0 {
        return None;
    }
    Some(next)
}

/// Whether an encoded image fits the budget.
pub fn fits_budget(encoded_len: usize) -> bool {
    encoded_len <= MAX_PNG_BYTES
}

fn scaled(width: u32, height: u32, scale: f64) -> ScaledSize {
    ScaledSize {
        // Never round down to nothing: a one-pixel image is useless but a
        // zero-pixel one is an encoder error.
        width: ((f64::from(width) * scale).round() as u32).max(1),
        height: ((f64::from(height) * scale).round() as u32).max(1),
        scale,
    }
}

/// The message an agent gets when no size fit.
pub fn budget_exhausted_message() -> String {
    format!(
        "The screenshot still exceeded {MAX_PNG_BYTES} bytes after downscaling to {}% . \
         Retry with no screenshot, or target a smaller window.",
        (MIN_SCALE * 100.0).round()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_small_window_is_captured_at_full_size() {
        let size = initial_size(800, 600);
        assert_eq!(size.width, 800);
        assert_eq!(size.height, 600);
        assert_eq!(size.scale, 1.0);
    }

    #[test]
    fn a_large_window_is_capped_at_the_longest_edge() {
        let size = initial_size(3840, 2160);
        assert_eq!(size.width, MAX_EDGE);
        assert!((size.scale - f64::from(MAX_EDGE) / 3840.0).abs() < 1e-9);
        assert_eq!(size.height, 720);
    }

    #[test]
    fn a_tall_window_is_capped_on_its_own_longest_edge() {
        let size = initial_size(1000, 4000);
        assert_eq!(size.height, MAX_EDGE);
        assert_eq!(size.width, 320);
    }

    /// The scale is what the agent divides by, so a wrong value silently sends
    /// every click to the wrong place.
    #[test]
    fn the_scale_maps_screenshot_pixels_back_to_action_coordinates() {
        let size = initial_size(2560, 1440);
        let pixel_x = 640.0;
        let action_x = pixel_x / size.scale;
        assert!((action_x - 1280.0).abs() < 1.0);
    }

    #[test]
    fn each_attempt_shrinks_by_the_step() {
        let first = initial_size(1000, 800);
        let second = next_size(1000, 800, first).unwrap();
        assert!((second.scale - SCALE_STEP).abs() < 1e-9);
        assert_eq!(second.width, 850);
    }

    #[test]
    fn shrinking_stops_at_the_floor() {
        let mut size = initial_size(1000, 800);
        let mut attempts = 0;
        while let Some(next) = next_size(1000, 800, size) {
            size = next;
            attempts += 1;
            assert!(attempts < 100, "shrinking did not terminate");
        }
        assert!(size.scale >= MIN_SCALE);
        assert!(size.scale * SCALE_STEP < MIN_SCALE);
    }

    /// A zero-pixel image is an encoder error, so the floor must be reached
    /// before any dimension rounds away.
    #[test]
    fn a_sliver_of_a_window_never_scales_to_nothing() {
        let mut size = initial_size(3, 2000);
        while let Some(next) = next_size(3, 2000, size) {
            size = next;
            assert!(size.width >= 1 && size.height >= 1);
        }
    }

    #[test]
    fn the_byte_budget_is_inclusive() {
        assert!(fits_budget(MAX_PNG_BYTES));
        assert!(!fits_budget(MAX_PNG_BYTES + 1));
        assert!(fits_budget(0));
    }

    #[test]
    fn a_zero_sized_window_does_not_divide_by_zero() {
        let size = initial_size(0, 0);
        assert_eq!(size.scale, 1.0);
    }

    #[test]
    fn the_exhausted_message_tells_the_agent_what_to_do_instead() {
        let message = budget_exhausted_message();
        assert!(message.contains("no screenshot"));
        assert!(message.contains("smaller window"));
    }
}
