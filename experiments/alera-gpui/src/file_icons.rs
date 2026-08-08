use std::collections::HashMap;
use std::sync::OnceLock;

use gpui::{div, svg, AnyElement, Div, IntoElement as _, ParentElement as _, Rgba, Styled as _};
use serde::Deserialize;

use crate::icons::{icon, AleraIcon};
use crate::material_icon_layers;

const MANIFEST_JSON: &str = include_str!("../assets/material-icons/manifest.json");
const ASSET_PREFIX: &str = "material-icons/icons/";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MaterialIconManifest {
    file: String,
    folder: String,
    folder_expanded: String,
    file_extensions: HashMap<String, String>,
    file_names: HashMap<String, String>,
    folder_names: HashMap<String, String>,
    folder_names_expanded: HashMap<String, String>,
}

fn manifest() -> &'static MaterialIconManifest {
    static MANIFEST: OnceLock<MaterialIconManifest> = OnceLock::new();
    MANIFEST.get_or_init(|| {
        serde_json::from_str(MANIFEST_JSON).expect("material icon manifest must be valid")
    })
}

pub fn file_icon(
    path_or_name: &str,
    is_directory: bool,
    is_expanded: bool,
    is_symlink: bool,
    size: f32,
    fallback_color: Rgba,
) -> AnyElement {
    if is_symlink {
        return icon(AleraIcon::Link, size, fallback_color).into_any_element();
    }
    let asset = if is_directory {
        directory_asset(path_or_name, is_expanded)
    } else {
        file_asset(path_or_name)
    };
    material_image(asset, size).into_any_element()
}

fn material_image(asset: &str, size: f32) -> Div {
    let layers = material_icon_layers::layers(asset);
    if layers.is_empty() {
        return div().w(gpui::px(size)).h(gpui::px(size)).child(
            svg()
                .path(format!("{ASSET_PREFIX}{asset}"))
                .size_full()
                .text_color(gpui::rgb(0x8b949e)),
        );
    }
    div()
        .relative()
        .w(gpui::px(size))
        .h(gpui::px(size))
        .children(layers.into_iter().map(|layer| {
            svg()
                .path(layer.path)
                .absolute()
                .top_0()
                .left_0()
                .size_full()
                .text_color(gpui::rgb(layer.color))
        }))
}

fn file_asset(path_or_name: &str) -> &str {
    let catalog = manifest();
    let name = icon_name(path_or_name);
    if let Some(asset) = catalog.file_names.get(&name) {
        return asset;
    }
    catalog
        .file_extensions
        .iter()
        .filter(|(extension, _)| name.ends_with(extension.as_str()))
        .max_by_key(|(extension, _)| extension.len())
        .map_or(catalog.file.as_str(), |(_, asset)| asset.as_str())
}

fn directory_asset(path_or_name: &str, is_expanded: bool) -> &str {
    let catalog = manifest();
    let name = icon_name(path_or_name);
    if is_expanded {
        catalog
            .folder_names_expanded
            .get(&name)
            .map_or(catalog.folder_expanded.as_str(), String::as_str)
    } else {
        catalog
            .folder_names
            .get(&name)
            .map_or(catalog.folder.as_str(), String::as_str)
    }
}

fn icon_name(path_or_name: &str) -> String {
    path_or_name
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(path_or_name)
        .to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_exact_flutter_material_file_icons() {
        assert_eq!(file_asset("src/main.rs"), "rust.svg");
        assert_eq!(file_asset("widget.test.ts"), "test-ts.svg");
        assert_eq!(file_asset("Dockerfile"), "docker.svg");
        assert_eq!(file_asset("unknown.extension"), "file.svg");
    }

    #[test]
    fn resolves_exact_flutter_material_folder_icons() {
        assert_eq!(directory_asset("src", false), "folder-src.svg");
        assert_eq!(directory_asset("src", true), "folder-src-open.svg");
        assert_eq!(directory_asset("anything", false), "folder.svg");
        assert_eq!(directory_asset("anything", true), "folder-open.svg");
    }
}
