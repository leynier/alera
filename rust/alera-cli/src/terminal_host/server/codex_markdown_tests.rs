use super::render_markdown;

#[test]
fn normalizes_newlines_and_trailing_stream_space() {
    assert_eq!(render_markdown("one\ntwo"), "one two");
}

#[test]
fn completes_default_remend_handlers() {
    assert_eq!(render_markdown("**bold"), "**bold**");
    assert_eq!(render_markdown("***bold italic"), "***bold italic***");
    assert_eq!(render_markdown("_italic"), "_italic_");
    assert_eq!(render_markdown("__italic"), "__italic__");
    assert_eq!(render_markdown("`code"), "`code`");
    assert_eq!(render_markdown("~~removed"), "~~removed~~");
    assert_eq!(render_markdown("$$x"), "$$x$$");
}

#[test]
fn protects_streaming_links_and_images_without_special_urls() {
    assert_eq!(
        render_markdown("[link](https://example"),
        "[link](streamdown:incomplete-link)"
    );
    assert_eq!(render_markdown("![image](https://example"), "");
    assert!(render_markdown("[link](https://example").contains("streamdown:"));
}

#[test]
fn protects_code_and_single_tilde_content() {
    assert_eq!(render_markdown("`20~25"), "`20~25`");
    assert_eq!(render_markdown("20~25"), "20\\~25");
    assert_eq!(render_markdown("```\n**raw\n```"), "```\n**raw\n```");
}

#[test]
fn handles_comparison_html_and_setext_streams() {
    assert_eq!(render_markdown("- > 25"), "- \\> 25");
    assert_eq!(render_markdown("hello <custom"), "hello");
    assert_eq!(render_markdown("Heading\n--"), "Heading\n--\u{200b}");
}

#[test]
fn preserves_complete_rich_markdown_structures() {
    let cases = [
        (
            "[link](https://example.test)",
            "[link](https://example.test)",
        ),
        (
            "![image](https://example.test/a.png)",
            "![image](https://example.test/a.png)",
        ),
        ("- one\n- two", "- one\n- two"),
        ("> quoted", "> quoted"),
        (
            "| a | b |\n| --- | --- |\n| 1 | 2 |",
            "| a | b |\n| --- | --- |\n| 1 | 2 |",
        ),
        ("<span>html</span>", "<span>html</span>"),
        ("\\*escaped\\*", "\\*escaped\\*"),
    ];
    for (input, expected) in cases {
        assert_eq!(render_markdown(input), expected, "input: {input}");
    }
}

#[test]
fn completes_nested_and_ambiguous_streams_without_touching_code() {
    assert_eq!(render_markdown("**bold and *italic"), "**bold and *italic*");
    assert_eq!(render_markdown("`**code**"), "`**code**`");
    assert_eq!(
        render_markdown("```\n[link](https://example\n```"),
        "```\n[link](https://example\n```"
    );
    assert_eq!(render_markdown("~~**removed"), "~~**removed**~~");
}

#[test]
fn completes_list_and_blockquote_prefixes_after_streaming() {
    assert_eq!(render_markdown("- **item"), "- **item**");
    assert_eq!(render_markdown("> `quote"), "> `quote`");
    assert_eq!(render_markdown("1. _item"), "1. _item_");
}

#[test]
fn completes_inline_and_block_math_after_streaming() {
    assert_eq!(render_markdown("$x"), "$x");
    assert_eq!(render_markdown("$$x"), "$$x$$");
    assert_eq!(render_markdown("before $$x"), "before $$x$$");
}
