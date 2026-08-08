use std::borrow::Cow;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use gpui::{
    div, img, percentage, prelude::FluentBuilder as _, px, svg, Animation, AnimationExt as _,
    AnyElement, App, Image, ImageFormat, IntoElement as _, ParentElement as _, Rgba, Styled as _,
    Transformation,
};

const LUCIDE_FONT: &[u8] = include_bytes!("../assets/fonts/Lucide-3.1.15.ttf");
const INTER_FONT: &[u8] = include_bytes!("../assets/fonts/Inter-Variable.ttf");
const JETBRAINS_MONO_FONT: &[u8] = include_bytes!("../assets/fonts/JetBrainsMono-Variable.ttf");
const ALERA_LOGO: &[u8] = include_bytes!("../../../assets/logo/alera-logo-white.png");
static ALERA_LOGO_IMAGE: OnceLock<Arc<Image>> = OnceLock::new();

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AleraIcon {
    Activity,
    Add,
    Agent,
    Ai,
    AppWindow,
    ArrowRightToLine,
    Back,
    Check,
    CheckCheck,
    Cancel,
    CloseFullscreen,
    CollapseAll,
    ChevronDown,
    ChevronRight,
    ChevronUp,
    ChevronsLeft,
    ChevronsRight,
    Close,
    Code,
    Copy,
    Cut,
    Delete,
    Diff,
    Download,
    Duplicate,
    Edit,
    Error,
    ExpandAll,
    Hidden,
    External,
    File,
    Files,
    Folder,
    FolderOpen,
    FolderSpecial,
    GitBranch,
    GitCommit,
    GitGraph,
    GitDiscard,
    GitFetch,
    GitFork,
    GitPull,
    GitPullRequest,
    GitPublish,
    GitPush,
    GitRefresh,
    GitStage,
    GitStash,
    GitStashPop,
    GitSync,
    GitUnstage,
    Home,
    Info,
    Keyboard,
    Link,
    List,
    LayoutGrid,
    Loading,
    More,
    MobileDevice,
    NewFile,
    NewFolder,
    Notifications,
    Paste,
    Pin,
    PinOff,
    OpenInFull,
    Quota,
    Refresh,
    Replace,
    Preview,
    Restore,
    Save,
    Search,
    Server,
    Settings,
    Success,
    SidebarToggle,
    Tag,
    Terminal,
    Text,
    TextSearch,
    Theme,
    Tune,
    Visible,
    Workflow,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AgentIcon {
    Agy,
    Amp,
    Claude,
    Codex,
    Copilot,
    Cursor,
    Grok,
    Kimi,
    MiniMax,
    OpenCode,
    Pi,
    Zai,
}

impl AgentIcon {
    fn asset(self) -> (&'static str, bool, bool) {
        match self {
            Self::Agy => ("agents/agy.png", true, false),
            Self::Amp => ("agents/amp.png", true, false),
            Self::Claude => ("agents/claude.svg", true, false),
            Self::Codex => ("agents/codex.svg", false, true),
            Self::Copilot => ("agents/copilot.svg", false, true),
            Self::Cursor => ("agents/cursor.png", true, false),
            Self::Grok => ("agents/grok.svg", false, true),
            Self::Kimi => ("agents/kimi.svg", true, false),
            Self::MiniMax => ("agents/minimax.svg", true, false),
            Self::OpenCode => ("agents/opencode.png", true, false),
            Self::Pi => ("agents/pi.svg", false, true),
            Self::Zai => ("agents/zai.svg", true, false),
        }
    }
}

impl AleraIcon {
    fn codicon_asset(self) -> Option<&'static str> {
        match self {
            Self::CloseFullscreen => Some("google-material-icons/close-fullscreen.svg"),
            Self::GitCommit => Some("codicons/check.svg"),
            Self::GitDiscard => Some("codicons/discard.svg"),
            Self::GitFetch => Some("codicons/git-fetch.svg"),
            Self::GitPull => Some("codicons/repo-pull.svg"),
            Self::GitPublish => Some("codicons/cloud-upload.svg"),
            Self::GitPush => Some("codicons/repo-push.svg"),
            Self::GitRefresh => Some("codicons/refresh.svg"),
            Self::GitStage => Some("codicons/add.svg"),
            Self::GitStash => Some("codicons/git-stash.svg"),
            Self::GitStashPop => Some("codicons/git-stash-pop.svg"),
            Self::GitSync => Some("codicons/sync.svg"),
            Self::GitUnstage => Some("codicons/remove.svg"),
            Self::OpenInFull => Some("google-material-icons/open-in-full.svg"),
            _ => None,
        }
    }

    fn font_and_codepoint(self) -> (&'static str, u32) {
        match self {
            Self::Activity => ("lucide", 57400),
            Self::Add => ("lucide", 57661),
            Self::Agent => ("lucide", 57787),
            Self::Ai => ("lucide", 58386),
            Self::AppWindow => ("lucide", 58406),
            Self::ArrowRightToLine => ("lucide", 58457),
            Self::Back => ("lucide", 57416),
            Self::Check => ("lucide", 57452),
            Self::CheckCheck => ("lucide", 58254),
            Self::Cancel => ("lucide", 57476),
            Self::CloseFullscreen => unreachable!("SVG-backed icon"),
            Self::CollapseAll => ("lucide", 57896),
            Self::ChevronDown => ("lucide", 57453),
            Self::ChevronRight => ("lucide", 57455),
            Self::ChevronUp => ("lucide", 57456),
            Self::ChevronsLeft => ("lucide", 57458),
            Self::ChevronsRight => ("lucide", 57459),
            Self::Close => ("lucide", 57778),
            Self::Code => ("lucide", 57491),
            Self::Copy => ("lucide", 57502),
            Self::Cut => ("lucide", 57678),
            Self::Delete => ("lucide", 57742),
            Self::Diff => ("lucide", 58201),
            Self::Download => ("lucide", 57522),
            Self::Duplicate => ("lucide", 58365),
            Self::Edit => ("lucide", 57849),
            Self::Error => ("lucide", 57463),
            Self::ExpandAll => ("lucide", 57873),
            Self::Hidden => ("lucide", 57531),
            Self::External => ("lucide", 57529),
            Self::File => ("lucide", 57548),
            Self::Files => ("lucide", 57551),
            Self::Folder => ("lucide", 57559),
            Self::FolderOpen => ("lucide", 57927),
            Self::FolderSpecial => ("lucide", 58378),
            Self::GitBranch => ("lucide", 57570),
            Self::GitCommit => ("codicon", 0xeab2),
            Self::GitGraph => ("lucide", 58708),
            Self::GitDiscard => ("codicon", 0xeae2),
            Self::GitFetch => ("codicon", 0xecb2),
            Self::GitFork => ("lucide", 57997),
            Self::GitPull => ("codicon", 0xeb40),
            Self::GitPullRequest => ("lucide", 57573),
            Self::GitPublish => ("codicon", 0xeac3),
            Self::GitPush => ("codicon", 0xeb41),
            Self::GitRefresh => ("codicon", 0xeb37),
            Self::GitStage => ("codicon", 0xea60),
            Self::GitStash => ("codicon", 0xec26),
            Self::GitStashPop => ("codicon", 0xec28),
            Self::GitSync => ("codicon", 0xea77),
            Self::GitUnstage => ("codicon", 0xeb3b),
            Self::Home => ("lucide", 57589),
            Self::Info => ("lucide", 57593),
            Self::Keyboard => ("lucide", 57988),
            Self::Link => ("lucide", 57602),
            Self::List => ("lucide", 57606),
            Self::LayoutGrid => ("lucide", 57599),
            Self::Loading => ("lucide", 57610),
            Self::More => ("lucide", 57526),
            Self::MobileDevice => ("lucide", 57699),
            Self::NewFile => ("lucide", 57545),
            Self::NewFolder => ("lucide", 57561),
            Self::Notifications => ("lucide", 57892),
            Self::Paste => ("lucide", 57477),
            Self::Pin => ("lucide", 57945),
            Self::PinOff => ("lucide", 58038),
            Self::Preview => ("lucide", 58678),
            Self::OpenInFull => unreachable!("SVG-backed icon"),
            Self::Quota => ("lucide", 57791),
            Self::Refresh => ("lucide", 57669),
            Self::Replace => ("lucide", 58331),
            Self::Restore => ("lucide", 57845),
            Self::Save => ("lucide", 57677),
            Self::Search => ("lucide", 57681),
            Self::Server => ("lucide", 57683),
            Self::Settings => ("lucide", 57684),
            Self::SidebarToggle => ("lucide", 57642),
            Self::Success => ("lucide", 57894),
            Self::Tag => ("lucide", 57727),
            Self::Terminal => ("lucide", 57729),
            Self::Text => ("lucide", 57752),
            Self::TextSearch => ("lucide", 58797),
            Self::Theme => ("lucide", 57630),
            Self::Tune => ("lucide", 58010),
            Self::Visible => ("lucide", 57530),
            Self::Workflow => ("lucide", 58405),
        }
    }
}

