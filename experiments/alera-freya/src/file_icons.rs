use std::collections::HashMap;
use std::sync::OnceLock;

use freya::prelude::*;
use include_dir::{Dir, include_dir};
use serde::Deserialize;

use crate::MUTED;

const MANIFEST_JSON: &str = include_str!("../../alera-gpui/assets/material-icons/manifest.json");
static ICONS: Dir<'_> =
    include_dir!("$CARGO_MANIFEST_DIR/../alera-gpui/assets/material-icons/icons");

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

pub(crate) fn file_icon(
    path_or_name: &str,
    is_directory: bool,
    is_expanded: bool,
    is_symlink: bool,
    size: f32,
) -> Element {
    if is_symlink {
        return SvgViewer::new(freya::icons::lucide::link())
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element();
    }
    let asset = if is_directory {
        directory_asset(path_or_name, is_expanded)
    } else {
        file_asset(path_or_name)
    };
    let Some(file) = ICONS.get_file(asset) else {
        return SvgViewer::new(if is_directory {
            freya::icons::lucide::folder()
        } else {
            freya::icons::lucide::file()
        })
        .width(Size::px(size))
        .height(Size::px(size))
        .color(MUTED)
        .into_element();
    };
    SvgViewer::new((asset, file.contents()))
        .width(Size::px(size))
        .height(Size::px(size))
        .into_element()
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
    fn resolves_the_same_material_assets_as_flutter() {
        assert_eq!(file_asset("bun.lock"), "bun.svg");
        assert_eq!(file_asset("package.json"), "nodejs.svg");
        assert_eq!(file_asset("README.md"), "readme.svg");
        assert_eq!(directory_asset("src", false), "folder-src.svg");
        assert_eq!(directory_asset("src", true), "folder-src-open.svg");
    }
}
