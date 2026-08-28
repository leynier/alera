use gpui::{
    div, img, prelude::FluentBuilder as _, px, relative, AnyElement, App, CursorStyle, FontWeight,
    InteractiveElement as _, IntoElement, ObjectFit, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, StyledImage as _, Window,
};
use gpui_component::text::{
    markdown_ast::Node, MarkdownNode, MarkdownParseContext, MarkdownPlugin, TextView,
};

use crate::{
    icons::{icon, AleraIcon},
    markdown_images, theme,
};

const MARKDOWN_IMAGE_PLUGIN: &str = "alera-markdown-image";

#[derive(Clone)]
struct MarkdownImageBlock {
    id: usize,
    url: SharedString,
    alt: SharedString,
    link: Option<SharedString>,
}

#[derive(Clone)]
struct MarkdownHeadingBlock {
    id: usize,
    text: SharedString,
}

#[derive(Clone)]
enum MarkdownVisualBlock {
    Image(MarkdownImageBlock),
    Heading(MarkdownHeadingBlock),
}

struct AleraMarkdownImagePlugin;

impl MarkdownPlugin for AleraMarkdownImagePlugin {
    fn is_block(&self) -> bool {
        true
    }

    fn name(&self) -> &str {
        MARKDOWN_IMAGE_PLUGIN
    }

    fn parse(&self, node: &Node, cx: &MarkdownParseContext<'_>) -> Option<MarkdownNode> {
        let id = node
            .position()
            .map(|position| cx.offset().saturating_add(position.start.offset))
            .unwrap_or_default();
        let (data, text) = match node {
            Node::Paragraph(paragraph) => {
                let [child] = paragraph.children.as_slice() else {
                    return None;
                };
                let (image, link) = match child {
                    Node::Image(image) => (image, None),
                    Node::Link(link) => {
                        let [Node::Image(image)] = link.children.as_slice() else {
                            return None;
                        };
                        (image, Some(SharedString::from(link.url.clone())))
                    }
                    _ => return None,
                };
                let alt = SharedString::from(image.alt.clone());
                (
                    MarkdownVisualBlock::Image(MarkdownImageBlock {
                        id,
                        url: image.url.clone().into(),
                        alt: alt.clone(),
                        link,
                    }),
                    alt,
                )
            }
            Node::Heading(heading) if heading.depth == 1 => {
                let mut text = String::new();
                for child in &heading.children {
                    append_visible_markdown_text(child, &mut text);
                }
                let text = SharedString::from(text);
                (
                    MarkdownVisualBlock::Heading(MarkdownHeadingBlock {
                        id,
                        text: text.clone(),
                    }),
                    text,
                )
            }
            _ => return None,
        };
        Some(
            MarkdownNode::new(MARKDOWN_IMAGE_PLUGIN, data)
                .text(text)
                .markdown(cx.node_source(node).unwrap_or_default().to_owned()),
        )
    }

    fn render(&self, node: &MarkdownNode, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        render_markdown_image(node)
    }
}

pub(super) fn with_markdown_images(view: TextView) -> TextView {
    view.plugin(AleraMarkdownImagePlugin)
}

fn render_markdown_image(node: &MarkdownNode) -> AnyElement {
    let Some(block) = node.data::<MarkdownVisualBlock>().cloned() else {
        return div().into_any_element();
    };
    match block {
        MarkdownVisualBlock::Image(image) => render_image_block(image),
        MarkdownVisualBlock::Heading(heading) => render_heading_block(heading),
    }
}

fn render_image_block(image: MarkdownImageBlock) -> AnyElement {
    let label = if image.alt.is_empty() {
        "Markdown image".to_owned()
    } else {
        image.alt.to_string()
    };
    let source = markdown_images::image_source(&image.url.clone().into());
    let image_element = img(source)
        .max_w(relative(1.0))
        .object_fit(ObjectFit::ScaleDown)
        .with_loading(markdown_image_placeholder)
        .with_fallback(markdown_image_placeholder);
    let link = image.link.clone();
    div()
        .id(SharedString::from(format!("markdown-image-{}", image.id)))
        .w_full()
        .min_w_0()
        .mt(px(-4.0))
        .role(if link.is_some() {
            Role::Link
        } else {
            Role::Image
        })
        .aria_label(label)
        .when(link.is_some(), |container| {
            let link = link.expect("link presence was checked");
            container
                .focusable()
                .tab_stop(true)
                .cursor(CursorStyle::PointingHand)
                .on_click(move |_, _, cx| cx.open_url(&link))
        })
        .child(image_element)
        .into_any_element()
}

fn render_heading_block(heading: MarkdownHeadingBlock) -> AnyElement {
    div()
        .id(SharedString::from(format!(
            "markdown-heading-{}",
            heading.id
        )))
        .w_full()
        .h(px(64.0))
        .flex()
        .items_center()
        .border_b_1()
        .border_color(theme::border())
        .role(Role::Heading)
        .aria_label(heading.text.to_string())
        .text_size(px(34.0))
        .line_height(px(41.0))
        .font_weight(FontWeight::SEMIBOLD)
        .child(div().relative().top(px(-2.0)).child(heading.text))
        .into_any_element()
}

fn markdown_image_placeholder() -> AnyElement {
    div()
        .w(px(400.0))
        .max_w(relative(1.0))
        .h(px(300.0))
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(8.0))
        .border_1()
        .border_color(theme::border_subtle())
        .bg(theme::surface_raised())
        .child(icon(AleraIcon::ImageOff, 20.0, theme::text_muted()))
        .into_any_element()
}

fn append_visible_markdown_text(node: &Node, output: &mut String) {
    match node {
        Node::Text(text) => output.push_str(&text.value),
        Node::InlineCode(code) => output.push_str(&code.value),
        Node::Image(image) => output.push_str(&image.alt),
        Node::Break(_) => output.push(' '),
        Node::Emphasis(node) => {
            for child in &node.children {
                append_visible_markdown_text(child, output);
            }
        }
        Node::Strong(node) => {
            for child in &node.children {
                append_visible_markdown_text(child, output);
            }
        }
        Node::Delete(node) => {
            for child in &node.children {
                append_visible_markdown_text(child, output);
            }
        }
        Node::Link(node) => {
            for child in &node.children {
                append_visible_markdown_text(child, output);
            }
        }
        _ => {}
    }
}