pub fn register_fonts(cx: &App) {
    cx.text_system()
        .add_fonts(vec![
            Cow::Borrowed(LUCIDE_FONT),
            Cow::Borrowed(INTER_FONT),
            Cow::Borrowed(JETBRAINS_MONO_FONT),
        ])
        .expect("failed to register Alera fonts");
}

pub fn icon(kind: AleraIcon, size: f32, color: Rgba) -> AnyElement {
    // Loading is an active state, not a static glyph. Routing it through the
    // shared spinner keeps every caller animated, including toolbar buttons
    // and empty states that only receive an `AleraIcon` value.
    if kind == AleraIcon::Loading {
        return loading_indicator(size, color);
    }
    if let Some(asset) = kind.codicon_asset() {
        return svg()
            .path(asset)
            .w(px(size))
            .h(px(size))
            .text_color(color)
            .into_any_element();
    }
    let (font, codepoint) = kind.font_and_codepoint();
    let glyph = char::from_u32(codepoint).expect("Alera icon codepoint must be valid");
    div()
        .flex()
        .items_center()
        .justify_center()
        .w(px(size))
        .h(px(size))
        .font_family(font)
        .text_size(px(size))
        .line_height(px(size))
        .text_color(color)
        .child(glyph.to_string())
        .into_any_element()
}

