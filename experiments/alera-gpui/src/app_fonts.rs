use std::borrow::Cow;

use gpui::TextSystem;

macro_rules! faces {
    ($stem:literal; $($weight:literal),+ $(,)?) => {
        [$(include_bytes!(concat!("../assets/fonts/static/", $stem, "-", stringify!($weight), ".ttf")).as_slice()),+]
    };
}

const INTER_FACES: [&[u8]; 9] = faces!("Inter"; 100, 200, 300, 400, 500, 600, 700, 800, 900);
const MONO_FACES: [&[u8]; 8] = faces!("JetBrainsMono"; 100, 200, 300, 400, 500, 600, 700, 800);
const LUCIDE_FONT: &[u8] = include_bytes!("../assets/fonts/Lucide-3.1.15.ttf");

pub fn register(text_system: &TextSystem) -> anyhow::Result<()> {
    // The pinned font-kit selector chooses registered faces, not variable
    // weight coordinates. Instances preserve the Flutter fonts' outlines.
    text_system.add_fonts(
        INTER_FACES
            .into_iter()
            .chain(MONO_FACES)
            .chain([LUCIDE_FONT])
            .map(Cow::Borrowed)
            .collect(),
    )
}

pub fn font_weight(family: &str, weight: f32) -> gpui::FontWeight {
    // CoreText gives these 200 faces weight -0.4. The pinned font-kit maps
    // that to ~237, so CSS matching at 200 otherwise selects the 100 face.
    // 250 selects the actual 200 outline; other families retain native matching.
    if cfg!(target_os = "macos")
        && matches!(family, "Inter" | "JetBrains Mono")
        && weight == 200.0
    {
        gpui::FontWeight(250.0)
    } else {
        gpui::FontWeight(weight)
    }
}
