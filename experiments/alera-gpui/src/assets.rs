use anyhow::Result;
use gpui::{AssetSource, SharedString};
use rust_embed::Embed;

#[derive(Embed)]
#[folder = "assets/"]
struct EmbeddedAssets;

pub struct AleraAssets;

impl AleraAssets {
    pub fn raw_bytes(path: &str) -> Option<std::borrow::Cow<'static, [u8]>> {
        EmbeddedAssets::get(path).map(|file| file.data)
    }
}

impl AssetSource for AleraAssets {
    fn load(&self, path: &str) -> Result<Option<std::borrow::Cow<'static, [u8]>>> {
        Ok(crate::material_icon_layers::load_virtual_layer(path).or_else(|| Self::raw_bytes(path)))
    }

    fn list(&self, path: &str) -> Result<Vec<SharedString>> {
        let prefix = if path.is_empty() {
            String::new()
        } else {
            format!("{}/", path.trim_end_matches('/'))
        };
        Ok(EmbeddedAssets::iter()
            .filter_map(|asset| {
                let relative = asset.strip_prefix(&prefix)?;
                (!relative.contains('/')).then(|| SharedString::from(relative.to_owned()))
            })
            .collect())
    }
}