pub fn loading_indicator(size: f32, color: Rgba) -> AnyElement {
    // Keep this in sync with Flutter's AleraTokens.durationSpin.
    svg()
        .path("lucide/loader-circle.svg")
        .w(px(size))
        .h(px(size))
        .text_color(color)
        .with_animation(
            "alera-loading-indicator",
            Animation::new(Duration::from_millis(1200)).repeat(),
            |icon, delta| icon.with_transformation(Transformation::rotate(percentage(delta))),
        )
        .into_any_element()
}

/// The sidebar agent spinner uses the same slower cadence as Flutter's
/// shared `AgentRunSpinner` while keeping the Lucide loader-circle geometry.
pub fn agent_loading_indicator(size: f32, color: Rgba) -> AnyElement {
    svg()
        .path("lucide/loader-circle.svg")
        .w(px(size))
        .h(px(size))
        .text_color(color)
        .with_animation(
            "alera-agent-loading-indicator",
            Animation::new(Duration::from_millis(1400)).repeat(),
            |icon, delta| icon.with_transformation(Transformation::rotate(percentage(delta))),
        )
        .into_any_element()
}

pub fn agent_icon(kind: AgentIcon, size: f32, color: Rgba) -> AnyElement {
    let (path, raster, tintable) = kind.asset();
    if raster {
        return img(path).w(px(size)).h(px(size)).into_any_element();
    }
    svg()
        .path(path)
        .w(px(size))
        .h(px(size))
        .when(tintable, |icon| icon.text_color(color))
        .into_any_element()
}

pub fn alera_logo(size: f32) -> AnyElement {
    let image = ALERA_LOGO_IMAGE
        .get_or_init(|| Arc::new(Image::from_bytes(ImageFormat::Png, ALERA_LOGO.to_vec())))
        .clone();
    img(image).w(px(size)).h(px(size)).into_any_element()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn semantic_icons_resolve_to_valid_glyphs() {
        for icon in [
            AleraIcon::Add,
            AleraIcon::Cancel,
            AleraIcon::Delete,
            AleraIcon::GitCommit,
            AleraIcon::GitFetch,
            AleraIcon::GitFork,
            AleraIcon::Notifications,
            AleraIcon::Success,
            AleraIcon::Tag,
        ] {
            let (_, codepoint) = icon.font_and_codepoint();
            assert!(char::from_u32(codepoint).is_some());
        }
    }

    #[test]
    fn status_icons_match_flutter_lucide_codepoints() {
        assert_eq!(AleraIcon::Check.font_and_codepoint().1, 57452);
        assert_eq!(AleraIcon::Loading.font_and_codepoint().1, 57610);
        assert_eq!(AleraIcon::Cancel.font_and_codepoint().1, 57476);
        assert_eq!(AleraIcon::Notifications.font_and_codepoint().1, 57892);
        assert_eq!(AleraIcon::Success.font_and_codepoint().1, 57894);
    }
}
