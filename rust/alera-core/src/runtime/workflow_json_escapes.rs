use std::borrow::Cow;

// yaml-rust2 rejects JSON's UTF-16 surrogate pairs. Classify JSON without building
// a tree, then normalize only paired string escapes. The caller has bounded the
// source bytes and still applies every YAML shape, duplicate and resource check.
pub(super) fn normalize_json_surrogate_pairs(source: &str) -> Cow<'_, str> {
    if !source.contains("\\u") || serde_json::from_str::<serde::de::IgnoredAny>(source).is_err() {
        return Cow::Borrowed(source);
    }
    let bytes = source.as_bytes();
    let mut quoted = false;
    let mut index = 0;
    let mut copied_until = 0;
    let mut normalized = String::new();
    while index < bytes.len() {
        match bytes[index] {
            b'"' => quoted = !quoted,
            b'\\' if quoted => {
                if let Some(value) = surrogate_pair(bytes, index) {
                    normalized.push_str(&source[copied_until..index]);
                    normalized.push(value);
                    index += 12;
                    copied_until = index;
                    continue;
                }
                // An escaped backslash or quote must not start another escape/string.
                index += 2;
                continue;
            }
            _ => {}
        }
        index += 1;
    }
    if copied_until == 0 {
        Cow::Borrowed(source)
    } else {
        normalized.push_str(&source[copied_until..]);
        Cow::Owned(normalized)
    }
}

fn surrogate_pair(bytes: &[u8], index: usize) -> Option<char> {
    let high = unicode_escape(bytes.get(index..index + 6)?)?;
    let low = unicode_escape(bytes.get(index + 6..index + 12)?)?;
    if !(0xd800..=0xdbff).contains(&high) || !(0xdc00..=0xdfff).contains(&low) {
        return None;
    }
    char::from_u32(0x10000 + ((u32::from(high) - 0xd800) << 10) + u32::from(low) - 0xdc00)
}

fn unicode_escape(bytes: &[u8]) -> Option<u16> {
    if !bytes.starts_with(b"\\u") {
        return None;
    }
    u16::from_str_radix(std::str::from_utf8(&bytes[2..]).ok()?, 16).ok()
}
