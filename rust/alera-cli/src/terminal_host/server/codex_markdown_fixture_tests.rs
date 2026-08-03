use super::render_markdown;

fn assert_cases(cases: &[(&str, &str)]) {
    for (input, expected) in cases {
        assert_eq!(render_markdown(input), *expected, "input: {input}");
    }
}

#[test]
fn matches_remend_emphasis_fixtures() {
    assert_cases(&[
        ("Text with **bold", "Text with **bold**"),
        ("**xxx*", "**xxx**"),
        ("**first** and **second", "**first** and **second**"),
        ("Text with ***bold-italic", "Text with ***bold-italic***"),
        ("*italic* **bold** ***both", "*italic* **bold** ***both***"),
        ("***bold-italic with `code", "***bold-italic with `code***`"),
        (
            "Combined **bold and *italic*** text",
            "Combined **bold and *italic*** text",
        ),
        ("Text with __italic", "Text with __italic__"),
        ("__xxx_", "__xxx__"),
        ("Text with _italic", "Text with _italic_"),
        ("234234*123", "234234*123"),
        ("hello*world", "hello*world"),
        (
            "\\*escaped asterisk and *italic",
            "\\*escaped asterisk and *italic*",
        ),
        ("some_variable_name", "some_variable_name"),
        ("café_price", "café_price"),
        (
            "test_var and _incomplete italic",
            "test_var and _incomplete italic_",
        ),
        ("~~strike", "~~strike~~"),
        ("~~strike~", "~~strike~~"),
        ("~~**removed", "~~**removed**~~"),
    ]);
}

#[test]
fn matches_remend_code_and_escape_fixtures() {
    assert_cases(&[
        ("Text with `code", "Text with `code`"),
        ("`incomplete", "`incomplete`"),
        (
            "```python print(\"Hello\")``",
            "```python print(\"Hello\")```",
        ),
        (
            "```\ncode block with `backtick\n```",
            "```\ncode block with `backtick\n```",
        ),
        (
            "```javascript\nconst x = `template",
            "```javascript\nconst x = `template",
        ),
        ("```\nblock\n```\n`inline", "```\nblock\n``` `inline`"),
        ("\\`not code\\` **bold", "\\`not code\\` **bold**"),
        ("`**bold`", "`**bold`"),
        ("`*italic`", "`*italic`"),
        ("`~~strikethrough`", "`~~strikethrough`"),
        ("**bold", "**bold**"),
        ("*italic", "*italic*"),
        ("\\**not bold", "\\**not bold**"),
        ("\\\\*actually italic", "\\\\*actually italic"),
        ("\\*not italic", "\\*not italic"),
    ]);
}

#[test]
fn matches_remend_link_and_image_fixtures() {
    assert_cases(&[
        (
            "Text with [incomplete link",
            "Text with [incomplete link](streamdown:incomplete-link)",
        ),
        (
            "[outer [nested] text](incomplete",
            "[outer [nested] text](streamdown:incomplete-link)",
        ),
        (
            "[link with [inner] content](http://incomplete",
            "[link with [inner] content](streamdown:incomplete-link)",
        ),
        (
            "[link with [brackets] inside](https://example.com)",
            "[link with [brackets] inside](https://example.com)",
        ),
        (
            "Text [outer [inner",
            "Text [outer [inner](streamdown:incomplete-link)",
        ),
        (
            "Text [outer [inner]",
            "Text [outer [inner]](streamdown:incomplete-link)",
        ),
        (
            "[link1 and [link2",
            "[link1 and [link2](streamdown:incomplete-link)",
        ),
        (
            "[first](url1) and [second",
            "[first](url1) and [second](streamdown:incomplete-link)",
        ),
        ("Text with ![incomplete image", "Text with "),
        ("![partial", ""),
        ("See ![the diag", "See "),
        ("![logo](./assets/log", ""),
        ("Text ![outer [inner]", "Text "),
        (
            "textContent ![image](https://example.com/path_name!!test.png)",
            "textContent ![image](https://example.com/path_name!!test.png)",
        ),
    ]);
}

#[test]
fn matches_remend_structural_and_math_fixtures() {
    assert_cases(&[
        ("Text with $$formula", "Text with $$formula$$"),
        ("$$formula$", "$$formula$$"),
        ("$$x = 1", "$$x = 1$$"),
        (
            "$$formula1$$ and $$formula2$$",
            "$$formula1$$ and $$formula2$$",
        ),
        ("Text with $formula", "Text with $formula"),
        ("Price is \\$100", "Price is \\$100"),
        (
            "* Item 1\n* Item 2\n* Item 3",
            "* Item 1\n* Item 2\n* Item 3",
        ),
        (
            "- Item 1\n- Item 2 with **bol",
            "- Item 1\n- Item 2 with **bol**",
        ),
        ("- **", "- **"),
        ("- __ text after", "- __ text after__"),
        ("> > **deeply nested bold", "> > **deeply nested bold**"),
        (
            "> > > triple nested *italic",
            "> > > triple nested *italic*",
        ),
        ("- [ ] **bold task", "- [ ] **bold task**"),
        ("- [ ] `code task", "- [ ] `code task`"),
        ("| **bold | next |", "| **bold | next |**"),
        ("| `code | next |", "| `code | next |`"),
        ("text <div class=\"test", "text"),
        (
            "text <!-- incomplete comment",
            "text <!-- incomplete comment",
        ),
        ("text <br>", "text <br>"),
        ("- > 25", "- \\> 25"),
        ("Heading\n--", "Heading\n--\u{200b}"),
        ("20~25", "20\\~25"),
        ("`20~25", "`20~25`"),
        ("\\*escaped\\*", "\\*escaped\\*"),
    ]);
}
