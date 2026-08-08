use std::borrow::Cow;
use std::collections::BTreeMap;
use std::sync::OnceLock;

use regex::{Captures, Regex};

use crate::assets::AleraAssets;

const ICON_PREFIX: &str = "material-icons/icons/";
const LAYER_PREFIX: &str = "material-icons/layers/";

#[derive(Clone, Debug)]
pub struct MaterialIconLayer {
    pub color: u32,
    pub path: String,
}

pub fn layers(asset: &str) -> Vec<MaterialIconLayer> {
    let path = format!("{ICON_PREFIX}{asset}");
    let Some(bytes) = AleraAssets::raw_bytes(&path) else {
        return Vec::new();
    };
    let source = String::from_utf8_lossy(&bytes);
    let mut colors = BTreeMap::new();
    for captures in paint_attribute_regex().captures_iter(&source) {
        let Some((key, color)) = normalize_color(&captures[2]) else {
            continue;
        };
        colors.insert(key, color);
    }
    colors
        .into_iter()
        .map(|(key, color)| MaterialIconLayer {
            color,
            path: format!("{LAYER_PREFIX}{key}/{asset}"),
        })
        .collect()
}

pub fn load_virtual_layer(path: &str) -> Option<Cow<'static, [u8]>> {
    let virtual_path = path.strip_prefix(LAYER_PREFIX)?;
    let (target, asset) = virtual_path.split_once('/')?;
    let source_path = format!("{ICON_PREFIX}{asset}");
    let bytes = AleraAssets::raw_bytes(&source_path)?;
    let source = String::from_utf8_lossy(&bytes);
    let rendered = paint_attribute_regex().replace_all(&source, |captures: &Captures<'_>| {
        let attribute = &captures[1];
        if normalize_color(&captures[2]).is_some_and(|(key, _)| key == target) {
            format!("{attribute}=\"#ffffff\"")
        } else {
            format!("{attribute}=\"none\"")
        }
    });
    Some(Cow::Owned(rendered.into_owned().into_bytes()))
}

fn paint_attribute_regex() -> &'static Regex {
    static PAINT: OnceLock<Regex> = OnceLock::new();
    PAINT.get_or_init(|| {
        Regex::new(r#"(?i)(fill|stroke)="([^"]+)""#)
            .expect("material icon paint regex must be valid")
    })
}

fn normalize_color(value: &str) -> Option<(String, u32)> {
    let value = value.strip_prefix('#')?;
    let expanded = match value.len() {
        3 => value
            .chars()
            .flat_map(|character| [character, character])
            .collect::<String>(),
        6 => value.to_owned(),
        _ => return None,
    };
    let key = expanded.to_ascii_lowercase();
    let color = u32::from_str_radix(&key, 16).ok()?;
    Some((key, color))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discovers_and_renders_exact_multicolor_layers() {
        let layers = layers("folder-src.svg");
        assert_eq!(layers.len(), 2);
        let green = layers.iter().find(|layer| layer.color == 0x4caf50).unwrap();
        let rendered = load_virtual_layer(&green.path).unwrap();
        let rendered = String::from_utf8(rendered.into_owned()).unwrap();
        assert!(rendered.contains(r##"fill="#ffffff""##));
        assert!(rendered.contains(r#"fill="none""#));
    }
}
