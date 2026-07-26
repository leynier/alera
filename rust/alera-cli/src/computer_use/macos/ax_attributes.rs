//! Reading one attribute off an accessibility element.
//!
//! Every value the tree needs comes through `AXUIElementCopyAttributeValue`,
//! which hands back an untyped Core Foundation object. Keeping the casting in one
//! place means the tree reader never touches a raw pointer.

use objc2_application_services::{AXUIElement, AXValue, AXValueType};
use objc2_core_foundation::{
    CFArray, CFBoolean, CFNumber, CFRetained, CFString, CFType, CGPoint, CGRect, CGSize,
};

use crate::computer_use::snapshot_contract::Rect;

/// Fetch one attribute, or nothing when the element does not have it.
///
/// A missing attribute is the normal case rather than an error: most elements
/// implement a handful of the dozens that exist.
pub fn attribute(element: &AXUIElement, name: &str) -> Option<CFRetained<CFType>> {
    let key = CFString::from_str(name);
    let mut value: *const CFType = std::ptr::null();
    // SAFETY: `key` outlives the call, and the out-pointer is a local we own. The
    // callee either writes a retained value or leaves it untouched and returns a
    // non-zero error.
    let error = unsafe { element.copy_attribute_value(&key, std::ptr::NonNull::from(&mut value)) };
    if error.0 != 0 || value.is_null() {
        return None;
    }
    // SAFETY: a successful call returns a +1 retained object, which we adopt.
    Some(unsafe { CFRetained::from_raw(std::ptr::NonNull::new(value.cast_mut())?) })
}

pub fn string_attribute(element: &AXUIElement, name: &str) -> Option<String> {
    let value = attribute(element, name)?;
    value.downcast_ref::<CFString>().map(CFString::to_string)
}

pub fn bool_attribute(element: &AXUIElement, name: &str) -> Option<bool> {
    let value = attribute(element, name)?;
    value.downcast_ref::<CFBoolean>().map(|flag| flag.value())
}

/// A numeric attribute rendered as text, for values an agent reads rather than
/// computes with, such as a slider's position.
pub fn number_as_string(element: &AXUIElement, name: &str) -> Option<String> {
    let value = attribute(element, name)?;
    if let Some(number) = value.downcast_ref::<CFNumber>() {
        return number.as_f64().map(|value| value.to_string());
    }
    if let Some(flag) = value.downcast_ref::<CFBoolean>() {
        return Some(flag.value().to_string());
    }
    None
}

/// The children of an element, in the order an element path indexes them.
pub fn element_children(element: &AXUIElement) -> Vec<CFRetained<AXUIElement>> {
    let Some(value) = attribute(element, "AXChildren") else {
        return Vec::new();
    };
    let Some(array) = value.downcast_ref::<CFArray>() else {
        return Vec::new();
    };
    let mut children = Vec::new();
    for index in 0..array.count() {
        // SAFETY: index is bounded by the array's own count.
        let raw = unsafe { array.value_at_index(index) };
        if raw.is_null() {
            continue;
        }
        let Some(pointer) = std::ptr::NonNull::new(raw.cast::<AXUIElement>().cast_mut()) else {
            continue;
        };
        // SAFETY: CFArray gives a borrowed reference, so it is retained before
        // being handed out with an independent lifetime.
        children.push(unsafe { CFRetained::retain(pointer) });
    }
    children
}

/// The window-local frame of an element.
///
/// macOS reports position and size as separate `AXValue` boxes in screen
/// coordinates, so the window rectangle is subtracted here to produce the
/// window-local frame the rest of the surface promises.
pub fn element_frame(element: &AXUIElement, window_bounds: Option<Rect>) -> Option<Rect> {
    let position = point_attribute(element, "AXPosition")?;
    let size = size_attribute(element, "AXSize")?;
    let rect = Rect::new(position.x, position.y, size.width, size.height);
    if rect.is_empty() {
        return None;
    }
    Some(match window_bounds {
        Some(bounds) => rect.to_window_local(&bounds),
        None => rect,
    })
}

/// An element's rectangle in screen coordinates, used for the window itself.
pub fn screen_rect(element: &AXUIElement) -> Option<Rect> {
    let position = point_attribute(element, "AXPosition")?;
    let size = size_attribute(element, "AXSize")?;
    let rect = Rect::new(position.x, position.y, size.width, size.height);
    (!rect.is_empty()).then_some(rect)
}

fn point_attribute(element: &AXUIElement, name: &str) -> Option<CGPoint> {
    let value = attribute(element, name)?;
    let boxed = value.downcast_ref::<AXValue>()?;
    let mut point = CGPoint { x: 0.0, y: 0.0 };
    // SAFETY: the type tag matches the out-parameter, which the callee fills.
    let ok = unsafe {
        boxed.value(
            AXValueType::CGPoint,
            std::ptr::NonNull::from(&mut point).cast(),
        )
    };
    ok.then_some(point)
}

fn size_attribute(element: &AXUIElement, name: &str) -> Option<CGSize> {
    let value = attribute(element, name)?;
    let boxed = value.downcast_ref::<AXValue>()?;
    let mut size = CGSize {
        width: 0.0,
        height: 0.0,
    };
    // SAFETY: as above; the tag and the out-parameter agree.
    let ok = unsafe {
        boxed.value(
            AXValueType::CGSize,
            std::ptr::NonNull::from(&mut size).cast(),
        )
    };
    ok.then_some(size)
}

/// Kept for the rect-typed attributes some elements expose directly.
pub fn rect_attribute(element: &AXUIElement, name: &str) -> Option<Rect> {
    let value = attribute(element, name)?;
    let boxed = value.downcast_ref::<AXValue>()?;
    let mut rect = CGRect {
        origin: CGPoint { x: 0.0, y: 0.0 },
        size: CGSize {
            width: 0.0,
            height: 0.0,
        },
    };
    // SAFETY: as above.
    let ok = unsafe {
        boxed.value(
            AXValueType::CGRect,
            std::ptr::NonNull::from(&mut rect).cast(),
        )
    };
    ok.then(|| {
        Rect::new(
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height,
        )
    })
}

/// The action names an element offers, as the tree lists them.
pub fn action_names(element: &AXUIElement) -> Vec<String> {
    let mut names: *const CFArray = std::ptr::null();
    // SAFETY: the out-pointer is a local we own; on success it holds a retained
    // array which is adopted below.
    let error = unsafe { element.copy_action_names(std::ptr::NonNull::from(&mut names)) };
    if error.0 != 0 || names.is_null() {
        return Vec::new();
    }
    let Some(pointer) = std::ptr::NonNull::new(names.cast_mut()) else {
        return Vec::new();
    };
    // SAFETY: adopting the +1 reference the call returned.
    let array = unsafe { CFRetained::from_raw(pointer) };
    let mut out = Vec::new();
    for index in 0..array.count() {
        // SAFETY: index is bounded by the array's own count.
        let raw = unsafe { array.value_at_index(index) };
        if raw.is_null() {
            continue;
        }
        let string = raw.cast::<CFString>();
        // SAFETY: borrowed from the array, valid for this iteration.
        let name = unsafe { (*string).to_string() };
        if !name.trim().is_empty() {
            out.push(name);
        }
    }
    out
}
